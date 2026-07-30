const std = @import("std");

const pb = @import("database_proto");
const c = @import("sqlite_c").c;

pub const sqlite_version_number: u32 = 3_053_004;
pub const max_database_bytes: usize = 64 * 1024 * 1024;
pub const max_sql_bytes: usize = 1024 * 1024;
pub const max_request_id_bytes: usize = 128;
pub const max_statements: usize = 32;
pub const max_parameters: usize = 1024;
pub const max_query_rows: usize = 1000;
pub const max_query_bytes: usize = 4 * 1024 * 1024;
pub const idempotency_window_entries: u64 = 10_000;

const page_size: usize = 4096;
const snapshot_magic = "RSQL";
const snapshot_version: u32 = 1;
const snapshot_header_bytes = 4 + 4 + 8 + std.crypto.hash.sha2.Sha256.digest_length;

pub const Error = error{
    OutOfMemory,
    OpenFailed,
    SqliteFailure,
    InvalidRequest,
    InvalidSnapshot,
    SnapshotTooLarge,
};

const AuthorizerMode = enum {
    internal,
    write,
    read,
};

const SqlFailure = struct {
    code: i32,
    message: []u8,

    fn deinit(self: *SqlFailure, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        self.* = undefined;
    }
};

const StatementOutcome = union(enum) {
    ok: pb.StatementResult,
    sql_error: SqlFailure,
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    db: *c.sqlite3,
    authorizer_mode: *AuthorizerMode,

    pub fn init(allocator: std.mem.Allocator) Error!Database {
        var self = try openEmpty(allocator);
        errdefer self.deinit();
        try self.initializeSchema();
        return self;
    }

    fn openEmpty(allocator: std.mem.Allocator) Error!Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(
            ":memory:",
            &db,
            c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX,
            null,
        );
        if (rc != c.SQLITE_OK or db == null) {
            if (db) |handle| _ = c.sqlite3_close_v2(handle);
            return error.OpenFailed;
        }
        const authorizer_mode = allocator.create(AuthorizerMode) catch {
            _ = c.sqlite3_close_v2(db.?);
            return error.OutOfMemory;
        };
        errdefer allocator.destroy(authorizer_mode);
        authorizer_mode.* = .internal;
        const self: Database = .{ .allocator = allocator, .db = db.?, .authorizer_mode = authorizer_mode };
        errdefer _ = c.sqlite3_close_v2(self.db);
        if (c.sqlite3_libversion_number() != @as(c_int, @intCast(sqlite_version_number))) {
            return error.SqliteFailure;
        }
        if (c.sqlite3_extended_result_codes(self.db, 1) != c.SQLITE_OK) return error.SqliteFailure;
        if (c.sqlite3_db_config(self.db, c.SQLITE_DBCONFIG_DEFENSIVE, @as(c_int, 1), @as(?*c_int, null)) != c.SQLITE_OK) {
            return error.SqliteFailure;
        }
        if (c.sqlite3_db_config(self.db, c.SQLITE_DBCONFIG_TRUSTED_SCHEMA, @as(c_int, 0), @as(?*c_int, null)) != c.SQLITE_OK) {
            return error.SqliteFailure;
        }
        if (c.sqlite3_db_config(self.db, c.SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, @as(c_int, 0), @as(?*c_int, null)) != c.SQLITE_OK) {
            return error.SqliteFailure;
        }
        if (c.sqlite3_db_config(self.db, c.SQLITE_DBCONFIG_ENABLE_TRIGGER, @as(c_int, 0), @as(?*c_int, null)) != c.SQLITE_OK) {
            return error.SqliteFailure;
        }
        _ = c.sqlite3_limit(self.db, c.SQLITE_LIMIT_SQL_LENGTH, @intCast(max_sql_bytes));
        _ = c.sqlite3_limit(self.db, c.SQLITE_LIMIT_LENGTH, @intCast(max_database_bytes));
        if (c.sqlite3_set_authorizer(self.db, authorize, authorizer_mode) != c.SQLITE_OK) return error.SqliteFailure;
        return self;
    }

    pub fn deinit(self: *Database) void {
        _ = c.sqlite3_close_v2(self.db);
        self.allocator.destroy(self.authorizer_mode);
        self.* = undefined;
    }

    fn initializeSchema(self: *Database) Error!void {
        self.authorizer_mode.* = .internal;
        try self.execInternal("PRAGMA page_size=4096");
        try self.execInternal("PRAGMA journal_mode=MEMORY");
        try self.execInternal("PRAGMA foreign_keys=ON");
        try self.execInternal("PRAGMA max_page_count=16384");
        try self.execInternal(
            \\CREATE TABLE __raft_sqlite_meta (
            \\  id INTEGER PRIMARY KEY CHECK (id = 1),
            \\  format_version INTEGER NOT NULL,
            \\  applied_index INTEGER NOT NULL
            \\) STRICT;
        );
        try self.execInternal("INSERT INTO __raft_sqlite_meta VALUES (1, 1, 0)");
        try self.execInternal(
            \\CREATE TABLE __raft_sqlite_requests (
            \\  request_id TEXT PRIMARY KEY,
            \\  request_hash BLOB NOT NULL,
            \\  response BLOB NOT NULL,
            \\  applied_index INTEGER NOT NULL
            \\) STRICT;
        );
        try self.execInternal(
            "CREATE INDEX __raft_sqlite_requests_applied ON __raft_sqlite_requests(applied_index)",
        );
    }

    pub fn apply(
        self: *Database,
        allocator: std.mem.Allocator,
        request: pb.ExecuteRequest,
        request_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8,
        applied_index: u64,
    ) Error![]u8 {
        if (!validExecuteRequest(request)) return self.recordInvalidRequest(allocator, request, request_hash, applied_index);

        self.authorizer_mode.* = .internal;
        try self.execInternal("BEGIN IMMEDIATE");
        var active = true;
        errdefer if (active) self.execInternal("ROLLBACK") catch {};

        if (try self.lookupRequest(allocator, request.request_id)) |stored| {
            defer allocator.free(stored.hash);
            if (std.mem.eql(u8, stored.hash, &request_hash)) {
                try self.updateAppliedIndex(applied_index);
                try self.execInternal("COMMIT");
                active = false;
                return stored.response;
            }
            allocator.free(stored.response);
            const encoded = try encodeExecuteResponse(allocator, .{
                .code = .EXECUTE_CODE_REQUEST_CONFLICT,
                .error_message = "request_id was already used for a different request",
                .applied_index = applied_index,
            });
            errdefer allocator.free(encoded);
            try self.updateAppliedIndex(applied_index);
            try self.execInternal("COMMIT");
            active = false;
            return encoded;
        }

        try self.execInternal("SAVEPOINT user_sql");
        var response: pb.ExecuteResponse = .{
            .code = .EXECUTE_CODE_OK,
            .applied_index = applied_index,
        };
        defer response.deinit(allocator);
        var sql_failure: ?SqlFailure = null;
        defer if (sql_failure) |*failure| failure.deinit(allocator);

        for (request.statements.items) |statement| {
            const outcome = try self.executeStatement(allocator, statement);
            switch (outcome) {
                .ok => |result| try response.results.append(allocator, result),
                .sql_error => |failure| {
                    sql_failure = failure;
                    break;
                },
            }
        }

        if (sql_failure) |failure| {
            self.authorizer_mode.* = .internal;
            try self.execInternal("ROLLBACK TO user_sql");
            try self.execInternal("RELEASE user_sql");
            response.results.clearRetainingCapacity();
            response.code = if (failure.code == c.SQLITE_FULL or failure.code == c.SQLITE_TOOBIG)
                .EXECUTE_CODE_RESOURCE_EXHAUSTED
            else
                .EXECUTE_CODE_SQL_ERROR;
            response.sqlite_code = failure.code;
            response.error_message = failure.message;
            sql_failure = null;
        } else {
            self.authorizer_mode.* = .internal;
            try self.execInternal("RELEASE user_sql");
        }

        const encoded = try encodeExecuteResponse(allocator, response);
        errdefer allocator.free(encoded);
        try self.insertRequest(request.request_id, &request_hash, encoded, applied_index);
        try self.pruneRequests(applied_index);
        try self.updateAppliedIndex(applied_index);
        try self.execInternal("COMMIT");
        active = false;
        return encoded;
    }

    fn recordInvalidRequest(
        self: *Database,
        allocator: std.mem.Allocator,
        request: pb.ExecuteRequest,
        request_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8,
        applied_index: u64,
    ) Error![]u8 {
        self.authorizer_mode.* = .internal;
        try self.execInternal("BEGIN IMMEDIATE");
        var active = true;
        errdefer if (active) self.execInternal("ROLLBACK") catch {};
        const encoded = try encodeExecuteResponse(allocator, .{
            .code = .EXECUTE_CODE_INVALID_REQUEST,
            .error_message = "invalid execute request",
            .applied_index = applied_index,
        });
        errdefer allocator.free(encoded);
        if (request.request_id.len > 0 and request.request_id.len <= max_request_id_bytes) {
            if (try self.lookupRequest(allocator, request.request_id)) |stored| {
                defer allocator.free(stored.hash);
                if (std.mem.eql(u8, stored.hash, &request_hash)) {
                    allocator.free(encoded);
                    try self.updateAppliedIndex(applied_index);
                    try self.execInternal("COMMIT");
                    active = false;
                    return stored.response;
                }
                allocator.free(stored.response);
            } else {
                try self.insertRequest(request.request_id, &request_hash, encoded, applied_index);
                try self.pruneRequests(applied_index);
            }
        }
        try self.updateAppliedIndex(applied_index);
        try self.execInternal("COMMIT");
        active = false;
        return encoded;
    }

    pub fn advance(self: *Database, applied_index: u64) Error!void {
        self.authorizer_mode.* = .internal;
        try self.execInternal("BEGIN IMMEDIATE");
        var active = true;
        errdefer if (active) self.execInternal("ROLLBACK") catch {};
        try self.updateAppliedIndex(applied_index);
        try self.execInternal("COMMIT");
        active = false;
    }

    pub fn query(self: *Database, allocator: std.mem.Allocator, request: pb.QueryRequest) Error!pb.QueryResponse {
        if (request.sql.len == 0 or request.sql.len > max_sql_bytes or
            std.mem.indexOfScalar(u8, request.sql, 0) != null or request.parameters.items.len > max_parameters)
        {
            return error.InvalidRequest;
        }

        self.authorizer_mode.* = .read;
        var statement: ?*c.sqlite3_stmt = null;
        var tail: [*c]const u8 = null;
        const prepare_rc = c.sqlite3_prepare_v3(
            self.db,
            request.sql.ptr,
            @intCast(request.sql.len),
            c.SQLITE_PREPARE_PERSISTENT,
            &statement,
            &tail,
        );
        if (prepare_rc != c.SQLITE_OK or statement == null) return error.InvalidRequest;
        defer _ = c.sqlite3_finalize(statement.?);
        if (!tailIsEmpty(request.sql, tail) or c.sqlite3_stmt_readonly(statement.?) == 0) return error.InvalidRequest;
        if (c.sqlite3_bind_parameter_count(statement.?) != request.parameters.items.len) return error.InvalidRequest;
        for (request.parameters.items, 1..) |value, index| {
            if (bindValue(statement.?, @intCast(index), value) != c.SQLITE_OK) return error.InvalidRequest;
        }

        var response: pb.QueryResponse = .{};
        errdefer response.deinit(allocator);
        const column_count: usize = @intCast(c.sqlite3_column_count(statement.?));
        if (column_count > 128) return error.InvalidRequest;
        for (0..column_count) |index| {
            const name = c.sqlite3_column_name(statement.?, @intCast(index));
            const copy = try allocator.dupe(u8, if (name == null) "" else std.mem.span(name));
            try response.columns.append(allocator, .{ .name = copy });
        }

        var result_bytes: usize = 0;
        while (true) {
            const rc = c.sqlite3_step(statement.?);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SqliteFailure;
            if (response.rows.items.len >= max_query_rows) return error.InvalidRequest;
            var row: pb.Row = .{};
            errdefer row.deinit(allocator);
            for (0..column_count) |index| {
                const value = try columnValue(allocator, statement.?, @intCast(index), &result_bytes);
                try row.values.append(allocator, value);
            }
            try response.rows.append(allocator, row);
        }
        return response;
    }

    pub fn takeSnapshot(self: *Database, allocator: std.mem.Allocator, applied_index: u64) Error![]u8 {
        try self.advance(applied_index);
        var image_size: c.sqlite3_int64 = 0;
        const image = c.sqlite3_serialize(self.db, "main", &image_size, 0);
        if (image == null) return error.OutOfMemory;
        defer c.sqlite3_free(image);
        if (image_size < 0 or image_size > max_database_bytes) return error.SnapshotTooLarge;
        const payload_len: usize = @intCast(image_size);
        const snapshot_data = allocator.alloc(u8, snapshot_header_bytes + payload_len) catch return error.OutOfMemory;
        errdefer allocator.free(snapshot_data);
        @memcpy(snapshot_data[0..4], snapshot_magic);
        std.mem.writeInt(u32, snapshot_data[4..8], snapshot_version, .little);
        std.mem.writeInt(u64, snapshot_data[8..16], payload_len, .little);
        std.crypto.hash.sha2.Sha256.hash(image[0..payload_len], snapshot_data[16..snapshot_header_bytes], .{});
        @memcpy(snapshot_data[snapshot_header_bytes..], image[0..payload_len]);
        return snapshot_data;
    }

    pub fn restore(self: *Database, metadata_index: u64, snapshot_data: []const u8) Error!void {
        if (snapshot_data.len < snapshot_header_bytes or !std.mem.eql(u8, snapshot_data[0..4], snapshot_magic)) {
            return error.InvalidSnapshot;
        }
        if (std.mem.readInt(u32, snapshot_data[4..8], .little) != snapshot_version) return error.InvalidSnapshot;
        const payload_len = std.mem.readInt(u64, snapshot_data[8..16], .little);
        if (payload_len > max_database_bytes or payload_len != snapshot_data.len - snapshot_header_bytes) {
            return error.InvalidSnapshot;
        }
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        const payload = snapshot_data[snapshot_header_bytes..];
        std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
        if (!std.mem.eql(u8, &digest, snapshot_data[16..snapshot_header_bytes])) return error.InvalidSnapshot;

        var candidate = try openEmpty(self.allocator);
        errdefer candidate.deinit();
        const buffer = c.sqlite3_malloc64(max_database_bytes) orelse return error.OutOfMemory;
        @memcpy(@as([*]u8, @ptrCast(buffer))[0..payload.len], payload);
        const rc = c.sqlite3_deserialize(
            candidate.db,
            "main",
            @ptrCast(buffer),
            @intCast(payload.len),
            @intCast(max_database_bytes),
            c.SQLITE_DESERIALIZE_FREEONCLOSE | c.SQLITE_DESERIALIZE_RESIZEABLE,
        );
        if (rc != c.SQLITE_OK) {
            return error.InvalidSnapshot;
        }
        try candidate.checkIntegrity();
        if (try candidate.appliedIndex() != metadata_index) return error.InvalidSnapshot;
        candidate.authorizer_mode.* = .internal;
        try candidate.execInternal("PRAGMA max_page_count=16384");

        const old = self.db;
        const old_authorizer_mode = self.authorizer_mode;
        self.db = candidate.db;
        self.authorizer_mode = candidate.authorizer_mode;
        candidate.db = old;
        candidate.authorizer_mode = old_authorizer_mode;
        candidate.deinit();
    }

    pub fn serializedSize(self: *Database) Error!u64 {
        var size: c.sqlite3_int64 = 0;
        const ptr = c.sqlite3_serialize(self.db, "main", &size, c.SQLITE_SERIALIZE_NOCOPY);
        if (ptr != null) return @intCast(size);
        if (size < 0) return error.SqliteFailure;
        return @intCast(size);
    }

    pub fn appliedIndex(self: *Database) Error!u64 {
        self.authorizer_mode.* = .internal;
        const statement = try self.prepareInternal("SELECT applied_index FROM __raft_sqlite_meta WHERE id = 1");
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_step(statement) != c.SQLITE_ROW) return error.SqliteFailure;
        return @intCast(c.sqlite3_column_int64(statement, 0));
    }

    fn checkIntegrity(self: *Database) Error!void {
        self.authorizer_mode.* = .internal;
        const statement = try self.prepareInternal("PRAGMA quick_check");
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_step(statement) != c.SQLITE_ROW) return error.InvalidSnapshot;
        const text = c.sqlite3_column_text(statement, 0);
        if (text == null or !std.mem.eql(u8, std.mem.span(text), "ok")) return error.InvalidSnapshot;
    }

    fn executeStatement(self: *Database, allocator: std.mem.Allocator, input: pb.Statement) Error!StatementOutcome {
        self.authorizer_mode.* = .write;
        var statement: ?*c.sqlite3_stmt = null;
        var tail: [*c]const u8 = null;
        const prepare_rc = c.sqlite3_prepare_v3(
            self.db,
            input.sql.ptr,
            @intCast(input.sql.len),
            c.SQLITE_PREPARE_PERSISTENT,
            &statement,
            &tail,
        );
        if (prepare_rc != c.SQLITE_OK or statement == null) return .{ .sql_error = try self.sqlFailure(allocator) };
        defer _ = c.sqlite3_finalize(statement.?);
        if (!tailIsEmpty(input.sql, tail) or c.sqlite3_stmt_readonly(statement.?) != 0 or
            c.sqlite3_column_count(statement.?) != 0 or c.sqlite3_bind_parameter_count(statement.?) != input.parameters.items.len)
        {
            return .{ .sql_error = .{
                .code = c.SQLITE_MISUSE,
                .message = try allocator.dupe(u8, "statement is not an allowed mutation"),
            } };
        }
        for (input.parameters.items, 1..) |value, index| {
            const rc = bindValue(statement.?, @intCast(index), value);
            if (rc != c.SQLITE_OK) return .{ .sql_error = try self.sqlFailure(allocator) };
        }
        const step_rc = c.sqlite3_step(statement.?);
        if (step_rc != c.SQLITE_DONE) return .{ .sql_error = try self.sqlFailure(allocator) };
        return .{ .ok = .{
            .rows_affected = c.sqlite3_changes64(self.db),
            .last_insert_rowid = c.sqlite3_last_insert_rowid(self.db),
        } };
    }

    fn sqlFailure(self: *Database, allocator: std.mem.Allocator) Error!SqlFailure {
        const code = c.sqlite3_extended_errcode(self.db);
        if (code == c.SQLITE_NOMEM) return error.OutOfMemory;
        const raw = std.mem.span(c.sqlite3_errmsg(self.db));
        const message = allocator.dupe(u8, raw[0..@min(raw.len, 512)]) catch return error.OutOfMemory;
        return .{ .code = code, .message = message };
    }

    fn execInternal(self: *Database, sql: [*:0]const u8) Error!void {
        self.authorizer_mode.* = .internal;
        var message: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql, null, null, &message);
        if (message != null) c.sqlite3_free(message);
        if (rc == c.SQLITE_NOMEM) return error.OutOfMemory;
        if (rc != c.SQLITE_OK) return error.SqliteFailure;
    }

    fn prepareInternal(self: *Database, sql: [*:0]const u8) Error!*c.sqlite3_stmt {
        self.authorizer_mode.* = .internal;
        var statement: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &statement, null);
        if (rc == c.SQLITE_NOMEM) return error.OutOfMemory;
        if (rc != c.SQLITE_OK or statement == null) return error.SqliteFailure;
        return statement.?;
    }

    const StoredRequest = struct {
        hash: []u8,
        response: []u8,
    };

    fn lookupRequest(self: *Database, allocator: std.mem.Allocator, request_id: []const u8) Error!?StoredRequest {
        const statement = try self.prepareInternal(
            "SELECT request_hash, response FROM __raft_sqlite_requests WHERE request_id = ?1",
        );
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_bind_text(statement, 1, request_id.ptr, @intCast(request_id.len), c.SQLITE_TRANSIENT) != c.SQLITE_OK) {
            return error.SqliteFailure;
        }
        const rc = c.sqlite3_step(statement);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return error.SqliteFailure;
        const hash = try copyColumnBlob(allocator, statement, 0);
        errdefer allocator.free(hash);
        const response = try copyColumnBlob(allocator, statement, 1);
        return .{ .hash = hash, .response = response };
    }

    fn insertRequest(self: *Database, request_id: []const u8, hash: []const u8, response: []const u8, index: u64) Error!void {
        const statement = try self.prepareInternal(
            "INSERT INTO __raft_sqlite_requests(request_id, request_hash, response, applied_index) VALUES (?1, ?2, ?3, ?4)",
        );
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_bind_text(statement, 1, request_id.ptr, @intCast(request_id.len), c.SQLITE_TRANSIENT) != c.SQLITE_OK or
            c.sqlite3_bind_blob(statement, 2, hash.ptr, @intCast(hash.len), c.SQLITE_TRANSIENT) != c.SQLITE_OK or
            c.sqlite3_bind_blob(statement, 3, response.ptr, @intCast(response.len), c.SQLITE_TRANSIENT) != c.SQLITE_OK or
            c.sqlite3_bind_int64(statement, 4, @intCast(index)) != c.SQLITE_OK or
            c.sqlite3_step(statement) != c.SQLITE_DONE)
        {
            return error.SqliteFailure;
        }
    }

    fn pruneRequests(self: *Database, index: u64) Error!void {
        const minimum = index -| idempotency_window_entries;
        const statement = try self.prepareInternal("DELETE FROM __raft_sqlite_requests WHERE applied_index <= ?1");
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_bind_int64(statement, 1, @intCast(minimum)) != c.SQLITE_OK or
            c.sqlite3_step(statement) != c.SQLITE_DONE)
        {
            return error.SqliteFailure;
        }
    }

    fn updateAppliedIndex(self: *Database, index: u64) Error!void {
        const statement = try self.prepareInternal("UPDATE __raft_sqlite_meta SET applied_index = ?1 WHERE id = 1");
        defer _ = c.sqlite3_finalize(statement);
        if (c.sqlite3_bind_int64(statement, 1, @intCast(index)) != c.SQLITE_OK or
            c.sqlite3_step(statement) != c.SQLITE_DONE)
        {
            return error.SqliteFailure;
        }
    }
};

fn validExecuteRequest(request: pb.ExecuteRequest) bool {
    if (request.request_id.len == 0 or request.request_id.len > max_request_id_bytes or
        request.statements.items.len == 0 or request.statements.items.len > max_statements)
    {
        return false;
    }
    var parameters: usize = 0;
    for (request.statements.items) |statement| {
        if (statement.sql.len == 0 or statement.sql.len > max_sql_bytes or
            std.mem.indexOfScalar(u8, statement.sql, 0) != null)
        {
            return false;
        }
        parameters = std.math.add(usize, parameters, statement.parameters.items.len) catch return false;
        if (parameters > max_parameters) return false;
        for (statement.parameters.items) |value| {
            const kind = value.kind orelse return false;
            switch (kind) {
                .text_value => |text| if (text.len > max_database_bytes) return false,
                .blob_value => |blob| if (blob.len > max_database_bytes) return false,
                else => {},
            }
        }
    }
    return true;
}

fn bindValue(statement: *c.sqlite3_stmt, index: c_int, value: pb.Value) c_int {
    const kind = value.kind orelse return c.SQLITE_MISUSE;
    return switch (kind) {
        .null_value => c.sqlite3_bind_null(statement, index),
        .integer_value => |integer| c.sqlite3_bind_int64(statement, index, integer),
        .real_value => |real| c.sqlite3_bind_double(statement, index, real),
        .text_value => |text| c.sqlite3_bind_text(statement, index, text.ptr, @intCast(text.len), c.SQLITE_TRANSIENT),
        .blob_value => |blob| c.sqlite3_bind_blob(statement, index, blob.ptr, @intCast(blob.len), c.SQLITE_TRANSIENT),
    };
}

fn columnValue(
    allocator: std.mem.Allocator,
    statement: *c.sqlite3_stmt,
    index: c_int,
    result_bytes: *usize,
) Error!pb.Value {
    return switch (c.sqlite3_column_type(statement, index)) {
        c.SQLITE_NULL => .{ .kind = .{ .null_value = .NULL_VALUE } },
        c.SQLITE_INTEGER => .{ .kind = .{ .integer_value = c.sqlite3_column_int64(statement, index) } },
        c.SQLITE_FLOAT => .{ .kind = .{ .real_value = c.sqlite3_column_double(statement, index) } },
        c.SQLITE_TEXT => blk: {
            const len: usize = @intCast(c.sqlite3_column_bytes(statement, index));
            result_bytes.* = std.math.add(usize, result_bytes.*, len) catch return error.InvalidRequest;
            if (result_bytes.* > max_query_bytes) return error.InvalidRequest;
            const source = c.sqlite3_column_text(statement, index);
            const copy = allocator.dupe(u8, source[0..len]) catch return error.OutOfMemory;
            break :blk .{ .kind = .{ .text_value = copy } };
        },
        c.SQLITE_BLOB => blk: {
            const len: usize = @intCast(c.sqlite3_column_bytes(statement, index));
            result_bytes.* = std.math.add(usize, result_bytes.*, len) catch return error.InvalidRequest;
            if (result_bytes.* > max_query_bytes) return error.InvalidRequest;
            const source = c.sqlite3_column_blob(statement, index);
            const bytes: [*]const u8 = @ptrCast(source);
            const copy = allocator.dupe(u8, bytes[0..len]) catch return error.OutOfMemory;
            break :blk .{ .kind = .{ .blob_value = copy } };
        },
        else => return error.SqliteFailure,
    };
}

fn tailIsEmpty(sql: []const u8, tail: [*c]const u8) bool {
    if (tail == null) return true;
    const offset = @intFromPtr(tail) - @intFromPtr(sql.ptr);
    if (offset > sql.len) return false;
    for (sql[offset..]) |byte| {
        if (!std.ascii.isWhitespace(byte) and byte != ';') return false;
    }
    return true;
}

fn copyColumnBlob(allocator: std.mem.Allocator, statement: *c.sqlite3_stmt, index: c_int) Error![]u8 {
    const len: usize = @intCast(c.sqlite3_column_bytes(statement, index));
    const source = c.sqlite3_column_blob(statement, index);
    if (len > 0 and source == null) return error.SqliteFailure;
    const bytes: [*]const u8 = @ptrCast(source);
    return allocator.dupe(u8, bytes[0..len]) catch error.OutOfMemory;
}

fn encodeExecuteResponse(allocator: std.mem.Allocator, response: pb.ExecuteResponse) Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    response.encode(&output.writer, allocator) catch return error.OutOfMemory;
    return output.toOwnedSlice() catch error.OutOfMemory;
}

fn authorize(
    context: ?*anyopaque,
    action: c_int,
    argument1: [*c]const u8,
    argument2: [*c]const u8,
    _: [*c]const u8,
    _: [*c]const u8,
) callconv(.c) c_int {
    const mode: *AuthorizerMode = @ptrCast(@alignCast(context.?));
    if (mode.* == .internal) return c.SQLITE_OK;
    if (isProtectedName(argument1) or isProtectedName(argument2)) return c.SQLITE_DENY;
    switch (action) {
        c.SQLITE_ATTACH,
        c.SQLITE_DETACH,
        c.SQLITE_PRAGMA,
        c.SQLITE_TRANSACTION,
        c.SQLITE_SAVEPOINT,
        c.SQLITE_CREATE_TEMP_INDEX,
        c.SQLITE_CREATE_TEMP_TABLE,
        c.SQLITE_CREATE_TEMP_TRIGGER,
        c.SQLITE_CREATE_TEMP_VIEW,
        c.SQLITE_CREATE_TRIGGER,
        c.SQLITE_DROP_TRIGGER,
        c.SQLITE_CREATE_VTABLE,
        c.SQLITE_DROP_VTABLE,
        c.SQLITE_REINDEX,
        c.SQLITE_ANALYZE,
        => return c.SQLITE_DENY,
        c.SQLITE_FUNCTION => {
            const function_name = if (argument2 != null) std.mem.span(argument2) else if (argument1 != null) std.mem.span(argument1) else return c.SQLITE_DENY;
            if (isBannedFunction(function_name)) return c.SQLITE_DENY;
        },
        else => {},
    }
    if (mode.* == .read) {
        return switch (action) {
            c.SQLITE_SELECT, c.SQLITE_READ, c.SQLITE_FUNCTION, c.SQLITE_RECURSIVE => c.SQLITE_OK,
            else => c.SQLITE_DENY,
        };
    }
    return c.SQLITE_OK;
}

fn isProtectedName(value: [*c]const u8) bool {
    if (value == null) return false;
    return std.ascii.startsWithIgnoreCase(std.mem.span(value), "__raft_sqlite_");
}

fn isBannedFunction(name: []const u8) bool {
    const banned = [_][]const u8{
        "random",            "randomblob", "load_extension", "date",
        "time",              "datetime",   "julianday",      "unixepoch",
        "strftime",          "timediff",   "current_date",   "current_time",
        "current_timestamp",
    };
    for (banned) |candidate| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}

fn testHash(value: []const u8) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(value, &digest, .{});
    return digest;
}

test "SQLite amalgamation is pinned" {
    try std.testing.expectEqual(@as(c_int, @intCast(sqlite_version_number)), c.sqlite3_libversion_number());
    try std.testing.expectEqualStrings("3.53.4", std.mem.span(c.sqlite3_libversion()));
}

test "database applies an atomic parameterized batch and queries it" {
    const allocator = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var database = try Database.init(allocator);
    defer database.deinit();
    var request: pb.ExecuteRequest = .{ .request_id = "request-1" };
    try request.statements.append(scratch, .{ .sql = "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL) STRICT" });
    var insert: pb.Statement = .{ .sql = "INSERT INTO items(id, name) VALUES (?1, ?2)" };
    try insert.parameters.append(scratch, .{ .kind = .{ .integer_value = 7 } });
    try insert.parameters.append(scratch, .{ .kind = .{ .text_value = "seven" } });
    try request.statements.append(scratch, insert);
    const hash = testHash("request-1");
    const encoded = try database.apply(allocator, request, hash, 3);
    defer allocator.free(encoded);

    var response_reader: std.Io.Reader = .fixed(encoded);
    var response = try pb.ExecuteResponse.decode(&response_reader, allocator);
    defer response.deinit(allocator);
    try std.testing.expectEqual(pb.ExecuteCode.EXECUTE_CODE_OK, response.code);
    try std.testing.expectEqual(@as(usize, 2), response.results.items.len);
    try std.testing.expectEqual(@as(u64, 3), try database.appliedIndex());

    var query: pb.QueryRequest = .{ .sql = "SELECT name FROM items WHERE id = ?1" };
    try query.parameters.append(scratch, .{ .kind = .{ .integer_value = 7 } });
    var query_response = try database.query(allocator, query);
    defer query_response.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), query_response.rows.items.len);
    try std.testing.expectEqualStrings("seven", query_response.rows.items[0].values.items[0].kind.?.text_value);
}

test "database rolls back a batch that uses a nondeterministic function" {
    const allocator = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var database = try Database.init(allocator);
    defer database.deinit();
    var schema: pb.ExecuteRequest = .{ .request_id = "schema" };
    try schema.statements.append(scratch, .{ .sql = "CREATE TABLE items (id INTEGER PRIMARY KEY) STRICT" });
    const schema_response = try database.apply(allocator, schema, testHash("schema"), 1);
    allocator.free(schema_response);

    var request: pb.ExecuteRequest = .{ .request_id = "bad-batch" };
    try request.statements.append(scratch, .{ .sql = "INSERT INTO items VALUES (1)" });
    try request.statements.append(scratch, .{ .sql = "INSERT INTO items VALUES (random())" });
    const encoded = try database.apply(allocator, request, testHash("bad-batch"), 2);
    defer allocator.free(encoded);
    var response_reader: std.Io.Reader = .fixed(encoded);
    var response = try pb.ExecuteResponse.decode(&response_reader, allocator);
    defer response.deinit(allocator);
    try std.testing.expectEqual(pb.ExecuteCode.EXECUTE_CODE_SQL_ERROR, response.code);

    var query_response = try database.query(allocator, .{ .sql = "SELECT count(*) FROM items" });
    defer query_response.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 0), query_response.rows.items[0].values.items[0].kind.?.integer_value);
}

test "database deduplicates requests and atomically restores snapshots" {
    const allocator = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var source = try Database.init(allocator);
    defer source.deinit();
    var request: pb.ExecuteRequest = .{ .request_id = "once" };
    try request.statements.append(scratch, .{ .sql = "CREATE TABLE items (id INTEGER PRIMARY KEY) STRICT" });
    try request.statements.append(scratch, .{ .sql = "INSERT INTO items VALUES (1)" });
    const hash = testHash("once");
    const first = try source.apply(allocator, request, hash, 5);
    defer allocator.free(first);
    const duplicate = try source.apply(allocator, request, hash, 6);
    defer allocator.free(duplicate);
    try std.testing.expectEqualStrings(first, duplicate);

    const snapshot_data = try source.takeSnapshot(allocator, 6);
    defer allocator.free(snapshot_data);
    var restored = try Database.init(allocator);
    defer restored.deinit();
    try restored.restore(6, snapshot_data);
    var query_response = try restored.query(allocator, .{ .sql = "SELECT count(*) FROM items" });
    defer query_response.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 1), query_response.rows.items[0].values.items[0].kind.?.integer_value);

    var corrupt = try allocator.dupe(u8, snapshot_data);
    defer allocator.free(corrupt);
    corrupt[corrupt.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidSnapshot, restored.restore(6, corrupt));
    try std.testing.expectEqual(@as(u64, 6), try restored.appliedIndex());
}

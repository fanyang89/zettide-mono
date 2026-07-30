const std = @import("std");

const pb = @import("database_proto");
const raft = @import("raft_zig");
const state_machine = @import("state_machine.zig");

const ProposalProbe = struct {
    allocator: std.mem.Allocator,
    completed: bool = false,
    response: ?[]u8 = null,
    failure: ?raft.Error = null,

    fn deinit(self: *ProposalProbe) void {
        if (self.response) |response| self.allocator.free(response);
    }

    fn callback(self: *ProposalProbe) raft.ProposalCallback {
        return .{ .ctx = self, .function = complete };
    }

    fn complete(context: *anyopaque, result: raft.ProposalResult) void {
        const self: *ProposalProbe = @ptrCast(@alignCast(context));
        switch (result) {
            .ok => |response| {
                self.response = self.allocator.dupe(u8, response) catch {
                    self.failure = error.OutOfMemory;
                    self.completed = true;
                    return;
                };
            },
            .err => |err| self.failure = err,
        }
        self.completed = true;
    }
};

fn propose(allocator: std.mem.Allocator, raftor: *raft.Raftor, request: pb.ExecuteRequest) ![]u8 {
    const encoded = try state_machine.encodeExecuteCommand(allocator, request);
    defer allocator.free(encoded);
    var probe: ProposalProbe = .{ .allocator = allocator };
    defer probe.deinit();
    try raftor.propose(encoded, probe.callback());
    for (0..64) |_| {
        if (probe.completed) break;
        _ = try raftor.tick();
    }
    try std.testing.expect(probe.completed);
    try std.testing.expectEqual(@as(?raft.Error, null), probe.failure);
    const response = probe.response orelse return error.MissingResponse;
    probe.response = null;
    return response;
}

fn countRows(allocator: std.mem.Allocator, machine: *state_machine.SqliteStateMachine) !i64 {
    var response = try machine.query(allocator, .{ .sql = "SELECT count(*) FROM items" });
    defer response.deinit(allocator);
    return response.rows.items[0].values.items[0].kind.?.integer_value;
}

test "single-node WAL restores a SQLite snapshot before replaying its suffix" {
    const allocator = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const root_path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(root_path);
    const data_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/raft", .{root_path}, 0);
    defer allocator.free(data_dir);

    var config: raft.RaftorConfig = .{};
    config.raft.id = 1;
    config.raft.election_timeout_seed = 42;
    config.cluster_id = .{1} ++ .{0} ** 15;
    config.advertise_addr = "test://node-1";
    config.data_dir = data_dir;
    config.snapshot_entries_threshold = 0;

    var snapshot_index: u64 = 0;
    var final_index: u64 = 0;
    {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        var machine = try state_machine.SqliteStateMachine.init(allocator);
        defer machine.deinit();
        const node = try raft.Raftor.create(allocator, config, machine.stateMachine());
        defer node.destroy();
        try node.campaign();

        var schema: pb.ExecuteRequest = .{ .request_id = "schema" };
        try schema.statements.append(arena.allocator(), .{ .sql = "CREATE TABLE items (id INTEGER PRIMARY KEY) STRICT" });
        allocator.free(try propose(allocator, node, schema));
        try node.takeSnapshot();
        snapshot_index = node.getStatus().applied_index;

        var insert: pb.ExecuteRequest = .{ .request_id = "insert" };
        try insert.statements.append(arena.allocator(), .{ .sql = "INSERT INTO items VALUES (1)" });
        allocator.free(try propose(allocator, node, insert));
        final_index = node.getStatus().applied_index;
        try std.testing.expect(final_index > snapshot_index);
        try std.testing.expectEqual(@as(i64, 1), try countRows(allocator, &machine));
    }

    {
        var machine = try state_machine.SqliteStateMachine.init(allocator);
        defer machine.deinit();
        const node = try raft.Raftor.create(allocator, config, machine.stateMachine());
        defer node.destroy();
        try std.testing.expectEqual(snapshot_index, node.getStatus().applied_index);
        try std.testing.expectEqual(@as(i64, 0), try countRows(allocator, &machine));
        for (0..64) |_| {
            if (try countRows(allocator, &machine) == 1) break;
            _ = try node.tick();
        }
        try std.testing.expectEqual(@as(i64, 1), try countRows(allocator, &machine));
        try std.testing.expectEqual(final_index, node.getStatus().applied_index);
    }
}

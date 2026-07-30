const std = @import("std");
const database = @import("raft_sqlite");

pub fn main(init: std.process.Init) !void {
    _ = database;
    try init.io.writeFile(.stdout(), "raft-sqlite: runtime not configured\n");
}

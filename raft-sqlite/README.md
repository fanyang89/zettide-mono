# raft-sqlite

A bounded, Raft-replicated SQLite database for Zig.

The project is under active development. SQLite runs in memory while raft-zig's
WAL and snapshots provide durable recovery.

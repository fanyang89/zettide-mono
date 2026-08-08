# Zettide Monorepo Developer Guide

## Zig Development Builds

During active development, agents must build the relevant Zig component with
its persistent incremental watch task instead of repeatedly invoking one-shot
`zig build` or `mise run build:*` commands:

```bash
mise run dev:etz
mise run dev:grpc-lite
mise run dev:raft-zig
mise run dev:zettide
mise run dev:zettide-cawfs
mise run dev:zettide-control
```

Run the task from the workspace root and keep it running while editing that
component. Stop it when the development session is complete.

Incremental compilation is experimental and must not be used as the final
correctness gate. Before committing, run the component's regular `test:*` task
or the root `mise run check` task without incremental compilation. Do not add
`-fincremental` or `--watch` to CI or release builds.

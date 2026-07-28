# Zettide

**A Fedora-first hyperconverged platform built for high performance by default.**

Zettide brings compute, storage, networking, and cluster coordination into one
cohesive system. The goal is a platform that can turn a Fedora host into a
useful private cloud without requiring operators to assemble and tune an
unrelated collection of infrastructure projects first.

Zettide is under active development. Its components are usable independently,
but the unified installation and cluster lifecycle are not production-ready.

## Principles

- **Fedora first.** Integrate deeply with KVM, QEMU, libvirt, systemd, and the
  modern Linux I/O stack instead of targeting the lowest common denominator.
- **One platform.** Treat compute, storage, networking, and control-plane
  behavior as one product with one lifecycle.
- **Performance by default.** Ship production builds and runtime defaults that
  favor efficient I/O, bounded resource use, and predictable latency.
- **Ready out of the box.** Minimize required choices while keeping advanced
  controls available when the defaults no longer fit.
- **Small trusted core.** Prefer focused, auditable components with explicit
  ownership and failure behavior.

## Components

| Component | Role | Implementation |
| --- | --- | --- |
| [`qtr`](qtr/) | VM lifecycle, host setup, storage attachment, and web control plane | Rust, React, libvirt/QEMU |
| [`zettide`](zettide/) | Portable volume format and Linux FUSE filesystem | Zig, littlefs, FUSE 3 |
| [`etz`](etz/) | Authenticated private networking across untrusted connectivity | Zig, TUN, EasyTier |
| [`raft-zig`](raft-zig/) | Consensus, membership, WAL, and replicated-state orchestration | Zig |
| [`grpc-lite`](grpc-lite/) | Shared Zig runtime services and lightweight asynchronous RPC | Zig, nghttp2, libxev |

This repository is the integration workspace. Each component remains an
independent Git submodule with its own release history and detailed
documentation.

[`spdk`](spdk/) is a pinned third-party source dependency for Zettide's Linux
storage data plane. It is built by this workspace but is not an independently
released Zettide component.

`grpc-lite` is the foundational dependency for Zettide's Zig components.
Reusable runtime facilities belong there rather than being reimplemented in
individual services; protocol- and product-specific behavior stays with its
own component.

## Development Setup

The supported development host is Fedora. Install the common native
dependencies first:

```sh
sudo dnf install \
  fuse3-devel \
  gcc \
  gcc-c++ \
  git \
  libvirt-devel \
  pkgconf-pkg-config
```

Install [mise](https://mise.jdx.dev/), then initialize the workspace:

```sh
git clone --recurse-submodules <repository-url> Zettide
cd Zettide
sudo PATH=/usr/bin:$PATH spdk/scripts/pkgdep.sh
mise trust
mise install
mise run bootstrap
```

`mise` pins Zig, Rust, Node.js, pnpm, CMake, Ninja, and Task. The bootstrap task
initializes nested source dependencies and installs the qtr web dependencies.
The SPDK dependency installer is an explicit host setup step because it uses the
Fedora package manager and requires root privileges. The SPDK build itself
prefers `/usr/bin/python3` so its RPM-provided `tabulate` and `pyelftools`
modules are available even when a user-local Python precedes it in `PATH`.
See [`qtr/README.md`](qtr/README.md) for the complete Fedora virtualization
runtime setup.

## Build And Test

Build every component with production-oriented optimization:

```sh
mise run build
```

The root build compiles a minimal shared SPDK library set before Zettide and
runs Zettide's SPDK header and link probe. It does not allocate hugepages, start
the SPDK application framework, or bind storage devices. Build SPDK alone with
`mise run build:spdk`.

Run all default test suites:

```sh
mise run test
```

Run formatting checks, tests, and build gates:

```sh
mise run check
```

The aggregate tasks run independent components concurrently and prefix their
output. Every task is also available per component:

```sh
mise run build:qtr
mise run test:zettide
mise run test:etz
mise run check
mise tasks
```

Update every submodule to the latest revision of its tracked branch and commit
the resulting submodule pointers:

```sh
mise run update
```

The update task creates a `chore: update submodules` commit only when at least
one submodule revision changes. It does not stage unrelated workspace files.

Privileged filesystem, network, and virtualization integration suites are not
part of the default root test task. Their host setup and commands are documented
inside the corresponding component.

## Direction

The integration path is intentionally incremental:

1. Deliver reliable standalone compute, storage, and networking components.
2. Establish a replicated control plane and durable cluster membership.
3. Unify host bootstrap, upgrades, observability, and failure recovery.
4. Ship a Fedora-native installation with tested high-performance defaults.

Until the final stage is complete, treat this repository as an engineering
workspace rather than a finished Fedora distribution or appliance.

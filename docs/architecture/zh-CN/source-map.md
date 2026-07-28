# 源码映射

本页将架构描述映射到当前仓库入口。目标能力尚无实现时明确标记，不用目标文档替代源码事实。

## 工作区

| 主题 | 文件 |
| --- | --- |
| 组件定位和整体成熟度 | [`../../../README.md`](../../../README.md) |
| 控制面当前范围 | [`../../../zettide-control/README.md`](../../../zettide-control/README.md) |
| 数据面当前能力 | [`../../../zettide/README.md`](../../../zettide/README.md) |
| Raft 概览和安全边界 | [`../../../raft-zig/README.md`](../../../raft-zig/README.md)（其中 scaffold/planned 状态说明已落后于当前源码） |
| RPC 功能和限制 | [`../../../grpc-lite/README.md`](../../../grpc-lite/README.md) |

## zettide-control

| 主题 | 文件 |
| --- | --- |
| Pool RPC、command 和 snapshot protobuf | [`../../../zettide-control/proto/zettide/control/v1/control.proto`](../../../zettide-control/proto/zettide/control/v1/control.proto) |
| Pool apply、幂等、snapshot/restore | [`../../../zettide-control/src/state_machine.zig`](../../../zettide-control/src/state_machine.zig) |
| 模块入口 | [`../../../zettide-control/src/root.zig`](../../../zettide-control/src/root.zig) |
| 构建与 protobuf codegen | [`../../../zettide-control/build.zig`](../../../zettide-control/build.zig) |

当前没有 daemon、grpc-lite handler、Node/Volume/Replica 协议或 reconciliation 实现。

## raft-zig

| 主题 | 文件 |
| --- | --- |
| 公共 API | [`../../../raft-zig/src/root.zig`](../../../raft-zig/src/root.zig) |
| Raft 状态机 | [`../../../raft-zig/src/raft.zig`](../../../raft-zig/src/raft.zig) |
| RawNode/Ready | [`../../../raft-zig/src/raw_node.zig`](../../../raft-zig/src/raw_node.zig) |
| Raftor、proposal、ReadIndex、恢复 | [`../../../raft-zig/src/raftor.zig`](../../../raft-zig/src/raftor.zig) |
| Raftor queue/snapshot 配置 | [`../../../raft-zig/src/raftor_config.zig`](../../../raft-zig/src/raftor_config.zig) |
| StateMachine 契约 | [`../../../raft-zig/src/state_machine.zig`](../../../raft-zig/src/state_machine.zig) |
| Durable membership | [`../../../raft-zig/src/cluster_membership.zig`](../../../raft-zig/src/cluster_membership.zig) |
| Segmented WAL | [`../../../raft-zig/src/wal.zig`](../../../raft-zig/src/wal.zig) |
| Transport 抽象 | [`../../../raft-zig/src/transport.zig`](../../../raft-zig/src/transport.zig) |
| grpc-lite transport | [`../../../raft-zig/src/rpc/grpc_lite_transport.zig`](../../../raft-zig/src/rpc/grpc_lite_transport.zig) |
| 多节点测试 | [`../../../raft-zig/tests/multi_node_test.zig`](../../../raft-zig/tests/multi_node_test.zig) |
| grpc transport 测试 | [`../../../raft-zig/tests/grpc_raftor_test.zig`](../../../raft-zig/tests/grpc_raftor_test.zig) |

## grpc-lite

| 主题 | 文件 |
| --- | --- |
| 公共 API | [`../../../grpc-lite/src/root.zig`](../../../grpc-lite/src/root.zig) |
| Channel、连接和 client TLS | [`../../../grpc-lite/src/channel.zig`](../../../grpc-lite/src/channel.zig) |
| Server、reactor 和 server TLS | [`../../../grpc-lite/src/server.zig`](../../../grpc-lite/src/server.zig) |
| Streaming 和背压 | [`../../../grpc-lite/src/stream.zig`](../../../grpc-lite/src/stream.zig) |
| Metadata | [`../../../grpc-lite/src/metadata.zig`](../../../grpc-lite/src/metadata.zig) |
| Deadline | [`../../../grpc-lite/src/deadline.zig`](../../../grpc-lite/src/deadline.zig) |
| 官方互操作范围 | [`../../../grpc-lite/tests/official/README.md`](../../../grpc-lite/tests/official/README.md) |

## zettide 本地存储

| 主题 | 文件 |
| --- | --- |
| v3 格式规范 | [`../../../zettide/docs/v3-format.md`](../../../zettide/docs/v3-format.md) |
| Member 头部格式 | [`../../../zettide/src/v3/member_format.zig`](../../../zettide/src/v3/member_format.zig) |
| Dynamic topology | [`../../../zettide/src/v3/pool_topology.zig`](../../../zettide/src/v3/pool_topology.zig) |
| Layout 与 policy | [`../../../zettide/src/v3/pool_layout.zig`](../../../zettide/src/v3/pool_layout.zig), [`pool_policy.zig`](../../../zettide/src/v3/pool_policy.zig) |
| Pool provision | [`../../../zettide/src/v3/pool_provision.zig`](../../../zettide/src/v3/pool_provision.zig) |
| Member scan 与 authority | [`../../../zettide/src/v3/pool_member_set.zig`](../../../zettide/src/v3/pool_member_set.zig), [`pool_authority.zig`](../../../zettide/src/v3/pool_authority.zig) |
| Membership transition | [`../../../zettide/src/v3/membership.zig`](../../../zettide/src/v3/membership.zig) |
| Control coordinator | [`../../../zettide/src/v3/pool_replicated_journal.zig`](../../../zettide/src/v3/pool_replicated_journal.zig) |
| Control record | [`../../../zettide/src/v3/control_record.zig`](../../../zettide/src/v3/control_record.zig) |
| Replica 本地 I/O 接口 | [`../../../zettide/src/v3/replica_endpoint.zig`](../../../zettide/src/v3/replica_endpoint.zig) |
| 本地 replicated block device | [`../../../zettide/src/v3/pool_block_device.zig`](../../../zettide/src/v3/pool_block_device.zig) |
| Linux 设备安全检查 | [`../../../zettide/src/v3/linux_block_device.zig`](../../../zettide/src/v3/linux_block_device.zig), [`linux_pool_plan.zig`](../../../zettide/src/v3/linux_pool_plan.zig) |

`ReplicaEndpoint` 是本地 vtable，不是跨节点 transport。v3 control journal 不是 Volume 数据 replication journal。

## SPDK/NVMf

| 主题 | 文件 |
| --- | --- |
| Zettide link probe | [`../../../zettide/test/spdk_link.c`](../../../zettide/test/spdk_link.c) |
| Probe 构建脚本 | [`../../../zettide/test/spdk-link.sh`](../../../zettide/test/spdk-link.sh) |
| SPDK NVMf API | [`../../../third_party/spdk/include/spdk/nvmf.h`](../../../third_party/spdk/include/spdk/nvmf.h) |
| SPDK bdev API | [`../../../third_party/spdk/include/spdk/bdev.h`](../../../third_party/spdk/include/spdk/bdev.h) |
| NVMf target 入口 | [`../../../third_party/spdk/app/nvmf_tgt/nvmf_main.c`](../../../third_party/spdk/app/nvmf_tgt/nvmf_main.c) |
| NVMf subsystem | [`../../../third_party/spdk/lib/nvmf/subsystem.c`](../../../third_party/spdk/lib/nvmf/subsystem.c) |
| TCP/RDMA transports | [`../../../third_party/spdk/lib/nvmf/tcp.c`](../../../third_party/spdk/lib/nvmf/tcp.c), [`rdma.c`](../../../third_party/spdk/lib/nvmf/rdma.c) |

当前 probe 只初始化 app options 和 TCP/RDMA transport options；不启动 SPDK app，不创建 bdev、subsystem、namespace、listener 或 controller。

## 尚无实现的目标能力

- Node registration、heartbeat 和 DataService。
- Volume/Replica 控制面元数据。
- ReplicaAllocation、extent allocator 和 durable local catalog。
- Placement、lease 和 Volume write epoch。
- Vendor-specific NVMf Replica protocol、两阶段 replication journal 与 2/3 commit certificate。
- Epoch-bound NVMf access gate。
- 自动 failover、resync、scrub 和 repair。
- mTLS 节点认证和面向不可信网络的授权。

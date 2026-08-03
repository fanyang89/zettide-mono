# 源码映射

本页将架构描述映射到当前仓库入口。目标能力尚无实现时明确标记，不用目标文档替代源码事实。

## 工作区

| 主题 | 文件 |
| --- | --- |
| 组件定位和整体成熟度 | [`../../../README.md`](../../../README.md) |
| 控制面当前范围 | [`../../../zettide-control/README.md`](../../../zettide-control/README.md) |
| 数据面当前能力 | [`../../../zettide/README.md`](../../../zettide/README.md) |
| qtr VM 与外部存储当前能力 | [`../../../qtr/README.md`](../../../qtr/README.md), [`../../../qtr/docs/external-storage.md`](../../../qtr/docs/external-storage.md), [`../../../qtr/docs/vm-configuration.md`](../../../qtr/docs/vm-configuration.md) |
| CAWFS shared qcow2 契约 | [`12-cawfs-shared-qcow2.md`](12-cawfs-shared-qcow2.md), [`../../../zettide-cawfs/README.md`](../../../zettide-cawfs/README.md) |
| Raft 概览和安全边界 | [`../../../raft-zig/README.md`](../../../raft-zig/README.md)（其中 scaffold/planned 状态说明已落后于当前源码） |
| RPC 功能和限制 | [`../../../grpc-lite/README.md`](../../../grpc-lite/README.md) |

## zettide-control

| 主题 | 文件 |
| --- | --- |
| Pool/Volume/Node/Member/Heartbeat protobuf | [`../../../zettide-control/proto/zettide/control/v1/control.proto`](../../../zettide-control/proto/zettide/control/v1/control.proto) |
| Pool/Volume/Node/Member apply、幂等、snapshot/restore 与 heartbeat binding | [`../../../zettide-control/src/state_machine.zig`](../../../zettide-control/src/state_machine.zig) |
| leader-local heartbeat store | [`../../../zettide-control/src/heartbeat.zig`](../../../zettide-control/src/heartbeat.zig) |
| Pool/Volume/Node/Member/Heartbeat grpc-lite handler 与 ReadIndex | [`../../../zettide-control/src/service.zig`](../../../zettide-control/src/service.zig) |
| daemon 命令行配置 | [`../../../zettide-control/src/config.zig`](../../../zettide-control/src/config.zig) |
| WAL、Raft transport 与服务生命周期装配 | [`../../../zettide-control/src/runtime.zig`](../../../zettide-control/src/runtime.zig) |
| 进程和信号入口 | [`../../../zettide-control/src/main.zig`](../../../zettide-control/src/main.zig) |
| restart、snapshot 与三 voter failover 测试 | [`../../../zettide-control/src/runtime_integration_test.zig`](../../../zettide-control/src/runtime_integration_test.zig) |
| 模块入口 | [`../../../zettide-control/src/root.zig`](../../../zettide-control/src/root.zig) |
| 构建与 protobuf codegen | [`../../../zettide-control/build.zig`](../../../zettide-control/build.zig) |

当前已有 durable Volume metadata intent、Node/Member registration 和 leader-local heartbeat 首个切片；尚无 placement、Replica/Allocation/Attachment mutation 或 reconciliation 实现。

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
| Multi-Volume catalog format | [`../../../zettide/docs/v3-multivolume-format.md`](../../../zettide/docs/v3-multivolume-format.md) |
| Catalog Volume 与 extent mapping | [`../../../zettide/src/v3/pool_catalog_volume.zig`](../../../zettide/src/v3/pool_catalog_volume.zig), [`pool_catalog_mutation.zig`](../../../zettide/src/v3/pool_catalog_mutation.zig) |
| Catalog endpoint registry | [`../../../zettide/src/endpoint_registry.zig`](../../../zettide/src/endpoint_registry.zig) |

`ReplicaEndpoint` 是本地 vtable，不是跨节点 transport。v3 control journal 不是 Volume 数据 replication journal。

## SPDK block frontend 与 NVMf

| 主题 | 文件 |
| --- | --- |
| Managed SPDK runtime | [`../../../zettide/src/spdk/runtime.zig`](../../../zettide/src/spdk/runtime.zig), [`../../../zettide/src/spdk/runtime.c`](../../../zettide/src/spdk/runtime.c) |
| SPDK bdev storage backend | [`../../../zettide/src/spdk/storage.zig`](../../../zettide/src/spdk/storage.zig) |
| NVMe-oF initiator controller | [`../../../zettide/src/spdk/nvme_controller.zig`](../../../zettide/src/spdk/nvme_controller.zig) |
| Async bdev provider 与 catalog backend | [`../../../zettide/src/spdk/catalog_volume_backend.zig`](../../../zettide/src/spdk/catalog_volume_backend.zig), [`../../../zettide/src/spdk/bdev_provider.c`](../../../zettide/src/spdk/bdev_provider.c) |
| vhost-user-blk catalog export | [`../../../zettide/src/spdk/catalog_vhost_export.zig`](../../../zettide/src/spdk/catalog_vhost_export.zig), [`../../../zettide/src/spdk/vhost_block_export.zig`](../../../zettide/src/spdk/vhost_block_export.zig) |
| SPDK focused test steps | [`../../../zettide/build.zig`](../../../zettide/build.zig), [`../../../zettide/test/`](../../../zettide/test/) |
| SPDK NVMf API | [`../../../third_party/spdk/include/spdk/nvmf.h`](../../../third_party/spdk/include/spdk/nvmf.h) |
| SPDK iSCSI target reference | [`../../../third_party/spdk/app/iscsi_tgt/iscsi_tgt.c`](../../../third_party/spdk/app/iscsi_tgt/iscsi_tgt.c), [`../../../third_party/spdk/lib/iscsi/`](../../../third_party/spdk/lib/iscsi/) |
| SPDK bdev API | [`../../../third_party/spdk/include/spdk/bdev.h`](../../../third_party/spdk/include/spdk/bdev.h) |
| NVMf target 入口 | [`../../../third_party/spdk/app/nvmf_tgt/nvmf_main.c`](../../../third_party/spdk/app/nvmf_tgt/nvmf_main.c) |
| NVMf subsystem | [`../../../third_party/spdk/lib/nvmf/subsystem.c`](../../../third_party/spdk/lib/nvmf/subsystem.c) |
| TCP/RDMA transports | [`../../../third_party/spdk/lib/nvmf/tcp.c`](../../../third_party/spdk/lib/nvmf/tcp.c), [`rdma.c`](../../../third_party/spdk/lib/nvmf/rdma.c) |

当前 Zettide 已能启动受管 SPDK runtime、访问 bdev、连接 NVMe-oF controller、提供异步 bdev 并创建 vhost-user-blk controller。尚未封装 iSCSI target，也未创建受管 NVMf target subsystem、namespace 或 listener；这些库级路径尚未装配为产品 daemon。

## qtr Storage

| 主题 | 文件 |
| --- | --- |
| iSCSI backend、scan、login/logout 与设备发现 | [`../../../qtr/src/storage.rs`](../../../qtr/src/storage.rs) |
| Storage CLI schema | [`../../../qtr/src/config.rs`](../../../qtr/src/config.rs) |
| VM file/block disk 与 libvirt reconciliation | [`../../../qtr/src/vm.rs`](../../../qtr/src/vm.rs) |

当前 qtr storage driver 与 VM disk path 相互独立；没有 Zettide Volume identity、managed publication 或持久 attachment reconciliation。

## zettide-cawfs

| 主题 | 文件 |
| --- | --- |
| transaction 与 Store 契约 | [`../../../zettide-cawfs/src/transaction.zig`](../../../zettide-cawfs/src/transaction.zig), [`../../../zettide-cawfs/src/store.zig`](../../../zettide-cawfs/src/store.zig) |
| SCSI CAW 与 whole-LUN Linux transport | [`../../../zettide-cawfs/src/scsi.zig`](../../../zettide-cawfs/src/scsi.zig), [`../../../zettide-cawfs/src/linux_sg_io.zig`](../../../zettide-cawfs/src/linux_sg_io.zig) |
| mutable data transport | [`../../../zettide-cawfs/src/data_block.zig`](../../../zettide-cawfs/src/data_block.zig) |
| persistent extent allocator | [`../../../zettide-cawfs/src/extent_allocator.zig`](../../../zettide-cawfs/src/extent_allocator.zig) |

当前尚无 SCSI-backed immutable Store、inode/directory/file extent map、CAWFS
`FilesystemBackend` adapter 或 qtr shared-image source。

## 尚无实现的目标能力

- DataService 产品 daemon、Node registration 客户端和扩展 heartbeat report。
- Pool default/per-Volume protection、在线加盘和保护迁移产品生命周期。
- Zettide managed iSCSI target 与 publication API。
- qtr Zettide backend、managed attachment 和 republish。
- Tier 3 Raft publication authority、access generation 和 DataService installed-generation fencing。
- ReplicaPlacement/ReplicaAllocation mutation、extent allocator 和 durable per-node ReplicaAllocation catalog；本地 Pool multi-Volume catalog 已有独立库级实现。
- VolumeAttachment mutation 和实际 publish/unpublish 路径。
- Placement、lease 和 Volume write epoch。
- Vendor-specific NVMf Replica protocol、两阶段 replication journal 与 2/3 commit certificate。
- Epoch-bound NVMf access gate。
- 自动 failover、resync、scrub 和 repair。
- mTLS 节点认证和面向不可信网络的授权。

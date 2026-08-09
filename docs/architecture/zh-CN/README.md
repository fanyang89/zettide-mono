# Zettide 存储架构

本文档描述 Zettide 从本地文件系统、单节点 VM 存储服务到分布式高可用存储的当前实现、目标架构、关键不变量和演进路径。

> Zettide 仍处于主动开发阶段。各章使用“当前实现”“目标设计”和“实现差距”区分已经存在的能力与尚未交付的能力。目标设计不能被解释为生产可用性承诺。

## 范围

本书覆盖存储系统及其与 qtr 的直接集成边界：

- `zettide-control`：元数据和集群控制面
- `zettide`：本地存储格式、文件系统和目标数据面
- `raftz`：控制面共识、WAL、快照和成员关系
- `grpc-lite`：控制 RPC 和 Raft transport
- SPDK 与 iSCSI：目标单节点 VM-facing block export
- SPDK 与 NVMe over Fabrics（NVMf）：目标跨节点 Replica 数据路径
- `qtr`：Volume publish、iSCSI session、libvirt attachment、CAWFS shared qcow2 和 republish 边界

除存储 attachment 外的计算调度、虚拟机生命周期、覆盖网络、Web 界面、计费和完整发行版生命周期不在本书范围内。Tier 3 支持把 Volume republish 到调用方指定的 qtr host，但不负责选择该 host 或自动重启 VM。

## 三层目标

| 层级 | 交付能力 | 故障边界 |
| --- | --- | --- |
| Tier 1 | 从文件或裸设备在本机挂载 FUSE 文件系统 | 单进程、单机和底层介质 |
| Tier 2 | 一个 Zettide 节点通过 iSCSI 向 qtr 提供受管 Volume | 可通过本地副本抵抗设备故障；不抵抗存储主机故障 |
| Tier 3 | 多节点同步复制、storage failover、repair 和 qtr republish | 默认 3/2 current protection 可抵抗单 storage node/Replica 故障；override 按实际保护级别承诺 |

三个 Tier 是累积能力，不是互斥产品。后一级复用前一级的格式、Volume 身份和本地数据路径，并增加新的服务边界与故障保证。

## 目录

1. [范围与状态](00-scope-and-status.md)
2. [目标与原则](01-goals-and-principles.md)
3. [系统架构](02-system-architecture.md)
4. [领域模型](03-domain-model.md)
5. [控制面](04-control-plane.md)
6. [数据面](05-data-plane.md)
7. [I/O 与控制流程](06-io-and-control-flows.md)
8. [一致性与 Fencing](07-consistency-and-fencing.md)
9. [故障与恢复](08-failure-and-recovery.md)
10. [部署与网络](09-deployment-and-networking.md)
11. [安全边界](10-security.md)
12. [演进路线图](11-evolution-roadmap.md)
13. [CAWFS 共享 qcow2 接入](12-cawfs-shared-qcow2.md)
14. [术语表](glossary.md)
15. [源码映射](source-map.md)

## 状态标记

| 标记 | 含义 |
| --- | --- |
| 当前 | 已存在实现，并有测试或可执行构建路径 |
| 部分 | 类型或局部机制已实现，但端到端能力尚未形成 |
| 目标 | 已选择的架构方向，尚未完成实现 |
| 非目标 | 当前阶段明确不处理 |

## 文档约定

- `Raft leader` 与 Volume `primary` 是不同角色。
- `Raft term`、本地 v3 Pool membership epoch 和 Volume write epoch 是不同版本域。
- 控制面 Pool 与 `zettide` v3 本地 Pool 是不同层次的对象。
- Pool Member topology 表示容量和故障边界；Volume protection policy 表示副本目标，二者不能互相推导。
- iSCSI 是 qtr/VM-facing 出口；NVMf 是 Tier 3 内部 Replica transport，二者作用域不同。
- qtr 持久化稳定 Volume/attachment 身份；portal、IQN/LUN session 和 `/dev/...` 路径是可重建运行时状态。
- shared qcow2 持久化 CAWFS volume/image 身份；mount point 和 image path 是 host-local observation。
- “持久确认”指满足底层 flush/FUA 语义，不是进入内存、发送队列或设备易失缓存。
- 当前安全模型是可信隔离网络，不是零信任网络。
- 文档与实现冲突时，以源码、协议和测试为准；入口见[源码映射](source-map.md)。

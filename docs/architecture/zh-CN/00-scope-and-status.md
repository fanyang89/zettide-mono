# 范围与状态

> 状态：当前实现与目标设计

## 系统边界

Zettide 按三个累积层级交付存储能力：

- Tier 1 由 `zettide` 直接从容器文件或本地 raw Pool 提供 FUSE 文件系统。
- Tier 2 在一个存储节点上管理 Pool、catalog Volume 和 block export，并通过 iSCSI 接入 qtr。
- Tier 3 将权威元数据和 Volume Replica 扩展到多个存储节点，提供 storage failover、repair 和 qtr republish。

另有一条不替代 Tier 2/3 block publication 的 shared-file profile：多个 qtr host
把 qcow2 保存在共同挂载的 CAWFS namespace，每个 image 保持全局 single-writer，
跨 host 接管必须完成外部硬 fencing。具体契约见
[CAWFS 共享 qcow2 接入](12-cawfs-shared-qcow2.md)。

Tier 3 将复制元数据控制面与高性能存储数据面组合为分布式存储系统：

- `zettide-control` 保存 Pool、Volume、Node、Replica、placement 和写入权威。
- `zettide` 在每个存储节点管理本地介质、Volume 副本和前端访问。
- `raft-zig` 复制权威元数据。
- `grpc-lite` 承载除数据块之外的控制通信。
- SPDK/NVMf 承载节点之间的副本读写和重同步数据。
- SPDK/iSCSI 承载 Zettide 与 qtr host 之间的 VM block I/O。
- qtr 管理 publish、host session、libvirt attachment 和目标 host 上的 republish。

当前仓库中的控制面与数据面尚未端到端贯通，不能描述为完整分布式存储集群。

## Tier 交付状态

| Tier | 当前状态 | 完成标准 |
| --- | --- | --- |
| Tier 1 | 部分 | file-backed 与 raw-device FUSE mount 当前可用；完整 Tier 还需满足声明的 POSIX profile 和全部准入测试 |
| Tier 2 | 部分 | 常驻服务管理动态 Pool 与 catalog Volume；SPDK iSCSI export 和 qtr managed backend 完成 create/publish/attach/restart/detach E2E |
| Tier 3 | 目标 | 跨节点 2/3 持久提交、lease/epoch fencing、自动 storage failover/repair，以及指定 qtr host 的 republish E2E |

## 当前状态矩阵

| 能力 | 状态 | 当前事实 | 目标 |
| --- | --- | --- | --- |
| Pool protobuf API | 当前 | 已定义并运行 `CreatePool`、`GetPool`、`ListPools` | 增加认证和运维接口 |
| Pool 内存状态机 | 当前 | 支持确定性 apply、名称索引、请求幂等、快照与恢复 | 扩展完整控制面元数据 |
| 控制面 Raft | 当前 | 已装配 Raftor、持久 WAL、ReadIndex、快照和 grpc-lite transport，并验证多节点恢复 | 增加动态成员与生产运维能力 |
| Volume 元数据 | 部分 | durable Create/Get/Delete、固定 3/2/1 策略、幂等恢复和 tombstone 已实现；创建只提交 `PROVISIONING` intent | 接入 placement、数据面收敛和写入权威 |
| Node 注册与心跳 | 部分 | durable Register/Get/List 已实现并经过 Raft 复制；leader-local Report/Get heartbeat 已实现 Node incarnation/sequence、Member presence 和可选 extent capacity | 增加能力更新、隔离、注销、路径和 Replica 观测 |
| Member 注册 | 当前 | durable Register/Get/List 已实现；显式绑定控制面 Pool、Node 与本地 set | 增加生命周期和 observed report |
| Placement 与 reconciliation | 目标 | 尚未实现 | 按故障域放置、修复和迁移副本 |
| 本地容器和文件系统 | 当前 | littlefs、对象层、FUSE 和恢复路径已实现 | 作为本地前端和持久化基础 |
| 本地 raw Pool | 当前 | 支持单盘和三个本地成员复制 | 接入跨节点资源模型 |
| 本地复制写入 | 当前 | 三个 endpoint 全部写入，任一失败冻结 writer | 演进为三副本、2/3 持久确认 |
| 动态本地成员控制 | 部分 | topology、membership 和 control journal 库级能力已实现 | 接入控制面编排与产品生命周期 |
| 本地 multi-Volume catalog | 部分 | catalog codec/graph/store、extent mapping、writable Volume backend 和 endpoint registry 已有库级路径 | 接入产品 CLI、扩容和保护迁移 reconciliation |
| SPDK runtime 与 bdev | 部分 | managed runtime、bdev dispatcher、异步 provider 和 catalog Volume backend 已有 focused tests | 装配常驻服务与设备生命周期 |
| vhost-user-blk export | 部分 | catalog Volume 到 vhost block controller 的库级生命周期已实现 | 保留为可选 VM frontend，不作为 Tier 2 首发协议 |
| iSCSI export | 目标 | vendored SPDK 具备 iSCSI target，但 Zettide 尚未封装或发布 Volume | 作为 Tier 2 首个 qtr managed protocol |
| qtr iSCSI host 连接 | 部分 | 可手动注册、扫描、login/logout 并发现 Linux block device | 增加 Zettide backend 和 attachment reconciliation |
| CAWFS shared qcow2 | 部分 | transaction、SCSI CAW/data transport、voting 和 persistent extent allocator 已存在；尚无 POSIX/FUSE 或 qtr 接线 | 多 host shared mount、per-image single-writer 和 fenced takeover |
| NVMf initiator | 部分 | managed NVMe-oF TCP/RDMA controller wrapper 可连接并枚举 namespace | 接入受管 Replica session |
| NVMf target | 目标 | 尚无受管 Replica subsystem、namespace 或 listener | 导出内部 Volume Replica namespace |
| Primary、lease、epoch | 目标 | 尚无协议与数据面 enforcement | 单主同步复制和旧 primary fencing |
| 生产级节点认证 | 目标 | grpc-lite 不支持 mTLS | 后续增加双向认证或等价安全边界 |

## 两种 Pool

仓库目前存在两个不同层次的 Pool：

- **控制面 Pool**：跨节点资源、策略和 Volume 的逻辑边界。
- **本地 v3 Pool**：由一个或多个 Member 构成的本地持久化集合，保存 topology、layout 和 control journal。

目标架构允许一个控制面 Pool 聚合多个节点的本地资源。二者必须通过稳定 ID 和显式注册关系绑定，不能依赖名称或设备路径隐式关联。

## 当前实现边界

### zettide-control

当前具备：

- Pool protobuf 模型和 unary service descriptor。
- `PoolStateMachine` 的确定性命令 apply。
- request ID 幂等与语义指纹冲突检测。
- Pool ID/name 索引、容量上限和输入校验。
- durable Node 注册、ID 索引、cluster binding、容量上限和输入校验。
- durable Member 注册、本地 set/slot 唯一性、Pool/Node 绑定和不可变 allocation geometry。
- durable Volume metadata intent、固定 3/2/1 保护参数、条件删除和永久有界 tombstone。
- ReplicaPlacement、ReplicaAllocation 和 VolumeAttachment 的 durable schema、索引与恢复不变量；当前没有创建这些 child resource 的命令。
- Pool/Node/Member/Volume 共享 request ID 幂等域和跨类型冲突检测。
- v5 状态快照、v2/v3/v4 兼容读取、原子恢复和损坏快照拒绝。
- Create/Get/List Pool grpc-lite handler；写成功来自 committed apply，读取经过 ReadIndex。
- Register/Get/List Node grpc-lite handler；写成功来自 committed apply，读取经过 ReadIndex。
- Register/Get/List Member grpc-lite handler；写成功来自 committed apply，读取经过 ReadIndex。
- Create/Get/Delete Volume grpc-lite handler；创建返回 `PROVISIONING` metadata intent，不执行 placement 或数据面 I/O。
- Report/Get Heartbeat grpc-lite handler；durable binding 校验和易失 observation 访问在 ReadIndex callback 中串行执行。
- leader-local heartbeat store；限制 10,000 Nodes、10,000 Member observations 和每次 256 Members，推荐 1 秒上报，5 秒后 stale。
- Heartbeat 不进入 WAL/snapshot；leader 切换、任期变化或 snapshot restore 后清空并要求重新上报。
- 使用命令行配置的可运行 daemon、持久 WAL 和 grpc-lite Raft transport。
- Pool/Node/Member/Volume 单节点 snapshot/WAL 恢复与三 voter leader failover、restart 集成测试，包括 Volume tombstone、幂等重放、heartbeat 清空和重新上报。

当前不具备：

- Replica/Allocation/Attachment mutation、placement、extent allocator、lease 和 reconciliation。
- Member lifecycle、当前 topology/authority、路径、Replica 和健康观测。
- Node 能力更新、隔离和注销。
- 动态成员管理、认证授权、mTLS、健康检查和生产运维接口。

### zettide

当前具备：

- 稀疏容器、littlefs、对象层和 Linux FUSE。
- 本地 raw block Pool 的安全创建、检查、打开和挂载。
- Member v3 双头部、控制日志、authority 扫描和故障冻结。
- 单成员无保护和三个本地成员复制。
- multi-Volume catalog、extent mapping、catalog data lease 和 writable backend 的库级实现。
- managed SPDK runtime、bdev dispatcher、NVMe-oF initiator、异步 bdev provider 和 vhost-user-blk export 生命周期。

当前不具备：

- 常驻 DataService 或 Node Agent。
- grpc-lite 控制客户端和节点注册。
- 产品级 SPDK daemon、iSCSI target、NVMf target 和跨节点复制。
- 动态扩容、每 Volume 保护策略迁移和对应产品命令。
- 多数派数据提交、primary 故障切换和后台副本修复。

### qtr

当前具备外部 iSCSI backend 注册、扫描、host login/logout 和设备发现。VM 定义仍引用本地文件或 block path；尚无 Zettide backend、Volume publication、持久 attachment reconciliation 或 storage republish。

## 成熟度判断

一项能力只有满足以下条件才标为“当前”：

1. 存在非测试实现，而不只是类型、枚举或注释。
2. 存在对应测试或可执行验证。
3. 上下游已经接线，才称为端到端能力。
4. 第三方 API 能编译链接，不等于运行时集成。
5. 磁盘格式能表达某项策略，不等于数据路径已经支持该策略。

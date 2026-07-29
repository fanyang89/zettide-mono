# 范围与状态

> 状态：当前实现与目标设计

## 系统边界

Zettide 的目标是将复制元数据控制面与高性能存储数据面组合为一个分布式存储系统：

- `zettide-control` 保存 Pool、Volume、Node、Replica、placement 和写入权威。
- `zettide` 在每个存储节点管理本地介质、Volume 副本和前端访问。
- `raft-zig` 复制权威元数据。
- `grpc-lite` 承载除数据块之外的控制通信。
- SPDK/NVMf 承载节点之间的副本读写和重同步数据。

当前仓库中的控制面与数据面尚未端到端贯通，不能描述为完整分布式存储集群。

## 当前状态矩阵

| 能力 | 状态 | 当前事实 | 目标 |
| --- | --- | --- | --- |
| Pool protobuf API | 当前 | 已定义 `CreatePool`、`GetPool`、`ListPools` | 增加运行服务、认证和运维接口 |
| Pool 内存状态机 | 当前 | 支持确定性 apply、名称索引、请求幂等、快照与恢复 | 纳入完整控制面进程 |
| 控制面 Raft | 部分 | `raft-zig` 已提供 Raftor、WAL、ReadIndex、快照和 grpc-lite transport | 在 `zettide-control` 装配并验证多节点服务 |
| Volume 元数据 | 目标 | 尚无 protobuf 和状态机模型 | 管理容量、状态、副本和写入权威 |
| Node 注册与心跳 | 目标 | 尚无数据节点控制协议 | 注册持久化，心跳由 leader 易失维护 |
| Placement 与 reconciliation | 目标 | 尚未实现 | 按故障域放置、修复和迁移副本 |
| 本地容器和文件系统 | 当前 | littlefs、对象层、FUSE 和恢复路径已实现 | 作为本地前端和持久化基础 |
| 本地 raw Pool | 当前 | 支持单盘和三个本地成员复制 | 接入跨节点资源模型 |
| 本地复制写入 | 当前 | 三个 endpoint 全部写入，任一失败冻结 writer | 演进为三副本、2/3 持久确认 |
| 动态本地成员控制 | 部分 | topology、membership 和 control journal 库级能力已实现 | 接入控制面编排与产品生命周期 |
| SPDK | 部分 | 只验证依赖链接和 TCP/RDMA transport options 初始化 | 启动 SPDK app 并接入实际 bdev |
| NVMf target/initiator | 目标 | 尚无 subsystem、namespace、listener 或跨节点连接 | 导出 Volume Replica namespace |
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
- 状态快照、原子恢复和损坏快照拒绝。
- Create/Get/List Pool grpc-lite handler；写成功来自 committed apply，读取经过 ReadIndex。
- 使用命令行配置的可运行 daemon、持久 WAL 和 grpc-lite Raft transport。
- 单节点 snapshot/WAL 恢复与三 voter leader failover、restart 集成测试。

当前不具备：

- Volume、Node、Replica、heartbeat、placement、lease 和 reconciliation。
- 动态成员管理、认证授权、mTLS、健康检查和生产运维接口。

### zettide

当前具备：

- 稀疏容器、littlefs、对象层和 Linux FUSE。
- 本地 raw block Pool 的安全创建、检查、打开和挂载。
- Member v3 双头部、控制日志、authority 扫描和故障冻结。
- 单成员无保护和三个本地成员复制。

当前不具备：

- 常驻 DataService 或 Node Agent。
- grpc-lite 控制客户端和节点注册。
- SPDK runtime、NVMf target/initiator 和跨节点复制。
- 多数派数据提交、primary 故障切换和后台副本修复。

## 成熟度判断

一项能力只有满足以下条件才标为“当前”：

1. 存在非测试实现，而不只是类型、枚举或注释。
2. 存在对应测试或可执行验证。
3. 上下游已经接线，才称为端到端能力。
4. 第三方 API 能编译链接，不等于运行时集成。
5. 磁盘格式能表达某项策略，不等于数据路径已经支持该策略。

# 演进路线图

> 状态：实施顺序建议，不代表发布日期

## 阶段 0：固定架构语义

- 统一 Pool、Volume、Node、Member、Replica、primary、lease 和 epoch。
- 固定当前/目标状态标记和协议版本规则。
- 保持 grpc-lite、raft-zig、zettide 和 zettide-control 基线测试通过。

完成标准：协议、源码和架构书没有术语冲突；每个版本域有明确作用域。

## 阶段 1：可运行 Pool 控制面

- 将 PoolStateMachine 装配到 Raftor/WAL。
- 实现 grpc-lite Pool handlers 和 daemon 配置。
- 写请求在 apply 后返回；Get/List 走 ReadIndex。
- 验证三 voter、restart、snapshot 和 leader failover。

当前状态：已完成。daemon 使用持久 WAL、静态 voter 配置和 grpc-lite Raft transport；集成测试覆盖 snapshot/WAL 恢复、三 voter restart 和 leader failover。

## 阶段 2：Node 与资源注册

- 定义 durable Node/Member registration 和 leader-local heartbeat。
- 绑定控制面 Pool 与本地 v3 Pool。
- DataService 恢复本地身份并报告 topology、capacity 和 authority。
- 建立 desired/observed reconciliation 框架。

## 阶段 3：SPDK 本地数据路径

- 启动受管 SPDK application framework。
- 接入本地 bdev、hugepage、reactor 和设备所有权。
- 保留当前格式校验、flush 语义和 sticky freeze。
- 在真实测试设备完成读写、重启和故障注入。

## 阶段 4：Volume 与 Replica 生命周期

- 增加 Volume/Replica protobuf、状态机和 placement。
- 将 Replica 放置到不同 Node/Member 故障域。
- 实现 ReplicaAllocation、extent allocator 和 durable local catalog。
- 实现创建、删除、tombstone、generation 和幂等 EnsureReplica。
- 初期只支持三副本，不把 EC 枚举视为实现。

## 阶段 5：内部 NVMf Replica Protocol

- 创建内部 Replica subsystem、namespace、listener 和 initiator connection。
- 定义 vendor-specific `PREPARE`/`COMMIT` commands 和 target-owned metadata。
- 优先验证 NVMf/RDMA；分别验证 InfiniBand、RoCE 或 iWARP provider。
- 在固定 primary、无自动 failover 的实验模式验证 qpair 中断和重连。

## 阶段 6：复制日志与 2/3 提交

- 实现 per-Volume journal、sequence、checksum 和 per-Replica position。
- 将 prepare/data record 持久化到两个 Replica。
- 将 quorum commit certificate 再持久化到两个 Replica 后确认。
- 验证每个两阶段崩溃窗口、响应丢失和 primary crash 后 certified-history 合并。

## 阶段 7：Lease、Epoch 与 Fencing

- 实现 lease grant/renew/revoke 和时钟安全预算。
- Replica 持久化最高 write epoch。
- 固定 quiesce、disconnect、drain、flush、persist epoch、reopen 的 barrier。
- 完成 pause old primary、promote new primary、resume old primary 测试。

在此阶段完成前，不提供自动 primary failover 承诺。

## 阶段 8：自动恢复与修复

- 合并幸存 Replica 的 certified histories，重建连续 committed prefix。
- 实现增量/全量 rebuild、scrub、限速和进度上报。
- 接入 Member joining/draining 和 Replica relocation。
- 区分恢复服务与恢复完整冗余。

## 阶段 9：安全与生产准入

- 增加 mTLS 或等价双向认证与授权。
- 完成证书生命周期、NVMf access control 和密钥隔离。
- 建立滚动升级、回滚、格式兼容和灾难恢复流程。
- 通过断电、网络分区、介质损坏、长稳和资源耗尽测试。

## 路线图约束

- 不因存在局部类型跳过端到端接线。
- 不在真实 SPDK I/O 验证前宣称数据面可用。
- 不在 commit evidence 完成前采用 2/3 成功语义。
- 不在 fencing 验证前自动切换 primary。
- 不在双向认证完成前放宽可信隔离网络要求。

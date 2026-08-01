# 目标与原则

> 状态：目标设计；部分原则已在当前组件中体现

## 架构目标

### Tier 1：本地文件系统

- 从单个容器文件或显式选择的 raw devices 挂载 Linux FUSE 文件系统。
- 保持格式可恢复、设备选择安全、失败时 fail closed。
- 不要求常驻服务、网络文件协议或 qtr。

### Tier 2：单节点 VM 存储

- 一个 Zettide storage node 管理可在线演进的本地 Pool 和多个 Volume。
- Pool 聚合容量并提供默认保护策略；Volume 可以覆盖默认副本目标。
- 加盘可以只增加容量，也可以触发目标 Volume 的保护级别迁移。
- 以标准 iSCSI 作为第一个 VM-facing protocol，qtr 通过 managed backend 完成 publish、login、attach 和重启 reconciliation。
- 本地多副本可以抵抗设备故障，但单 storage node 故障仍导致服务不可用。

### Tier 3：分布式高可用存储

Zettide 面向可信私有集群提供分布式 Volume：

- Pool 是跨节点资源边界，一个 Pool 包含多个 Volume。
- 每个 Volume 默认有三个副本，分布在不同节点故障域。
- 每个可写 Volume 只有一个 primary。
- primary 在至少 2/3 副本持久化写入后才确认成功。
- 控制面元数据通过 Raft 提交，并支持线性一致读取。
- 节点之间的数据通信使用 SPDK NVMf/RDMA。Fabric 可以是 InfiniBand、RoCE 或经过兼容验证的 iWARP。
- 除数据块和重同步数据之外的通信使用 grpc-lite。
- 旧 primary、旧 epoch 和不确定提交必须 fail closed。
- qtr 保持相同 Volume identity，并能在调用方指定的新 host 上 republish。

## 非目标

初始阶段不追求：

- 在公网或不可信租户网络直接暴露内部 RPC 和 NVMf。
- 多主并发写同一 Volume。
- 跨地域同步复制。
- 纠删码数据路径。
- 让每次数据 I/O 经过 Raft。
- 在缺少可验证提交证据时自动选择“看起来最新”的副本。
- 在 Tier 1 提供网络文件系统。
- 在 Tier 2 抵抗整个 storage node 故障。
- 由存储系统自动选择 VM host、迁移 VM 或重启 VM。

## 设计原则

### 1. 权威状态与观测状态分离

Raft 保存 desired state；当前 leader 保存 heartbeat 和 observed state；Member/Replica 保存本地持久化事实。控制器通过 reconciliation 使三者收敛。“命令已下发”不等于“数据已就绪”。

### 2. 控制面与数据面分离

Raft 处理低频元数据和所有权变更，NVMf 处理高频块 I/O。正常读写路径不依赖控制面逐请求参与。

### 3. 不确定时停止写入

无法证明 lease、epoch、placement、提交边界或副本持久性时，Volume 停止确认新写入。当前 `zettide` 的 sticky write freeze 是这一原则在本地故障场景中的先行实现。

### 4. 单调 epoch 执行 fencing

Lease 限制授权时间，Volume write epoch 永久隔离历史 primary。二者不能互相替代。Replica 必须持久化最高接受 epoch，并独立拒绝旧 epoch 写入。

### 5. 稳定身份不依赖地址

Pool、Volume、Node、Member 和 Replica 使用稳定 ID。IP、NQN、listener、设备路径和进程 incarnation 都是可变属性。

### 6. Primary 不是 Raft leader

Raft leader 协调控制面日志；Volume primary 协调一个 Volume 的数据写入。二者作用域、故障切换和版本号完全独立。

### 7. Member 是本地持久化故障边界

Member 具有独立身份、几何、控制历史和错误状态。设备路径只是当前位置，不是 Member 身份。

### 8. 有界资源和显式背压

RPC buffer、Raft proposal queue、heartbeat、reconciliation task 和 repair bandwidth 必须有容量限制。过载时拒绝、延迟或合并，不能无限占用内存。

### 9. 格式和恢复证据先于自动化

提交记录、校验信息、版本和恢复规则必须先稳定，再引入自动 failover、repair 和 rebalance。

### 10. 显式降级

系统使用三个正交维度：生命周期、可用性/保护状态和运行阶段。可用性至少区分 Healthy、Degraded、ReadOnly、Unavailable；运行阶段可以是 Fencing、Recovering、Repairing 或 None。不用单一“在线”状态掩盖数据保护级别。

### 11. 不夸大安全能力

TLS server authentication 不等于 mTLS；cluster ID 和 node ID 不等于认证。首版只能部署在可信隔离网络。

### 12. 可验证后再自动化

Primary 自动切换、Replica 重建和在线成员变更必须经过崩溃、断网、旧 primary 恢复和介质损坏测试。

### 13. 容量与保护解耦

Pool Member topology 只回答“有哪些容量和故障边界”。Pool default 与 Volume override 回答“一个 Volume 需要多少副本”。系统分别报告 desired protection、current protection 和 migration phase；增加 Member 不自动改变已有 Volume 的数据保护语义。

### 14. Attachment 使用稳定身份

Volume ID、publication ID、qtr host ID 和 VM disk ID 是恢复依据。iSCSI portal、IQN/LUN session、Linux block path 和 libvirt target 是派生状态，不能替代稳定身份。Detach 必须先撤销 VM 使用，再释放 session 和 publication。

## 成功标准

Tier 1 需要能够证明 file-backed 与 raw-device mount、恢复和错误处理符合声明语义。

Tier 2 需要能够证明在线加盘不会隐式改变保护策略，保护迁移在中断后可恢复，并且 qtr 的 create/publish/login/attach/restart/detach 流程幂等收敛。

Tier 3 需要能够证明：

- 控制面重启和 leader 切换不丢失已确认元数据。
- 同一 Volume 不存在两个可取得数据 quorum 的 primary。
- 对已达到默认 3/2 current protection 的 Volume，客户端成功写入后任一单副本故障不会丢失该写入；override 按其实际保护级别承诺。
- 旧 epoch 在所有合格 Replica 上被拒绝。
- Node 重启依靠持久化身份和状态恢复，而不是进程内存。
- NVMf namespace 的发布和撤销受 placement、lease 和 epoch 约束。
- 控制面或数据面无法形成 quorum 时，系统不会静默降低一致性。
- Storage primary 切换后旧 primary 受 Volume epoch fencing；qtr host 转移时旧 session 受独立 publication access-generation fencing，同一 Volume 可安全 republish 到指定 host。

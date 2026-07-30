# 领域模型

> 状态：Pool、durable Volume metadata intent、NodeRegistration/MemberRegistration 与 leader-local NodeObservation 首个切片当前实现；其余为目标设计

## 模型边界

`zettide-control` 管理集群级元数据，不承载数据块。权威状态通过 Raft 复制，查询视图保存在内存，并由 WAL 和 snapshot 恢复。

控制面 Pool 是跨节点资源域。一个 Pool 包含多个 Volume；一个 Node 可以为一个或多个 Pool 提供本地 Member 容量；一个 Volume 的 Replica 分布在多个 Node 故障域。

## 核心实体

| 实体 | 关键职责 | 持久位置 |
| --- | --- | --- |
| Pool | Volume 命名空间、资源和策略边界 | Raft 状态机 |
| Volume | 容量、保护策略、生命周期、write epoch | Raft 状态机 |
| NodeRegistration | 节点身份、控制/NVMf endpoint、能力、故障域 | Raft 状态机 |
| MemberRegistration | 本地持久单元与控制面 Pool/Node 的绑定 | Raft 状态机 |
| ReplicaPlacement | Volume Replica 的目标 Node、角色和 generation | Raft 状态机 |
| ReplicaAllocation | Replica 在 Member 上不重叠的 extent/range | Raft 状态机 + Node 本地 catalog |
| VolumeLease | 当前 primary holder、lease ID、epoch 和授权边界 | Raft 状态机 |
| NodeObservation | incarnation、heartbeat、容量和运行状态 | 当前 leader 内存 |
| ReplicaObservation | 实际 generation、applied/committed position、健康和修复进度 | 当前 leader 内存 |
| ReconciliationAction | desired/observed 差异产生的幂等动作 | 派生任务；结果按需提交 Raft |

## 实体关系

```mermaid
erDiagram
    POOL ||--o{ VOLUME : contains
    POOL ||--o{ MEMBER : aggregates
    NODE ||--o{ MEMBER : hosts
    VOLUME ||--|{ REPLICA : protects
    NODE ||--o{ REPLICA : serves
    REPLICA ||--|{ ALLOCATION : maps
    MEMBER ||--o{ ALLOCATION : stores
    VOLUME ||--o| LEASE : authorizes
    NODE ||--o{ LEASE : holds

    POOL {
        uuid pool_id
        string name
        uint64 revision
    }
    VOLUME {
        uuid volume_id
        uuid pool_id
        uint64 size_bytes
        uint64 write_epoch
        string state
    }
    NODE {
        uuid node_id
        string failure_domain
        string management_state
    }
    MEMBER {
        bytes member_id
        bytes local_set_id
        uuid node_id
        uuid pool_id
        uint16 member_slot
    }
    REPLICA {
        uuid replica_id
        uuid volume_id
        uint64 generation
        string desired_state
    }
    ALLOCATION {
        uuid allocation_id
        uuid member_id
        uint64 offset
        uint64 length
        uint64 generation
    }
    LEASE {
        uuid lease_id
        uuid volume_id
        uuid holder_node_id
        uint64 write_epoch
    }
```

## Desired、Observed 与 Persistent Facts

```mermaid
flowchart LR
    API[管理请求] --> Desired[Raft Desired State]
    Heartbeat[Heartbeat / Report] --> Observed[Leader Observed State]
    Disk[Member / Replica Metadata] --> Facts[Persistent Facts]
    Desired --> Reconciler[Reconciler]
    Observed --> Reconciler
    Facts --> Reconciler
    Reconciler --> Action[幂等动作]
    Action --> Node[DataService]
    Node --> Heartbeat
    Reconciler -->|权威变化| Command[Raft Command]
    Command --> Desired
```

- Desired state 回答“系统应该是什么”。
- Observed state 回答“当前 leader 最近观察到什么”。
- Persistent facts 回答“节点重启后仍能从介质证明什么”。

Heartbeat 丢失可以将 Node 标记为 suspected，但不能直接删除 registration、提升 primary 或宣告数据丢失。任何写入权威变更必须形成 Raft command。

## 核心不变量

1. Pool、Volume、Node、Member 和 Replica ID 在各自作用域内唯一且不复用。
2. 一个 Volume 属于且只属于一个 Pool。
3. 一个 Replica 属于且只属于一个 Volume，并绑定一个 Node；其 allocation 映射到一个或多个不重叠 Member extent。
4. 同一 Volume 的多个 Replica 不得放在同一主机故障域。
5. 默认 Volume 具有三个目标 Replica，写 quorum 为两个。
6. Primary 必须是当前 placement 中的一个合格 Replica；任意两个合格 Replica 可以组成写 quorum。
7. 一个可写 Volume 至多有一个有效 primary lease。
8. Volume write epoch 单调递增，不回退、不复用。
9. 任何可能使旧 primary 与新 primary 并存的操作必须推进 epoch。
10. Replica generation 在重建后变化；旧 generation 的 endpoint 不得重新加入当前 placement。
11. Observed state 不能覆盖 desired state 或介质上的持久事实。
12. 修复中的 Replica 不参与写 quorum 或 primary 候选集合。
13. Placement 变更先建立新保护，再撤销仍承担 quorum 的旧 Replica。
14. Raft apply 必须确定、原子且无外部副作用。ID、时间和 placement 结果在 proposal 前确定。
15. 变更请求具有稳定 request ID；同 ID 不同语义必须返回冲突。

## Volume 生命周期与保护状态

```mermaid
stateDiagram-v2
    [*] --> Provisioning
    Provisioning --> Active: 至少两个合格副本且 primary fenced
    Provisioning --> Failed: 无法满足 placement
    Active --> Deleting
    Failed --> Deleting
    Deleting --> [*]
```

状态分为三个正交字段：

- `lifecycle_state`：Provisioning、Active、Deleting、Failed。
- `availability_state`：Healthy、Degraded、ReadOnly、Unavailable。
- `operation_phase`：None、Fencing、Recovering、Repairing。

例如修复第三个副本时，Volume 可以同时是 `Active + Degraded + Repairing`。三副本合格才是 Healthy；只有两个合格副本时是 Degraded。对外展示按 Unavailable、ReadOnly、Degraded、Healthy 的可用性优先级呈现，并单独附带 operation phase。

## 当前实现与差距

当前 `zettide-control` 实现 Pool、durable Volume metadata intent，以及 create-only 的 durable NodeRegistration 和 MemberRegistration。CreateVolume 保存 Pool 归属、逻辑容量、固定 3/2/1 保护参数、`Provisioning + Unknown + None` 状态、初始 generation/write epoch、创建 revision 和 resource version，但不选择 placement、不预留 extent，也不等待数据面 READY。GetVolume 经过 ReadIndex；DeleteVolume 要求 expected resource version，仅允许无 Replica/Attachment 引用的 Volume，并原子保留永久有界 tombstone。删除后名称可复用，Volume ID 不复用。

控制协议和 v5 状态快照已定义 ReplicaPlacement、ReplicaAllocation 与 VolumeAttachment durable schema。恢复会验证故障域、Pool/Node/Member 引用、extent 对齐与不重叠，以及 consumer 唯一性；当前尚无创建或演进这些 child resource 的 command，因此这些类型不代表 placement 或 attachment 已接通。

NodeRegistration 保存稳定 Node ID、cluster binding、control/NVMf endpoint、failure domain、capability bits、protocol version、注册时间和 revision；不保存 heartbeat、容量或在线状态。

MemberRegistration 使用介质原生 16-byte Member ID，绑定控制面 Pool、hosting Node 与 16-byte local set ID，并保存稳定 slot、birth topology digest、metadata/data capacity 和 extent size。Member ID 全局唯一；一个 local set 只绑定一个控制面 Pool；同一 local set 的 slot 不可冲突。设备路径、当前 topology/authority、使用量和健康不进入 registration。

状态机使用 Pool/Node/Member/Volume 共享 request history、v5 快照与恢复，并兼容读取 v2 Pool-only、v3 Pool/Node 和 v4 Pool/Node/Member 快照。当前 NodeObservation 只包含 Node incarnation/sequence、接受时间、leader term、Member presence 和可选 extent capacity；相同 ordering tuple 的相同语义可重放，不同语义或回退会冲突。Observation 只存在于当前 leader 内存，5 秒后 stale，leader 切换或恢复 snapshot 时清空，不覆盖 registration，也不进入 WAL/snapshot。

Volume placement 和 lifecycle 收敛、Replica/Allocation/Attachment mutation、lease、epoch enforcement、路径健康、Replica positions 和 repair progress 尚无实现；Node 更新、隔离和注销以及 Member lifecycle 也尚未实现。当前 v3 Pool 的公共数据区只承载一个 Volume，尚无多 Volume extent allocator 和 durable local catalog。

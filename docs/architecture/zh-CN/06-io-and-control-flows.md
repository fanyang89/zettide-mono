# I/O 与控制流程

> 状态：目标流程

## 通信边界

| 流量 | 协议 |
| --- | --- |
| Replica vendor commands、数据读写和重同步 | SPDK NVMf/RDMA（IB、RoCE 或 iWARP） |
| Node 注册、heartbeat 和状态报告 | grpc-lite |
| Volume/Replica 创建和删除 | grpc-lite |
| Primary、lease、epoch 与 fencing 协调 | grpc-lite |
| NVMf endpoint/namespace 发现 | grpc-lite |
| 控制节点间 Raft 消息 | raft-zig over grpc-lite |

## 节点注册

```mermaid
sequenceDiagram
    participant N as Zettide Node
    participant D as DataService
    participant S as SPDK Runtime
    participant C as Control Leader
    participant R as Raft

    N->>N: 读取 stable node ID 和本地 Replica facts
    N->>S: 初始化 bdev / NVMf capability
    N->>D: 启动控制服务
    D->>C: RegisterNode(identity, endpoints, capability)
    C->>R: 提交 NodeRegistration
    R-->>C: applied
    C-->>D: registration revision
    loop Heartbeat
        D->>C: incarnation, capacity, replicas, paths
        C-->>D: latest desired revision
    end
```

Registration 持久化，heartbeat 易失。Leader 切换后 Node 无需创建新身份，但必须向新 leader 重新 heartbeat。

## 创建 Volume

```mermaid
sequenceDiagram
    participant U as Client
    participant C as Control Leader
    participant R as Raft
    participant A as Node A
    participant B as Node B
    participant D as Node C

    U->>C: CreateVolume(request_id, pool, size)
    C->>C: 选择故障域、Member extents 和初始 primary
    C->>R: 条件预留 Volume + placements + allocations + epoch
    R-->>C: applied
    par Create Replica A
        C->>A: EnsureReplica(id, allocation, generation)
        A->>A: 原子校验无重叠并写 local catalog
        A-->>C: Ready(endpoint, local facts)
    and Create Replica B
        C->>B: EnsureReplica(id, allocation, generation)
        B->>B: 原子校验无重叠并写 local catalog
        B-->>C: Ready(endpoint, local facts)
    and Create Replica C
        C->>D: EnsureReplica(id, allocation, generation)
        D->>D: 原子校验无重叠并写 local catalog
        D-->>C: Ready(endpoint, local facts)
    end
    C->>R: 激活 allocations + pending lease grant
    R-->>C: applied
    C->>A: PendingGrant(epoch, nonce, duration)
    A->>A: 启动本地 monotonic deadline
    A-->>C: ActivationAck(nonce)
    C->>R: 提交 activated lease
    R-->>C: applied
    par Replica A fencing barrier
        C->>A: Quiesce, drain, flush, persist epoch
        A-->>C: fenced
    and Replica B fencing barrier
        C->>B: Quiesce, drain, flush, persist epoch
        B-->>C: fenced
    end
    A->>B: NVMf connect with epoch-bound access
    A->>D: NVMf connect with epoch-bound access
    A-->>C: lease + data boundary + fencing quorum ready
    C-->>U: Volume Available
```

Allocation reservation 包含 allocation ID、Member ID、offset、length 和 generation，并通过 Raft 条件事务防止控制面重叠。Node local catalog 是第二道持久校验，发现冲突时拒绝而不自行改选范围。部分创建失败时 reservation 保留，由 reconciler 重试或显式 tombstone 后重新放置。

`EnsureReplica` 以 Replica/allocation ID 和 generation 幂等。删除时先撤销 namespace/session，再写 generation tombstone 并进入 quarantine；只有控制面确认旧 generation 不再可达、Node catalog 已持久更新后，extent 才能重新分配。

## 写入和读取

```mermaid
sequenceDiagram
    participant App as Application
    participant F as Local Frontend
    participant P as Primary Engine
    participant J as Replication Journal
    participant L as Local Replica
    participant R1 as Remote Replica B
    participant R2 as Remote Replica C

    App->>F: write / fsync
    F->>P: block write
    P->>P: check lease + epoch
    par PREPARE vendor command
        P->>L: prepare(metadata, payload)
        L-->>P: durable prepare digest
    and NVMf PREPARE
        P->>R1: prepare(metadata, payload)
        R1-->>P: durable prepare digest
    and NVMf PREPARE
        P->>R2: prepare(metadata, payload)
        R2-->>P: digest or timeout
    end
    P->>J: form quorum commit certificate
    par COMMIT certificate
        P->>L: persist certificate
        L-->>P: durable
    and NVMf COMMIT
        P->>R1: persist certificate
        R1-->>P: durable
    end
    P->>J: advance committed position
    P-->>F: success
    F-->>App: success

    App->>F: read
    F->>P: block read
    P->>P: choose current healthy replica
    P->>L: read
    L-->>P: data + integrity result
    P-->>App: data
```

第三个 Replica 未确认时对应范围进入 dirty set，后台 resync 不改变已确认写入的可见性。

## Primary 故障切换

```mermaid
sequenceDiagram
    participant C as Control Leader
    participant R as Raft
    participant Old as Old Primary
    participant B as Replica B
    participant N as New Primary

    C-xOld: heartbeat / path lost
    C->>B: PreliminaryCandidateState
    C->>N: PreliminaryCandidateState
    C->>R: 提交 new primary + higher epoch + pending lease
    R-->>C: applied
    C->>B: Quiesce and drain old session
    C->>N: Quiesce and drain old session
    B->>B: Flush, persist max epoch, reopen
    N->>N: Flush, persist max epoch, reopen
    B-->>C: fenced
    N-->>C: fenced
    C->>B: CollectFinalManifest
    C->>N: CollectFinalManifest
    B-->>C: drained certified history
    N-->>C: drained certified history
    C->>C: 合并 candidates，确定连续 committed prefix
    N->>B: write-back candidates + recovery frontier
    N->>N: 物化并校验完整前缀
    N-->>C: ActivationAck(nonce)
    C->>R: 激活 lease 和 recovery revision
    R-->>C: applied
    N-->>C: primary ready
    Note over Old: 旧 session 和旧 epoch 写入被拒绝
```

仅 heartbeat 存活不足以成为 primary。Fencing quorum 必须先阻止旧 epoch 新写入并 drain 已接收 I/O，然后才能收集最终 manifest。控制面从该 recovery quorum 的 certificates 恢复并集、write-back 单份 candidate、持久化新 frontier；候选物化完整连续前缀并激活 lease 后才能开放写入。

## Replica 恢复

1. 恢复节点校验 Volume ID、Replica ID、generation 和 epoch。
2. 旧副本标记为 Stale/Rebuilding，不参与读、写 quorum 或 failover。
3. Primary 比较 journal position、dirty ranges 和数据摘要。
4. Journal 覆盖时增量追赶，否则执行范围或全量 rebuild。
5. 对追赶结果执行 checksum/summary 验证。
6. 追平当前 committed position 后，上报 Ready。
7. Reconciler 提交其合格状态，恢复三副本保护。

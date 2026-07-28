# 系统架构

> 状态：当前组件基础 + 目标集成架构

## 系统上下文

```mermaid
flowchart LR
    Client[管理客户端]
    App[本机应用]

    subgraph CP[zettide-control 集群]
        API[grpc-lite API]
        Loop[Control Loop]
        Barrier[ReadIndex Barrier]
        SM[内存元数据状态机]
        Raft[raft-zig]
        WAL[WAL]
        Snapshot[Snapshot]
        API --> Loop --> Raft
        Raft -->|committed apply| SM
        Raft --> WAL
        SM --> Snapshot
        API -. linearizable read .-> Barrier
        Barrier --> Raft
        Barrier -->|applied >= read index| SM
    end

    subgraph A[Zettide Node A]
        FE1[本地前端]
        DS1[DataService]
        VE1[Volume Engine / Primary]
        SPDK1[SPDK bdev + NVMf]
        Media1[Member / Replica]
        FE1 --> VE1 --> SPDK1 --> Media1
        DS1 --> VE1
    end

    subgraph B[Zettide Node B]
        DS2[DataService]
        SPDK2[SPDK NVMf]
        Media2[Member / Replica]
        DS2 --> SPDK2 --> Media2
    end

    subgraph C[Zettide Node C]
        DS3[DataService]
        SPDK3[SPDK NVMf]
        Media3[Member / Replica]
        DS3 --> SPDK3 --> Media3
    end

    Client -->|grpc-lite| API
    App --> FE1
    API -. 注册、placement、lease、状态 .-> DS1
    API -. grpc-lite .-> DS2
    API -. grpc-lite .-> DS3
    VE1 -. NVMf/RDMA: IB, RoCE or iWARP .-> SPDK2
    VE1 -. NVMf/RDMA: IB, RoCE or iWARP .-> SPDK3
```

虚线表示目标集成。当前尚无 DataService、跨节点 Volume Engine 和 NVMf 数据路径。

## 组件职责

### zettide-control

目标职责：

- 保存 Pool、Volume、Node、Replica、placement、lease 和 epoch。
- 处理管理 API 和节点注册。
- 选择 Replica 放置位置与 primary。
- 比较 desired/observed state 并执行 reconciliation。
- 通过 Raft 提交所有权威元数据变更。

当前只实现 Pool 协议和 Pool 内存状态机，尚未装配网络服务和 Raft 集群运行时。

### raft-zig

职责：

- 复制控制面状态机命令。
- 持久化 HardState、日志、membership 和 snapshot。
- 提供 proposal callback 与 ReadIndex。
- 通过 grpc-lite persistent stream 传输 Raft 消息。

生产控制面必须配置持久 `data_dir`；空目录配置使用 MemoryStorage，不具备重启持久性。

### grpc-lite

职责：

- 承载管理、注册、heartbeat、reconciliation 和 Raft RPC。
- 提供 unary/streaming、deadline、metadata、流控和有界缓冲。
- 在 reactor 线程运行回调；业务逻辑不得阻塞回调线程。

grpc-lite 不负责数据副本复制，也不提供自动 RPC retry、负载均衡或 mTLS。

### zettide

当前职责：

- 管理容器、littlefs、对象层和 FUSE 前端。
- 管理 Member v3 格式、Pool topology、layout 和 control journal。
- 通过本地 `ReplicaEndpoint` 访问 Member 数据区域。
- 在本地三成员复制失败后冻结 writer。

目标新增职责：

- 运行常驻 DataService、Volume Engine 和 SPDK reactor。
- 管理本地 Replica 与 NVMf namespace。
- 作为 initiator 访问远程 Replica。
- 执行 primary 写入排序、2/3 提交、fencing 和 resync。

### SPDK/NVMf

目标职责：

- 将本地介质和 Replica 暴露为 bdev。
- 为 Replica 创建受控 NVMf namespace。
- 通过 NVMf/RDMA 传输跨节点数据；RDMA provider 可以使用 InfiniBand、RoCE 或兼容的 iWARP。
- 将 I/O completion 映射到明确的 durable flush/FUA 语义。

当前只完成编译和链接探针，不启动 SPDK application framework。

## 控制路径

1. 请求到达当前 `zettide-control` leader。
2. Leader 在 proposal 前完成权限、参数和幂等校验，并生成确定性命令。
3. Raft 多数派持久化并提交命令。
4. 本地状态机 apply 后返回结果。
5. Reconciler 根据 desired state 和节点上报生成幂等动作。
6. DataService 执行动作并上报 observed state。
7. 需要改变权威关系的结果再次通过 Raft 提交。

## 数据路径

1. 本机应用通过 zettide 前端访问 Volume。
2. 前端将块请求交给当前 primary Volume Engine。
3. Primary 检查 lease 和 write epoch。
4. Primary 将写入发送到本地及远程 Replica。
5. 至少两个 Replica 持久化 prepare/data record；随后至少两个 Replica 持久化 quorum commit certificate，primary 才确认成功。
6. 未确认的第三副本通过 journal/dirty ranges 后台追赶。

Raft 不进入这个逐 I/O 同步路径。

## 关键版本域

| 值 | 作用域 | 用途 |
| --- | --- | --- |
| Raft term | 控制面 Raft group | Raft leader 任期 |
| 本地 v3 Pool membership epoch | 一个本地 v3 Pool topology | Member 集合和角色版本 |
| Volume write epoch | 单个 Volume | Primary 写入 fencing |
| Replica generation | 单个 Replica 数据实例 | 区分重建后的数据代次 |
| Lease ID | 单次 primary 授权 | 区分具体授权实例 |
| Revision | 控制面状态 | 已 apply 的元数据版本 |

这些值不得相互替代或隐式转换。

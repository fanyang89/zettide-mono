# 术语表

## Pool

目标控制面中的跨节点资源、策略和 Volume 管理边界。

当前还有一个同名概念：`zettide` v3 Pool 是由本地 Member、topology、layout 和 control journal 构成的持久化集合。文档在可能歧义时使用“控制面 Pool”和“本地 v3 Pool”。

## Volume

向本地前端提供固定逻辑容量和块语义的存储资源。目标 Volume 属于一个 Pool，具有 Replica 集合、primary、lease 和 write epoch。

当前 `zettide` 也使用 Volume 表示可挂载 littlefs 容器或建立在本地 Pool 上的文件系统实例；控制面尚无 Volume 模型。

## Node

运行 DataService、Volume Engine 和 SPDK/NVMf 的受管存储节点，使用稳定 `node_id`。

`raft-zig` 的 node 是 Raft 参与者，属于另一个身份域。

## Member

本地 v3 Pool 中具有独立身份、slot、几何、控制记录和数据区域的持久化单元。文件路径或块设备路径是位置，不是 Member 身份。

## Replica

一个 Volume 的持久化数据副本。目标 Replica 绑定 Volume、Node 和本地介质，并持久化 Replica generation、applied position 和最高接受 epoch。

当前 `ReplicaEndpoint` 只是进程内 I/O vtable，不是跨节点协议。

## Primary

某个 Volume 当前唯一的数据写协调者。Primary 检查 lease、分配写序列、复制数据并形成 2/3 持久提交。

Primary 不是 Raft leader。

## Lease

控制面授予 Volume primary 的有限期写权限，至少绑定 Volume、holder、lease ID 和 write epoch。Lease 到期或无法安全续租时，primary 停止新写入。

## Epoch

单调递增的 fencing 版本。必须明确作用域：

- 本地 v3 Pool membership epoch：Member topology 版本；未来控制面 placement 使用独立 revision。
- Volume write epoch：Volume 写入权威版本。
- Raft term：Raft leader 任期，不是 Volume epoch。

## Generation

一个持久化对象或副本的数据代次。Replica 重建后使用新 generation，防止旧 namespace 或旧本地数据被误认为当前副本。

## Revision

控制面状态机的已提交版本，通常对应或派生自 apply 的 Raft log index。

## Desired State

Raft 状态机中保存的权威目标，例如 placement、primary、epoch 和管理状态。

## Observed State

当前 leader 根据 heartbeat、状态上报和探测得到的运行时事实，例如节点可达性、Replica applied position 和 repair progress。Observed state 本身不授予写权限。

## Reconciliation

比较 desired/observed state，生成幂等动作并推动系统收敛的过程。

## Authority

从持久控制记录和 quorum 证据中选择出的可接受状态。Authority 是恢复概念，不表示安全认证。

## Quorum

完成某类决策所需的最小参与者集合。必须区分 Raft quorum、Pool control quorum 和 Volume data commit quorum。

## Fencing

阻止旧所有者继续写入的机制。目标 Volume fencing 使用 lease 和单调 write epoch，并由 Replica 在持久写入边界执行。

## NVMf

NVMe over Fabrics。Zettide 目标数据面通过 SPDK NVMf 在节点间访问 Volume Replica namespace。

## RDMA 与 iWARP

RDMA 是目标低延迟数据 transport。InfiniBand、RoCE 和 iWARP 是不同 RDMA 环境；SPDK 暴露统一的 `RDMA` transport，由底层 provider 决定具体模式。iWARP 仍需要兼容 RNIC、verbs provider 和网络栈，不是普通 TCP socket fallback。

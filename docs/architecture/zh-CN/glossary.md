# 术语表

## Pool

Volume 命名空间、Member 容量和默认保护策略边界。Tier 2 Pool 位于一个 storage node；Tier 3 控制面 Pool 聚合多个 Node 的资源。

当前还有一个同名概念：`zettide` v3 Pool 是由本地 Member、topology、layout 和 control journal 构成的持久化集合。文档在可能歧义时使用“控制面 Pool”和“本地 v3 Pool”。

## Volume

向文件系统或 VM-facing frontend 提供固定逻辑容量和块语义的存储资源。Volume 属于一个 Pool，可以继承 Pool default protection 或使用自身 override；Tier 3 Volume 还具有 Replica 集合、primary、lease 和 write epoch。

当前控制面 Volume 是 durable `PROVISIONING` metadata intent，支持 Create/Get 和无依赖条件下的 tombstone Delete；尚未接通 placement、数据面或前端。本地文件系统产品使用 BlobFilesystem，不把它称为 Volume。

## BlobFilesystem 与 Blob store

BlobFilesystem 是当前 `zettide` 唯一的文件系统产品。backend-neutral FUSE/POSIX frontend 将其挂载到 Linux；其 immutable blob 与 COW metadata 由 Blob stores 持久化到 regular Blob file 或 raw-disk Blob Pool。CAWFS 是独立共享存储方向，不是 BlobFilesystem backend。

## Node

运行 DataService、Volume Engine 和 SPDK/NVMf 的受管存储节点，使用稳定 `node_id`。

`raft-zig` 的 node 是 Raft 参与者，属于另一个身份域。

## Member

本地 v3 Pool 中具有独立身份、slot、几何、控制记录和数据区域的持久化单元。文件路径或块设备路径是位置，不是 Member 身份。

## Replica

一个 Volume 的持久化数据副本。目标 Replica 绑定 Volume、Node 和本地介质，并持久化 Replica generation、applied position 和最高接受 epoch。

当前 `ReplicaEndpoint` 只是进程内 I/O vtable，不是跨节点协议。

## Primary

某个 Volume 当前唯一的数据写协调者。Primary 检查 lease、分配写序列、复制数据并按 protection policy 形成持久 quorum commit；Tier 3 默认 profile 是 2/3。

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

NVMf 是 Tier 3 内部 Replica transport，不是 qtr 的首个 VM-facing protocol。

## RDMA 与 iWARP

RDMA 是目标低延迟数据 transport。InfiniBand、RoCE 和 iWARP 是不同 RDMA 环境；SPDK 暴露统一的 `RDMA` transport，由底层 provider 决定具体模式。iWARP 仍需要兼容 RNIC、verbs provider 和网络栈，不是普通 TCP socket fallback。

## Tier 1 / Tier 2 / Tier 3

- Tier 1：从 regular Blob file 或 raw-disk Blob Pool 提供本机 BlobFilesystem FUSE/POSIX mount。
- Tier 2：一个 Zettide storage node 通过 iSCSI 向 qtr 提供受管 catalog Volume。
- Tier 3：多 storage nodes 同步复制 Volume，执行 storage failover、repair 和 qtr republish。

三个 Tier 是累积能力。Tier 3 不包含 VM host 调度或自动 VM restart。

## Protection Policy

Volume 期望的数据副本策略。Pool 提供 default，Volume 可以 override。必须区分 desired protection、current protection 和 migration phase；Pool Member 数量不能证明某个 Volume 已达到目标副本数。

## Publication

Zettide DataService 将一个 Volume 暴露给指定 consumer/host 的受管 VM-facing block endpoint。Tier 2 首个 publication protocol 是 iSCSI。Volume ID、publication ID 和稳定 SCSI serial/WWID 是身份依据；portal、IQN、LUN 和 session 是可 reconciliation 的 locator/runtime 信息，即使实现让它们在重启后保持稳定也不能替代权威身份。

Exclusive publication 还具有单调 access generation。Tier 2 在本地持久化；Tier 3 由 Raft 保存 publication authority，各 DataService 持久化最高 installed generation。可达旧 target 通过 session context、ACL/credential、quiesce、drain 和撤销隔离；失联旧 target 还必须依赖 primary lease 到期和 Replica epoch fencing。Volume write epoch 与 publication generation 不能互相替代。

## Attachment

Volume publication、qtr host、VM disk consumer 与 libvirt disk 之间的持久期望关系。Attach 在任何外部副作用前持久化 intent，再建立 publication/session 并修改 libvirt；detach 先持久化 detaching intent，再按相反顺序释放资源。

## Republish

旧 publication access generation 被 fencing 后，Zettide DataService 为同一 Volume/consumer 激活新 generation，调用方指定的 qtr host 建立新 initiator session 和 attachment 的过程。若 storage primary 同时失效，还必须先完成独立的 Volume epoch fencing 和 committed-boundary recovery。Republish 是 storage HA 能力，不等于 VM 调度或自动重启。

## iSCSI

Tier 2 首个 qtr/VM-facing block protocol。qtr host 使用 initiator login 后将发现的 block device 接入 libvirt。iSCSI 不决定 Replica placement、quorum 或 write epoch。

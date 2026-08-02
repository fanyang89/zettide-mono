# 演进路线图

> 状态：实施顺序建议，不代表发布日期

## 已有基础

- Tier 1 file-backed 和 raw-device FUSE CLI、格式、恢复和 syscall tests 已存在。
- 单成员 unprotected v3 target 格式化，以及受监管的外部 dufs HTTP/WebDAV 前端已存在。
- 本地 dynamic topology/membership、multi-Volume catalog、extent mapping、catalog data lease 和 writable backend 已有库级实现。
- managed SPDK runtime、bdev dispatcher、NVMe-oF initiator、异步 bdev provider 和 vhost-user-blk export 已有 focused tests。
- `zettide-control` 已有 Pool/Node/Member/Volume durable metadata、heartbeat、静态多 voter Raft runtime、WAL/snapshot/ReadIndex 和恢复测试。
- qtr 已有手动外部 iSCSI discovery、login/logout 和本地 block-device VM attachment。

这些基础不等于 Tier 2 或 Tier 3 已端到端交付。

## Milestone 1：稳定并完成 Tier 1

- 保持 container file 与 raw Pool FUSE 入口、恢复语义和 privileged tests 稳定。
- 明确当前 raw Pool 产品支持范围为一个无保护设备或三个复制设备。
- 按 POSIX profile 关闭未完成语义，并把当前可用路径与完整 Tier 准入分开报告。

完成标准：支持矩阵内的 filesystem 行为具有可执行 CLI、恢复测试和明确错误语义；不依赖常驻 daemon 或网络服务。

## Milestone 2：Tier 2 动态 Pool 与保护策略

- 将 Member joining/active/draining 和 catalog capacity publication 接入产品生命周期。
- 为 Pool 增加 default protection，为 Volume 增加可选 override。
- 分离 desired protection、current protection 和 migration phase。
- 支持加盘仅扩容，或按显式策略为选定 Volume 增加 Replica。
- 实现可恢复的 copy/verify/publish migration；删除旧 Replica 必须晚于新保护达成。

完成标准：单盘 Pool 可在线加盘；已有单副本 Volume 可以保持单副本或显式提升副本数；任意迁移崩溃点均可安全恢复。

## Milestone 3：Tier 2 常驻服务与 iSCSI

- 装配 Zettide DataService、稳定本地管理 API 和持久 endpoint registry。
- 将 catalog Volume backend 接入受管 SPDK iSCSI target、IQN/LUN 和 publication lifecycle。
- 定义 publication identity、单调 access generation、幂等 publish/unpublish、session drain、ACL/credential 撤销和 restart recovery。
- 在真实测试设备验证 flush、discard、resize、target restart 和 session reconnect。
- 保留 vhost-user-blk 为可选 frontend，不阻塞 iSCSI 首发。

完成标准：一个 storage node 可创建多个 Volume，并在重启后恢复相同 publication identity 和数据。

## Milestone 4：Tier 2 qtr Managed Backend

- qtr schema 引用稳定 Zettide backend/Volume identity，不持久化瞬时设备路径。
- 实现 publish、discover/login、设备验证、libvirt attach、detach/logout/unpublish。
- 在任何外部副作用前持久化 attachment intent，并在 qtr/Zettide/iSCSI/libvirt 任一组件重启后 reconciliation。
- 验证响应丢失、重复请求、session 丢失、设备枚举变化和 detach 中断。

完成标准：create/publish/attach/restart/detach E2E 自动收敛，不要求操作者手工运行 `iscsiadm` 或填写 `/dev/...`。

## Milestone 5：Tier 3 Placement 与 Replica 生命周期

- DataService 注册本地 topology、capacity、authority 和 Replica observation。
- 实现 ReplicaPlacement/ReplicaAllocation/VolumeAttachment mutation、extent allocator 和 reconciliation。
- 将 Pool default/per-Volume protection 扩展到跨 Node 故障域，并按 current protection 报告实际故障保证。
- 实现 generation、幂等 EnsureReplica、删除 quarantine 和 relocation。

当前 control metadata 只提交固定 3/2/1 `PROVISIONING` intent；该阶段完成前不把 schema 描述为已接线数据面。

## Milestone 6：Tier 3 Replica 数据路径

- 创建内部 NVMf Replica subsystem、namespace、listener 和 initiator session。
- 定义 vendor-specific `PREPARE`/`COMMIT` commands 与 target-owned metadata。
- 实现 per-Volume journal、sequence、checksum、Replica position 和两阶段 commit certificate。
- 验证 NVMf/RDMA、qpair 中断、每个崩溃窗口和 2/3 持久成功语义。

完成标准：对已达到默认 3/2 current protection 的 Volume，任一单 Replica 故障后，所有已确认写入仍可从 recovery quorum 证明并恢复。较低 protection override 只获得其当前策略可证明的保证。

## Milestone 7：Tier 3 Fencing、Failover 与 Republish

- 实现 lease grant/renew/revoke、Volume write epoch 和 Replica `max_accepted_epoch`。
- 固定 quiesce、disconnect、drain、flush、persist epoch、reopen barrier。
- 合并 certified histories，恢复连续 committed prefix，再激活新 primary。
- 将 VM-facing publication authority 和独立 access generation 纳入 Raft；DataService 持久化最高 installed generation。
- 可达旧 target quiesce/drain session并撤销 ACL/credential；失联 target 依靠 primary lease 到期和 Replica epoch fencing 阻止旧路径提交。
- 在 Zettide DataService 激活新 publication generation；qtr 在调用方指定的 host 以同一 Volume/consumer identity reconcile 新 session 和 libvirt attachment。

完成标准：pause old primary、promote、resume old primary、storage node loss 和跨 qtr host republish E2E 同时证明不会出现两个可写 primary 或两个有效 exclusive publication generation。VM host 选择和自动 VM restart 不属于此标准。

## Milestone 8：自动 Repair 与生产准入

- 实现增量/全量 rebuild、scrub、限速、进度上报和 Replica relocation。
- 增加 control/DataService 双向认证、iSCSI per-host authentication 和 NVMf access control。
- 建立凭据与证书轮换、滚动升级、回滚、格式兼容和灾难恢复流程。
- 通过断电、网络分区、介质损坏、旧 host 恢复、长稳和资源耗尽测试。

## 路线图约束

- 不因存在 format、schema 或局部 library 跳过产品生命周期和 E2E 接线。
- 不把 Pool Member 数量描述为 Volume 已达成副本数。
- 不在受管 iSCSI target 和 qtr reconciliation 完成前宣称 Tier 2。
- 不在 commit evidence 和 fencing 完成前采用 2/3 成功或自动 storage failover 语义。
- 不把 storage republish 描述为 VM 调度或自动 VM failover。
- 不在双向认证完成前放宽可信隔离网络要求。

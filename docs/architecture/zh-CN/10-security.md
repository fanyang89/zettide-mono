# 安全边界

> 状态：当前约束 + 目标强化方向

## 初始模型

首版运行在可信、隔离、由运维控制的存储网络：

- 控制 RPC、Raft transport 和 NVMf 不暴露到公网或不可信租户网络。
- iSCSI publication 只允许受管 qtr host 从隔离 VM storage 网络访问。
- 防火墙/VLAN/VRF 只允许受管 Node 和 control voters 访问内部端口。
- 主机、内核、SPDK 进程和本地介质属于可信计算基。
- 节点加入通过受控 bootstrap，不因网络可达自动加入。

这是当前限制，不是长期零信任目标。

## grpc-lite 边界

grpc-lite 支持明文 HTTP/2 和可选 TLS 1.2+、服务端证书、客户端显式 CA、hostname verification 和 ALPN `h2`。

当前不支持：

- mTLS 和客户端证书验证。
- 内建身份、角色和授权策略。
- 系统 CA 自动发现。
- xDS、ALTS 或云身份凭据。

因此可选 TLS 可以提供链路加密和服务端认证，但不能证明调用方是合法 Node。`cluster_id`、`node_id` 和 metadata 用于协议/配置校验，不是认证凭据。当前 `raft-zig` grpc-lite transport 是明文可信网络 transport。

## 威胁边界

初始设计处理：

- 非预期主机访问内部端口。
- 错误节点连接错误 cluster。
- 旧 primary 恢复后继续尝试写入。
- Member/Replica 部分写、损坏和旧 generation。
- 无界队列和资源耗尽。

初始设计不抵御：

- 获得 Node root 权限的攻击者。
- 能任意注入和修改隔离网络流量的攻击者。
- 恶意控制面多数派或恶意设备固件。
- 内存抓取和 DMA 攻击。

## 身份域

以下身份必须分离：

- Control voter identity。
- Data Node identity。
- 管理客户端 identity。
- NVMf primary/Replica session identity。
- 应用/租户 identity。

Stable ID 不依赖 IP。重新安装节点不能无条件复用旧 Node ID；必须同时持有对应持久身份并通过运维授权。

## 数据写安全

网络隔离不能解决 stale primary。目标数据面同时使用：

- 有期限 lease。
- 单调 Volume write epoch。
- Replica 持久化 `max_accepted_epoch`。
- Epoch-bound NVMf session access。
- 2/3 durable commit evidence。

撤销路由、关闭 listener 或断开 qpair 都是辅助措施，不能替代 Replica 的持久 epoch enforcement。

首版 trusted-network 模型只把 epoch-bound session 作为非恶意节点之间的崩溃/分区安全机制。Host NQN 是 initiator 提供的字符串，不能单独证明身份。若 session identity 成为对抗恶意节点的安全边界，授权必须绑定 DH-HMAC-CHAP 或等价不可伪造、可轮换的 epoch credential，并定义分发和撤销顺序。

## iSCSI 与 qtr 边界

Tier 2 首版 iSCSI 运行在可信隔离网络，并以 portal ACL、initiator 限制和受管 host 配置缩小暴露面。这些措施不等于强身份认证。进入生产准入前需要冻结 CHAP 或等价认证、凭据轮换、每 publication 授权和撤销顺序。

qtr 不把 CHAP secret、可重放 publication credential 或原始设备路径作为 VM 的长期身份。秘密进入受限 host credential store，不进入 VM YAML、普通日志或 Zettide Raft state。Detach/republish 撤销旧 host access 后才向新 host 发放凭据。

## 持久化完整性

当前已有 A/B headers、CRC/摘要、control history、WAL checksum 和故障冻结。这些用于发现损坏，不提供数据机密性或节点真实性。

当前 Volume 格式不承诺静态数据加密。架构书不把 checksum 描述为加密或认证。

## 密钥与日志

未来启用 TLS/mTLS 时：

- 私钥不进入仓库、Raft 状态机或日志。
- Node identity 绑定稳定 Node ID，而不是地址。
- 证书轮换不要求全量停机。
- 加载失败 fail closed，不静默回退明文。
- Control 和 NVMf 凭据使用不同用途与权限。

日志不得包含私钥、token、可重放 lease 凭据或原始块数据。可以记录 resource ID、revision、epoch、状态转换和错误码。

## 放宽可信网络前提

在以下能力完成前不得宣称适用于不可信网络：

- Control/DataService 双向认证。
- 管理、成员变更和恢复操作授权。
- NVMf initiator/session 认证和隔离。
- iSCSI initiator/publication 认证、每 host 授权和凭据轮换。
- 证书签发、轮换、撤销和应急恢复。
- Lease/epoch fencing 的网络分区验证。
- 独立安全审查。

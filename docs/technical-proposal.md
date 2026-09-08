# Clash HarmonyOS NEXT 原生客户端技术方案（评审稿）

> 状态：Approved for M0
> 目标：在开始完整开发前，验证 HarmonyOS NEXT 原生 VPN 数据通路及 Mihomo 内核移植是否可行。
> 结论先行：产品层使用 ArkTS/ArkUI，数据面复用并移植 Mihomo，使用 Native C++ 适配 HarmonyOS；不让 TUN 数据包经过 ArkTS。

## 1. 项目目标

开发一款完全基于 HarmonyOS NEXT 的开源原生网络代理客户端，最低支持 HarmonyOS 6.0（API 20），覆盖手机与鸿蒙 PC/2-in-1，并提供符合鸿蒙交互习惯的稳定体验，尽可能兼容 Mihomo/Clash 生态。

首个公开测试版本需要满足：

- 原生 HAP，不依赖 Android 兼容层、Root 或外部守护进程。
- 使用 HarmonyOS `VpnExtensionAbility` 建立系统 VPN。
- 支持导入本地 Clash YAML 和订阅 URL。
- 支持规则、全局、直连三种常用模式。
- 支持策略组切换、延迟测试、运行日志和流量统计。
- TCP、UDP、DNS、IPv4 和 IPv6 在目标设备上稳定工作。
- 在平台能力允许的范围内复用 Mihomo 的配置、规则和协议行为。
- 网络切换、锁屏、休眠和应用界面退出后，隧道状态可预测且能够恢复。

本项目中的“兼容 Clash”特指兼容选定版本的 Mihomo，而不是同时兼容所有历史 Clash 分支。

## 2. 非目标与平台差异

第一版不承诺以下能力：

- 与某个桌面 Clash 客户端界面完全一致。
- Root、iptables、TProxy、eBPF 或修改系统路由表。
- 平台无法可靠提供时的 `PROCESS-NAME`、`PROCESS-PATH` 等进程匹配规则。
- 在应用外动态下载并执行未随 HAP 签名发布的内核二进制。
- 对 Mihomo alpha 版本每次提交进行即时同步。
- 第一版不覆盖平板、穿戴、TV、车机等其他鸿蒙设备形态；手机与 PC/2-in-1 属于首发范围。

遇到平台不支持的配置项时，应用必须明确提示，而不是静默忽略。兼容状态分为：完全支持、平台替代实现、不支持并报错。

## 3. 技术决策

### 3.1 推荐方案

采用“原生产品层 + 隔离内核进程”的混合架构：

```text
┌─────────────────────────────────────────────┐
│ ArkUI / ArkTS                               │
│ 页面、状态管理、订阅、配置编辑、系统交互       │
└───────────────────┬─────────────────────────┘
                    │ 粗粒度控制 API
┌───────────────────▼─────────────────────────┐
│ VPN Extension / Core Supervisor             │
│ VPN 生命周期、权限、网络变化、内核拉起与恢复    │
└───────────────────┬─────────────────────────┘
                    │ TUN FD + IPC
┌───────────────────▼─────────────────────────┐
│ Native Core Process                         │
│ C++ 启动器 + HarmonyOS 适配层 + Mihomo Core  │
└───────────────────┬─────────────────────────┘
                    │ 系统 Socket
                  Internet
```

ArkTS 与 Native 层之间只传递命令、状态、统计和经过限流的日志。TUN 数据包、连接数据和 DNS 数据不跨 Node-API 边界。

### 3.2 为什么不纯 ArkTS 重写内核

纯 ArkTS 可以实现基础代理，但完整实现 Mihomo 涉及 TCP/UDP 会话、DNS、Fake-IP、规则引擎、TLS 指纹、QUIC、WireGuard 及大量代理协议。重新实现会显著扩大安全、兼容性和性能风险。

HarmonyOS 官方原生开发模型允许 ArkTS 调用 C/C++ 动态库，并提供 Native 子进程和 FD 传递能力。这更适合高频 I/O 与长时间运行的数据面。

### 3.3 为什么内核需要隔离进程

- 内核异常不会直接拖垮 UI。
- 可以独立监控、限流和重启。
- 避免 Go 运行时与 ArkTS 运行时长期共享主进程造成排障困难。
- TUN FD 可以在 Native 层直接交付，避免逐包跨语言调用。

若早期设备验证发现独立进程受到 VPN Extension 生命周期限制，可临时退化为同进程 Native 线程，但对外接口保持不变。

## 4. 内核移植方案

### 4.1 现状

Mihomo 使用 Go。官方 Go 工具链目前没有 `GOOS=ohos`，Mihomo 官方也没有 HarmonyOS 构建产物。因此不能把 Android ARM64 或 Linux ARM64 可执行文件直接当作正式方案。

### 4.2 移植策略

建立单独的 `mihomo-ohos` 构建层，尽量减少对上游代码的侵入：

1. 固定一个稳定版 Mihomo 作为兼容基线。
2. 裁剪 CLI、系统服务、桌面特有逻辑和不适用的自动路由功能。
3. 将核心入口封装为少量 C ABI，优先尝试 `c-shared` 形式。
4. 使用 HarmonyOS NDK/Clang 完成 cgo 依赖构建。
5. 为系统差异增加独立的 OHOS platform adapter，不在业务模块散布条件编译。
6. 通过 C++ Supervisor 创建内核实例并传入配置目录、缓存目录和 TUN FD。
7. 上游升级时通过补丁集和自动化兼容测试重新构建。

建议的核心接口：

```c
int core_create(const CoreOptions* options, CoreHandle* handle);
int core_start(CoreHandle handle, int tun_fd);
int core_reload(CoreHandle handle, const char* config_path);
int core_get_status(CoreHandle handle, CoreStatus* status);
int core_stop(CoreHandle handle, int timeout_ms);
void core_destroy(CoreHandle handle);
```

配置、日志和状态不要通过高频函数轮询传递；使用本地 IPC 或有界消息队列。敏感信息不得写入普通日志。

### 4.3 技术验证闸门

在开发完整 UI 前完成 2–4 周验证。必须同时通过：

- 在至少一台 HarmonyOS NEXT 真机加载并启动内核。
- 从 VPN API 获取 TUN FD，并由内核完成双向读写。
- TCP：连续访问 HTTPS 站点和大文件下载成功。
- UDP：DNS 与至少一种普通 UDP 流量成功。
- 代理：DIRECT、REJECT、HTTP/SOCKS5 出站工作正常。
- 连续运行 8 小时无崩溃、死锁和持续内存增长。
- Wi-Fi 与蜂窝网络切换后在 5 秒内恢复基本连通。
- 内核退出后 Supervisor 能识别状态，且不会进入无限重启循环。

任何一项失败都要形成原因报告。以下情况触发停止或重新选型：

- 必须长期维护大面积 Go runtime fork 才能运行。
- 核心依赖的系统调用无法安全映射到 HarmonyOS 应用沙箱。
- VPN Extension 无法可靠把数据通路交给 Native 层。
- 性能连续低于同设备网络基线的 50%，且无法定位到可优化环节。

验证失败后的备选路径不是立刻重写全部 Mihomo，而是先评估范围更小的 C++/Rust 原生核心，只实现产品首发所需协议。

## 5. 模块划分

建议目录结构：

```text
clash-hos/
├── entry/                    # ArkUI 页面与应用入口
├── features/
│   ├── profiles/             # 配置、订阅、导入导出
│   ├── proxies/              # 策略组与节点
│   ├── connections/          # 连接与流量展示
│   └── settings/             # 应用设置
├── vpn_extension/            # VpnExtensionAbility 与生命周期
├── native/
│   ├── bridge/               # Node-API，粗粒度产品接口
│   ├── supervisor/           # 内核进程、IPC、恢复与诊断
│   └── platform/ohos/        # FD、Socket、网络变化、文件系统适配
├── core/
│   ├── mihomo/               # 固定上游版本或 submodule
│   └── patches/ohos/         # 可审计的最小补丁集
├── tests/
│   ├── compatibility/        # 与基准 Mihomo 的差分测试
│   ├── integration/          # VPN/TUN/网络测试
│   └── fixtures/             # 脱敏配置语料
├── tools/                    # 构建、打包、符号与诊断脚本
└── docs/
```

模块之间不得直接共享可变全局状态。UI 只依赖 `CoreService` 抽象，不直接依赖 Mihomo 类型，便于以后替换内核。

## 6. 产品与数据流程

### 6.1 启动流程

1. 用户选择配置并点击连接。
2. ArkTS 校验配置和 VPN 授权状态。
3. VPN Extension 创建虚拟接口，设置地址、路由、DNS 和 MTU。
4. Supervisor 启动 Native Core，传入 TUN FD 和只读运行快照。
5. 内核报告 Ready 后，UI 才显示“已连接”。
6. 若启动超时，关闭 TUN、停止内核并返回可诊断错误。

### 6.2 网络切换

1. 监听默认网络变化。
2. 阻止内核出口重新进入自身 VPN，避免流量回环。
3. 更新底层网络绑定并失效旧连接。
4. 保留用户选择的策略组和配置状态。
5. 超时后进行一次受控重启，禁止无限重启。

### 6.3 配置处理

- 原始订阅与活动运行配置分离。
- 每次更新先在临时区域解析、校验和编译，成功后原子切换。
- 更新失败继续使用最后一次有效配置。
- Token、认证信息和订阅 URL 使用系统安全存储；普通设置和非敏感缓存使用应用沙箱。
- 展示配置错误的字段路径和原因，不只返回“解析失败”。

## 7. 兼容性范围

### 7.1 首个 Beta 必须支持

- Mihomo 稳定版常用 YAML 字段。
- 本地配置、远程订阅、Proxy Provider、Rule Provider。
- `rule`、`global`、`direct` 模式。
- 常用规则：DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、IP-CIDR6、GEOIP、GEOSITE、MATCH。
- select、url-test、fallback、load-balance 等常用策略组，以所选 Mihomo 基线为准。
- TCP/UDP、IPv4/IPv6、DNS、Fake-IP。
- Mihomo 基线内可在 HarmonyOS 正常运行的主流出站协议。
- 核心 REST API 的产品内等价能力；是否对局域网开放控制端口默认关闭。

### 7.2 需要平台验证

- 应用/进程规则。
- 系统证书与用户证书集成。
- QUIC、WireGuard、TUN stack 的具体实现组合。
- IPv6-only、NAT64、私有 DNS/DoH 共同存在时的行为。
- 热点共享、VPN 冲突、双卡和弱网环境。
- 长时间后台运行与系统省电策略。

## 8. 性能与体验指标

在确定两台参考设备后锁定最终指标。评审阶段采用以下暂定门槛：

| 指标 | 目标 |
|---|---|
| 冷启动到隧道 Ready | 不超过 3 秒，不含首次下载规则数据 |
| 热启动到隧道 Ready | 不超过 1.5 秒 |
| 网络切换恢复 | 常规场景不超过 3 秒，最迟 5 秒 |
| TCP 吞吐 | 达到同设备同网络直连基线的 75% 以上 |
| 稳态 CPU | 100 Mbps TCP 场景平均不超过单个大核的 20% |
| 稳态内存 | 常用配置与规则集下 PSS 不超过 180 MB |
| 空闲耗电 | 8 小时锁屏测试无异常唤醒风暴，目标值由真机基线确定 |
| 稳定性 | 24 小时压力测试无崩溃、无不可恢复断网 |
| UI 响应 | 日志和连接列表高负载时仍保持可交互 |

指标必须在固定配置、固定节点、固定网络和相同测试时间窗内对比。若规则数据本身过大，需要同时报告 Core、规则数据和 UI 的内存占用。

## 9. 测试策略

### 9.1 差分兼容测试

在 Linux 上运行同版本官方 Mihomo 作为基准，对同一批脱敏配置比较：

- 配置是否接受以及错误位置。
- 规则匹配结果。
- 策略组选择和健康检查状态。
- DNS 响应模式与 Fake-IP 映射。
- REST API 的关键字段。

平台差异必须进入白名单并附原因，不允许简单跳过失败用例。

### 9.2 真机测试

- Wi-Fi、蜂窝、双卡、IPv6-only、弱网和网络切换。
- 锁屏、充电、低电量、省电模式和系统回收。
- 大文件、短连接、视频、游戏 UDP、DNS 压力。
- VPN 冲突、配置更新失败、订阅超时、磁盘空间不足。
- 内核崩溃、异常退出和应用升级后的恢复。

### 9.3 安全测试

- 配置解析与订阅内容模糊测试。
- Web 控制接口默认只绑定本机并使用随机密钥。
- 防止路径穿越、任意文件读取和规则包解压炸弹。
- 日志脱敏，不记录完整订阅 URL、密码、Token 或用户访问内容。
- 第三方依赖生成 SBOM，并持续跟踪高危漏洞。

## 10. 里程碑与工期

以下估算以 2–3 名熟悉 HarmonyOS、C++ 和网络协议的开发者为前提。项目最低兼容 HarmonyOS 6.0.0（API 20），当前使用 HarmonyOS 6.1.1（API 24）编译和测试。

### M0：可行性验证，2–4 周

- 原生工程骨架。
- VPN 授权和 TUN 建立。
- Native 子进程与 FD 传递。
- Mihomo 最小移植或明确失败报告。
- TCP/UDP/DNS 真机数据通路。
- 性能、内存和 8 小时稳定性报告。

交付决策：Go/Mihomo 路径继续、调整或终止。

### M1：内核与系统基础，3–5 周

- CoreService、Supervisor、IPC 和错误模型。
- 网络切换、受控重启、配置原子更新。
- 配置存储和敏感信息保护。
- 基础差分测试与构建流水线。

### M2：产品 MVP，4–6 周

- 首页、配置、订阅、策略组、日志和设置。
- 常用模式、规则、DNS 和主流协议验证。
- 启停、导入、更新、失败回退完整闭环。
- 关键体验与无障碍检查。

### M3：Beta 与发布准备，4–6 周

- 24 小时压力测试和设备矩阵测试。
- 性能、耗电、弱网及生命周期优化。
- 崩溃诊断、隐私说明、许可证材料和 SBOM。
- 灰度版本与问题反馈通道。

如果 M0 成功，首个可测试 Beta 的合理周期约为 13–21 周。完整追平 Mihomo 全量特性不纳入这个工期，而是持续兼容工作。

## 11. 主要风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| Go 无官方 OHOS target | 无法稳定构建内核 | M0 优先验证；保持补丁最小；设明确退出条件 |
| VPN/后台生命周期限制 | 隧道被回收或断网 | 以 Extension 为状态源；真机长稳测试；受控恢复 |
| 出口流量回环 | CPU 飙升、完全断网 | 平台网络绑定/保护机制；启动阶段强制自检 |
| Mihomo 更新破坏移植 | 维护成本上升 | 固定稳定版；季度升级；差分测试和补丁审计 |
| 大规则集内存过高 | 杀后台、耗电 | 延迟加载、紧凑数据格式、规则集预算与告警 |
| GPL-3.0 义务 | 影响产品发布模式 | 开发前确定开源/商业策略并进行法律审查 |
| 应用市场政策 | 无法公开分发 | M0 同期确认类目、权限和审核材料，不到最后才验证 |

## 12. 许可证与发布决策

Mihomo 当前采用 GPL-3.0。若应用与移植后的内核作为组合产品分发，需要按实际链接、通信、修改和打包方式评估源代码提供等义务。本方案不把“独立进程”视为自动规避 GPL 的手段。

在 M0 结束前必须确定：

1. 产品是否整体开源。
2. 是否接受公开 HarmonyOS 移植补丁和构建脚本。
3. 若闭源，是否取得其他授权，或改用 clean-room 内核。
4. 发布渠道是内部、侧载测试还是应用市场。

## 13. 已确认与待确认的产品决策

- 已确认：首发支持手机与鸿蒙 PC/2-in-1。
- 已确认：最低 HarmonyOS 6.0.0（API 20），当前编译目标为 6.1.1（API 24）。
- 已确认：产品开源。
- 待确认：手机与 PC 各至少一台参考设备。
- 首发必须支持的协议清单。
- 是否要求完全兼容现有订阅，还是允许产品侧规范化转换。
- 是否计划应用市场公开上架。
- 是否允许内置本地 Web 控制接口；建议默认关闭外部访问。

这些决策不会阻碍 M0 技术验证，但会影响 M1 之后的架构和发布方式。

## 14. 建议的启动顺序

批准本方案后，不立即开发完整页面，按以下顺序开工：

1. 创建 HarmonyOS Native C++ 工程骨架。
2. 跑通 VPN 授权和 TUN FD 获取。
3. 跑通 Native 子进程、IPC 和 FD 生命周期。
4. 建立固定版本 Mihomo fork/patch 构建实验。
5. 完成 DIRECT、HTTP/SOCKS、TCP、UDP、DNS 数据通路。
6. 提交 M0 报告和是否继续复用 Mihomo 的最终决策。
7. 再进入产品 UI、订阅和完整兼容开发。

## 15. 参考资料

- HarmonyOS VPN 管理：<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-net-vpn>
- HarmonyOS VPN Extension：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-net-vpnextension>
- HarmonyOS Node-API：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/napi-introduction-V5>
- HarmonyOS Native 子进程：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-child-process-development-guideline>
- Go 支持平台：<https://go.dev/doc/install/source>
- Mihomo Releases：<https://github.com/MetaCubeX/mihomo/releases>
- Mihomo GPL-3.0：<https://raw.githubusercontent.com/MetaCubeX/mihomo/Meta/LICENSE>

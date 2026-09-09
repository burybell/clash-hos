# R4 数据通路可靠性清单

R4 的目标是把现有功能原型改造成“连接状态有真实网络结果支撑、异常可以诊断并恢复”的客户端。仅成功创建 VPN 接口不能代表互联网已经可用。

## 完成标准

- [ ] HarmonyOS 手机实体机可以通过所选节点完成 DNS 解析以及 TCP、UDP 通信。
- [ ] 界面能区分 VPN 隧道创建、内核就绪、节点选择和代理出口验证。
- [ ] 内核启动失败时立即关闭 VPN，并恢复设备普通网络。
- [ ] Wi-Fi 与蜂窝网络切换后能够恢复，且不会无限重启。
- [ ] 手机完成 8 小时混合流量测试，无崩溃、泄漏或静默断网。
- [ ] HarmonyOS PC/2-in-1 完成以太网/Wi-Fi 切换和数据通路测试。

## R4.1 启动和出口诊断

- [x] 按内核分别检查就绪状态，xray-rust 不再等待 ClashRS 控制端口。
- [x] 首次系统 VPN 授权最多等待 15 秒。
- [x] 启动后通过两个独立 HTTPS 地址验证所选节点。
- [x] 分别展示“出口已验证”和“连接已建立但出口异常”。
- [x] 对 DNS、TCP、TLS、传输和超时错误生成脱敏诊断原因。
- [x] 增加能证明流量确实进入并离开 TUN 的设备测试。

## R4.2 协议与数据包矩阵

- [x] DIRECT IPv4 TCP 和 UDP。
- [ ] ClashRS Shadowsocks TCP 和 UDP。
- [ ] ClashRS Trojan TCP 和 UDP（配置支持时）。
- [x] ClashRS AnyTLS TCP。
- [x] xray-rust VLESS REALITY Vision TCP。
- [x] Fake-IP DNS UDP 与 TCP 回退。
- [ ] 两套内核的出口保护和防回环验证。

## R4.3 恢复与稳定性

- [ ] 手机 Wi-Fi/蜂窝网络切换后的受控恢复。
- [ ] PC/2-in-1 以太网/Wi-Fi 切换后的受控恢复。
- [ ] 锁屏、后台和进程重建测试。
- [ ] 配置原子替换以及重启失败回滚。
- [ ] 有次数上限的崩溃恢复，并展示最终失败状态。
- [ ] 先完成手机 8 小时测试，再进入 24 小时 Beta 门槛。

## 测试证据

每次设备测试记录系统/API 版本、架构、配置协议（不得包含凭据）、所选内核、网络类型、起止时间、传输字节、失败原因和恢复结果。测试产物中不得保存订阅地址、Token、服务器凭据或流量内容。

### 2026-09-09 手机冒烟测试

- 设备：SGT-AL00、ARM64、OpenHarmony 7.0.0.105 / API 26。
- 内核/协议：xray-rust、VLESS REALITY Vision；服务端和凭据已隐藏。
- 网络：Wi-Fi，蜂窝网络同时可用。
- 结果：所选节点的 HTTPS 探测返回 HTTP 204，系统浏览器通过 VPN 成功显示 `https://www.google.com`。
- TUN 证据：诊断快照记录 71 个入站包和 60 个出站包，通用丢包、TCP/UDP 打开错误均为 0。
- 预期兼容事件：Vision 拒绝了 2 次 UDP/443 请求，浏览器随后成功回退到 TCP。

### 2026-09-09 ClashRS 数据通路测试

- 设备：SGT-AL00、ARM64、OpenHarmony 7.0.0.105 / API 26。
- 内核/配置：ClashRS；脱敏后的配置协议清单包含 AnyTLS 和 VLESS 节点。
- 结果：所选节点通过双 HTTPS 出口检测，系统浏览器通过 VPN 成功打开 `https://www.google.com`。
- DNS 证据：VPN 连接期间，独立的 DNS UDP 与 TCP 查询均收到事务号匹配的有效响应。
- DIRECT 证据：切换 ClashRS 到直连模式后，独立的 IPv4 UDP 与 TCP DNS 查询均收到有效响应。
- 隐私：未记录服务端、订阅元数据、凭据或流量内容。

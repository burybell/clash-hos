# Clash HOS

简体中文 | [English](README.md)

Clash HOS 是一款面向 HarmonyOS NEXT 的开源原生网络客户端，兼容 Clash 配置生态，最低支持 HarmonyOS 6.0，同时面向手机和鸿蒙 PC/2-in-1 设备开发。

> [!WARNING]
> Clash HOS 仍在积极开发，目前不是正式生产版本。用于日常连接前，请备份重要配置并阅读下方已知限制。

## 主要功能

- ArkUI/ArkTS 原生界面，支持手机与 PC 响应式布局。
- 原生 `VpnExtensionAbility`，不依赖 Android 兼容层，也不需要 Root。
- 支持 Clash YAML 订阅链接一键导入和二维码扫描。
- 支持多订阅配置、独立更新和当前配置切换。
- 支持规则、全局、直连模式。
- 支持国家/地区筛选、真实节点测速、隐藏不可用节点和延迟排序。
- 支持在偏好国家中自动选择延迟最低的可用节点。
- 展示连接时长、活动连接数、实时上传和下载速率。
- 支持系统浅色/深色模式与鸿蒙风格导航。
- 提供 ARM64 与 x86_64 原生数据面。

## 设备支持

入口模块声明了 HarmonyOS `default` 和 `2in1` 设备类型。最低兼容版本为 HarmonyOS 6.0.0 / API 20，目标 SDK 为 HarmonyOS 6.1.1 / API 24。

| 设备类型 | 架构 | 当前状态 |
|---|---|---|
| HarmonyOS 手机 | ARM64 | 已持续在实体设备上测试 |
| HarmonyOS PC / 2-in-1 | ARM64 或 x86_64 | 已具备构建目标和宽屏布局，更多实体硬件测试仍在进行 |

## 技术架构

```text
ArkUI / ArkTS
  界面、订阅、设置、运行状态编排
        │
        ▼
VpnExtensionAbility
  VPN 授权、路由/DNS、TUN 生命周期
        │
        ▼
C++ Node-API 桥接层
  粗粒度原生生命周期接口
        │
        ├── ClashRS：较广泛的 Clash YAML 兼容能力
        └── xray-rust：VLESS + REALITY + Vision 路径
```

高频数据包不会穿过 ArkTS 边界。VPN 扩展把基于文件描述符的 TUN 接口直接交给原生内核，ArkTS 仅处理配置、生命周期、测速结果和流量统计。

上游版本固定在 [`core/clash-rs/upstream.json`](core/clash-rs/upstream.json)、[`core/xray-rust/upstream.json`](core/xray-rust/upstream.json) 和 [`core/mihomo/upstream.json`](core/mihomo/upstream.json)。HarmonyOS 修改以可审查的补丁集维护，不提交完整上游源码。

## 当前兼容范围

包含 AnyTLS 等 Clash 协议的订阅使用 ClashRS。仅包含 VLESS REALITY Vision 的配置可以转换到 xray-rust，以保留 TLS 指纹和 REALITY 参数。

目前支持：

- 远程 Clash YAML 订阅。
- 多配置保存、切换和单独更新。
- 常用代理组及手动节点选择。
- 通过真实原生内核进行节点测速。
- 按偏好国家自动选择最低延迟节点。
- 规则、全局、直连模式。
- xray-rust 转换路径中的常用域名/IP 规则。
- IPv4 TUN 路由与 DNS 配置。

已知限制：

- VPN 数据通路目前仅支持 IPv4。
- xray-rust 转换路径尚未支持所有 Clash 规则和协议组合。
- 网络切换恢复、长时间稳定性、IPv6 和安全凭据存储仍需完善。
- 已提供 PC/2-in-1 构建支持，但实体设备测试目前仍以手机为主。
- 订阅链接和节点凭据目前保存在应用沙箱中，后续计划接入硬件级安全存储。

设计背景参见 [`docs/technical-proposal.md`](docs/technical-proposal.md)，早期里程碑参见 [`docs/m0-checklist.md`](docs/m0-checklist.md)，当前数据通路可靠性工作参见 [`docs/r4-checklist.zh-CN.md`](docs/r4-checklist.zh-CN.md)。

## 开发环境

- macOS 开发主机。
- DevEco Studio 6.1.1 Release 或更高版本。
- HarmonyOS SDK 6.1.1 / API 24，包含 Native SDK。
- 包含 `cargo` 的 Rust 工具链。
- Git、CMake、Ninja 和 Node.js；大部分非 Rust 工具由 DevEco 自带。
- HarmonyOS 6.0+ 手机或 PC/2-in-1 实体设备/模拟器。

脚本默认 DevEco Studio 位于 `/Applications/DevEco-Studio.app`。Native SDK 位于其他位置时，请设置 `OHOS_SDK_NATIVE`。

## 从源码构建

```sh
git clone git@github.com:burybell/clash-hos.git
cd clash-hos
cp build-profile.example.json5 build-profile.json5
./tools/build-hap.sh
```

首次构建会把固定版本的上游源码克隆到 `.build/`，应用仓库补丁，编译 ARM64 和 x86_64 OHOS 动态库并打包 HAP。后续构建会复用本地 Cargo 产物。

未配置签名时，预期产物为：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

实体设备安装需要在 DevEco Studio 中配置本地自动签名。签名产物通常位于 `entry/build/default/outputs/default/entry-default-signed.hap`。

`build-profile.json5` 已被有意忽略，因为 DevEco 签名配置会包含本地证书路径和密码，绝对不要提交该文件。

## 安装到设备

通过 HDC 连接设备后执行：

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc install -r \
  entry/build/default/outputs/default/entry-default-signed.hap
```

首次连接时 HarmonyOS 会要求设备所有者授权 VPN 扩展。签名和 VPN 授权必须由设备所有者完成。

## 开发检查

```sh
node tools/check-project.mjs
cmake -S tests/native -B build/native-tests
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure
```

原生动态库已存在时，可以只构建应用：

```sh
./tools/hvigorw assembleHap --mode module \
  -p product=default -p module=entry@default -p buildMode=debug --no-daemon
```

## 隐私与安全

Clash HOS 不提供、不销售、也不推荐任何代理服务。配置由用户自行提供和控制。订阅可能包含敏感链接、令牌、服务器地址和凭据，请勿在 Issue、截图、日志、测试或 Pull Request 中提交真实订阅。

Clash 本地控制接口仅在运行时绑定到回环地址，不会主动暴露到局域网。安全漏洞请按照 [`SECURITY.md`](SECURITY.md) 私下报告。

## 参与贡献

欢迎提交 Issue 和 Pull Request。贡献前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。请固定上游版本、保证补丁可审计、保持数据面原生化，并同时兼顾浅色/深色与手机/宽屏布局。

## 法律声明

本项目是用于合法隐私保护、开发和互操作用途的通用网络客户端。用户应自行遵守适用法律、服务条款和网络策略。维护者不提供代理服务，也不对网络可用性或特定用途适用性作出保证。

## 开源许可证

Clash HOS 应用代码以 [Apache License 2.0](LICENSE) 发布。第三方组件保留各自许可证：ClashRS 使用 Apache-2.0，xray-rust 使用 MPL-2.0。准确版本与许可证哈希记录在对应的 `upstream.json` 文件中。

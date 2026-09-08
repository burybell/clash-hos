# Clash HOS

[简体中文](README.zh-CN.md) | English

Clash HOS is an open-source, Clash-compatible network client built natively for HarmonyOS NEXT. It targets HarmonyOS 6.0 and later and is designed for phones and HarmonyOS PCs/2-in-1 devices.

> [!WARNING]
> Clash HOS is under active development and is not yet a production release. Back up important profiles and review the limitations below before daily use.

## Highlights

- Native ArkUI/ArkTS interface with responsive phone and PC layouts.
- Native `VpnExtensionAbility`; no Android compatibility layer or root access.
- Clash YAML subscriptions with one-tap URL import and QR-code scanning.
- Multiple profiles with independent refresh and active-profile selection.
- Rule, global, and direct routing modes.
- Country filters, real node latency tests, unavailable-node hiding, and delay sorting.
- Optional lowest-latency selection within preferred countries.
- Connection duration, active connections, upload rate, and download rate.
- System light/dark appearance and HarmonyOS-style navigation.
- Native ARM64 and x86_64 data planes.

## Device support

The entry module declares HarmonyOS `default` and `2in1` device types. The minimum compatible SDK is HarmonyOS 6.0.0 / API 20; the target SDK is HarmonyOS 6.1.1 / API 24.

| Device family | Architecture | Status |
|---|---|---|
| HarmonyOS phone | ARM64 | Actively tested on physical hardware |
| HarmonyOS PC / 2-in-1 | ARM64 or x86_64 | Build target and responsive layout available; broader hardware testing is ongoing |

## Architecture

```text
ArkUI / ArkTS
  UI, subscriptions, preferences, runtime orchestration
        │
        ▼
VpnExtensionAbility
  VPN authorization, route/DNS setup, TUN lifecycle
        │
        ▼
C++ Node-API bridge
  Coarse-grained native lifecycle boundary
        │
        ├── ClashRS: broad Clash YAML compatibility
        └── xray-rust: VLESS + REALITY + Vision path
```

Packet processing never crosses the ArkTS boundary. The VPN extension passes an fd-backed TUN interface to the native core; ArkTS exchanges only configuration, lifecycle state, latency results, and traffic statistics.

Upstream revisions are pinned in [`core/clash-rs/upstream.json`](core/clash-rs/upstream.json), [`core/xray-rust/upstream.json`](core/xray-rust/upstream.json), and [`core/mihomo/upstream.json`](core/mihomo/upstream.json). HarmonyOS changes are maintained as reviewable patch sets instead of vendored upstream repositories.

## Current compatibility

ClashRS handles subscriptions containing supported Clash protocols such as AnyTLS. VLESS REALITY Vision-only profiles can be translated to xray-rust so TLS fingerprints and REALITY parameters are preserved.

Available today:

- Remote Clash YAML subscriptions.
- Multiple profiles, switching, and per-profile refresh.
- Common proxy groups and manual node selection.
- Real latency tests through the native core.
- Automatic best-node selection with country preferences.
- Rule, global, and direct modes.
- Common domain/IP rules in the xray-rust translation path.
- IPv4 TUN routing and DNS configuration.

Known limitations:

- The VPN data path is currently IPv4-only.
- Some Clash rules and protocol combinations are not supported by the xray-rust translation path.
- Network-change recovery, long-duration stability, IPv6, and secure credential storage need more work.
- PC/2-in-1 packaging exists, but physical-device testing currently focuses on phones.
- Subscription URLs and node credentials are stored in the application sandbox; hardware-backed secret storage is planned.

See [`docs/technical-proposal.md`](docs/technical-proposal.md) for design background and [`docs/m0-checklist.md`](docs/m0-checklist.md) for early native-core milestones.

## Requirements

- macOS development host.
- DevEco Studio 6.1.1 Release or newer.
- HarmonyOS SDK 6.1.1 / API 24, including the Native SDK.
- Rust toolchain with `cargo`.
- Git, CMake, Ninja, and Node.js. DevEco bundles most non-Rust tools used by the scripts.
- HarmonyOS 6.0+ phone or PC/2-in-1 device/emulator.

Scripts default to DevEco Studio at `/Applications/DevEco-Studio.app`. Set `OHOS_SDK_NATIVE` if the Native SDK is elsewhere.

## Build from source

```sh
git clone git@github.com:burybell/clash-hos.git
cd clash-hos
cp build-profile.example.json5 build-profile.json5
./tools/build-hap.sh
```

The first build clones pinned upstream sources into `.build/`, applies checked-in patches, builds ARM64 and x86_64 OHOS libraries, and packages the HAP. Later builds reuse local Cargo artifacts.

Without signing, the expected output is:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

Configure DevEco Studio automatic signing locally for physical-device installation. A signed build is normally written to `entry/build/default/outputs/default/entry-default-signed.hap`.

`build-profile.json5` is intentionally ignored because DevEco signing stores local certificate paths and passwords in it. Never commit it.

## Install on a device

After connecting through HDC:

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc install -r \
  entry/build/default/outputs/default/entry-default-signed.hap
```

HarmonyOS asks the device owner to authorize the VPN extension on first connection. Signing and VPN authorization must be completed by the device owner.

## Development checks

```sh
node tools/check-project.mjs
cmake -S tests/native -B build/native-tests
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure
```

When native libraries already exist, build only the application with:

```sh
./tools/hvigorw assembleHap --mode module \
  -p product=default -p module=entry@default -p buildMode=debug --no-daemon
```

## Privacy and security

Clash HOS does not include, sell, or endorse proxy services. Users provide and control their own configurations. Subscriptions may contain sensitive URLs, tokens, addresses, and credentials; never include real subscriptions in issues, screenshots, logs, tests, or pull requests.

The local Clash controller is injected at runtime on loopback only. The application does not intentionally expose it to the LAN. Report vulnerabilities privately as described in [`SECURITY.md`](SECURITY.md).

## Contributing

Issues and pull requests are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md). Keep upstream revisions pinned, patches auditable, packet processing native, and UI changes compatible with light/dark and phone/wide layouts.

## Legal notice

This is a general-purpose networking client for legitimate privacy, development, and interoperability use. Users are responsible for applicable laws, service terms, and network policies. The maintainers provide no proxy service and no warranty of connectivity or fitness for a particular purpose.

## License

Clash HOS application code is licensed under the [Apache License 2.0](LICENSE). Third-party components retain their own licenses: ClashRS is Apache-2.0 and xray-rust is MPL-2.0. Exact revisions and license hashes are recorded in their `upstream.json` files.

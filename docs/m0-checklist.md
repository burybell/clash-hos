# M0 Feasibility Checklist

## Fixed product decisions

- Distribution: open source.
- Minimum OS: HarmonyOS 6.0.0 / API 20.
- Current compile and target SDK: HarmonyOS 6.1.1 / API 24.
- Devices: phone (`default`) and HarmonyOS PC/2-in-1 (`2in1`).
- UI: ArkUI/ArkTS.
- Data plane: ClashRS native Rust/OHOS port behind a Native C++ boundary; Mihomo remains the compatibility reference.

## Work status

- [x] Architecture proposal.
- [x] HarmonyOS project structure.
- [x] Phone and PC device declarations.
- [x] VPN Extension declaration.
- [x] ArkTS `CoreService` abstraction.
- [x] Native C++/Node-API bridge with fail-closed status.
- [x] Initial adaptive-width dashboard shell.
- [x] Locate DevEco Studio 6.1.1 and HarmonyOS API 24 SDK bundled under `/Applications/DevEco-Studio.app`.
- [x] Compile ArkTS, Native C++, resources, and an unsigned HAP with API 24 SDK.
- [x] Package `libclash_core.so` for both ARM64 and x86_64.
- [x] Verify the PC ARM64 emulator image is installed.
- [x] Connect an ARM64 HarmonyOS phone (`SGT-AL00`, OpenHarmony 7.0.0.105 / API 26) over wireless HDC.
- [x] Configure project-specific automatic debug signing without copying another project's credentials.
- [x] Build, install, launch, and visually verify the shell on an ARM64 HarmonyOS phone.
- [x] Import a Clash-compatible HTTPS subscription on-device without persisting or logging the subscription URL.
- [ ] Run on HarmonyOS 6 PC/2-in-1 emulator/device.
- [x] Confirm VPN authorization UI on the physical phone.
- [x] Build a safe TUN handoff path with fail-close startup.
- [x] Decide and document the repository SPDX license (Apache-2.0 for project-owned code).
- [x] Pin Mihomo v1.19.30 / `ac017cdd246ce8bd547653d927e7bf77d7ee73d5` and record source metadata.
- [x] Complete the Go/OHOS `c-shared` feasibility spike; reject the unmodified approach due to musl `initial-exec TLS` incompatibility.
- [x] Build ClashRS FFI for ARM64 and x86_64 OHOS and load/probe the ARM64 library on a physical phone.
- [x] Transfer TUN FD to the native core without copying packet data through ArkTS.
- [ ] Verify DIRECT, HTTP/SOCKS5, TCP, UDP, and DNS paths.
- [ ] Verify socket protection/no-loop behavior.
- [ ] Complete Wi-Fi/cellular switching tests on phone.
- [ ] Complete Ethernet/Wi-Fi switching tests on PC.
- [ ] Complete 8-hour stability run and write the M0 decision report.

## Safety invariants

1. Never create a default-route VPN until the packet-processing core reports ready.
2. Never process TUN packets in the ArkTS UI thread.
3. Never log subscription URLs, credentials, proxy passwords, or traffic payloads.
4. A failed core start must destroy the VPN and restore normal networking.
5. Crash recovery must be bounded; no infinite restart loop.

# R4 Data-Path Reliability Checklist

R4 turns the existing feature-complete prototype into a client whose connected state is backed by an observable, recoverable network path. A VPN interface being created is not sufficient evidence of internet access.

## Exit criteria

- [ ] A physical HarmonyOS phone can resolve DNS and carry TCP and UDP traffic through the selected proxy.
- [ ] The UI distinguishes tunnel creation, core readiness, node selection, and verified proxy egress.
- [ ] A failed core start closes the VPN and restores ordinary networking.
- [ ] Wi-Fi/cellular switching recovers without an unbounded restart loop.
- [ ] A phone completes an 8-hour mixed-traffic run without a crash, leak, or silent black hole.
- [ ] A HarmonyOS PC/2-in-1 completes Ethernet/Wi-Fi switching and core data-path tests.

## R4.1 Startup and egress diagnostics

- [x] Use engine-specific readiness checks; xray-rust must not wait for the ClashRS controller.
- [x] Allow up to 15 seconds for first-time system VPN authorization.
- [x] Verify the selected proxy against two independent HTTPS endpoints after startup.
- [x] Show verified and degraded egress states separately from the VPN tunnel state.
- [x] Record a sanitized diagnostic reason for DNS, TCP, TLS, transport, and timeout failures.
- [x] Add a device test that proves traffic entered and left the TUN interface.

## R4.2 Protocol and packet-path matrix

- [x] DIRECT IPv4 TCP and UDP.
- [ ] ClashRS Shadowsocks TCP and UDP.
- [ ] ClashRS Trojan TCP and UDP where supported by the profile.
- [x] ClashRS AnyTLS TCP.
- [x] xray-rust VLESS REALITY Vision TCP.
- [x] Fake-IP DNS over UDP and TCP fallback.
- [ ] Socket protection and no-loop behavior under both engines.

## R4.3 Recovery and stability

- [ ] Debounced Wi-Fi/cellular recovery on phone.
- [ ] Debounced Ethernet/Wi-Fi recovery on PC/2-in-1.
- [ ] Screen lock, background, and process-recreation tests.
- [ ] Atomic profile replacement with rollback after failed restart.
- [ ] Bounded crash recovery with a visible terminal failure state.
- [ ] 8-hour phone run, followed by a 24-hour beta gate.

## Test evidence

For each device run, record the OS/API version, architecture, profile protocol (without credentials), selected engine, network bearer, start/end timestamps, transferred bytes, failure reason, and recovery result. Never store subscription URLs, tokens, server credentials, or traffic payloads in test artifacts.

### 2026-09-09 phone smoke test

- Device: SGT-AL00, ARM64, OpenHarmony 7.0.0.105 / API 26.
- Engine/protocol: xray-rust, VLESS REALITY Vision; endpoint and credentials redacted.
- Network: Wi-Fi with cellular available.
- Result: selected-node HTTPS probe returned HTTP 204 and the system browser rendered `https://www.google.com` through the VPN.
- TUN evidence: diagnostic snapshot reached 71 inbound and 60 outbound packets with zero general drops and zero TCP/UDP open errors.
- Expected compatibility event: two UDP/443 attempts were rejected by Vision and the browser successfully fell back to TCP.

### 2026-09-09 ClashRS packet-path test

- Device: SGT-AL00, ARM64, OpenHarmony 7.0.0.105 / API 26.
- Engine/profile: ClashRS; the sanitized profile inventory contains AnyTLS and VLESS nodes.
- Result: a selected node passed the dual HTTPS egress probe and the system browser rendered `https://www.google.com` through the VPN.
- DNS evidence: independent DNS queries over UDP and TCP received valid matching responses while the VPN was active.
- DIRECT evidence: after switching ClashRS to direct mode, independent IPv4 UDP and TCP DNS probes both received valid responses.
- Privacy: endpoints, subscription metadata, credentials, and traffic contents were not recorded.

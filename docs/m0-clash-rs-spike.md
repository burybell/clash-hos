# M0 ClashRS OHOS Spike

## Result

The native Rust/OHOS approach is viable enough to become the primary M0 data-plane path.

- Pinned upstream commit: `470bc5a427bfaea3fafcedf32563010f9a47b691` (`clash-rs` 0.10.8).
- License: Apache-2.0.
- ARM64 and x86_64 `libclashrs.so` build for Rust's native OHOS targets.
- The ARM64 library is packaged in the signed HAP and loads successfully on the physical HarmonyOS device.
- The C++ boundary resolves `clash_start` without starting the core or changing network routes.
- The generated ARM64 ELF is about 11 MiB and has only `libc.so` as a dynamic dependency.

## Maintained OHOS patch

The patch is deliberately narrow:

1. Enable the AWS-LC crypto backend required by the selected FFI features.
2. Disable Linux process-name lookup on OHOS because `sock2proc` pulls Linux netlink/libc assumptions that do not compile against OHOS libc.
3. Disable the Linux TProxy UDP helper on OHOS; M0 uses the system-created VPN TUN descriptor instead.
4. Temporarily omit TUIC from the FFI feature set because the pinned TUIC dependency uses an unstable Rust `if let` guard with the installed stable compiler.

Domain, IP, port, rule-set, Shadowsocks, SSH, DNS, HTTP/SOCKS and the base Clash configuration paths remain available in this build. Protocol coverage still requires configuration and on-device traffic tests before release claims are made.

## Reproducible build

`tools/build-clash-rs.sh` fetches the pinned commit into ignored `.build/`, applies `core/clash-rs/patches/0001-ohos-ffi.patch`, builds both supported ABIs, and copies generated libraries into the HAP ABI directories. Source metadata and the upstream license hash are stored in `core/clash-rs/upstream.json`.

## Next gate

The next gate is lifecycle and TUN integration:

1. Add a project-owned C ABI that accepts the HarmonyOS-created TUN file descriptor.
2. Generate a runtime configuration that uses ClashRS `fd://N` TUN input.
3. Protect outbound sockets from re-entering the VPN.
4. Start with DIRECT-only traffic, then validate TCP, UDP, DNS, HTTP/SOCKS and subscription nodes.
5. Keep the current fail-closed gate until the core proves it can drain the TUN descriptor.

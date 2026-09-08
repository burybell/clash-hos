# M0 Mihomo Port Spike

## Upstream baseline

- Version: `v1.19.30`
- Commit: `ac017cdd246ce8bd547653d927e7bf77d7ee73d5`
- Module: `github.com/metacubex/mihomo`
- Go module language floor: Go 1.20
- License file SHA-256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`
- `go.mod` SHA-256: `944b5c26fc12aec517a436d9204f034b513269b46ee66b900ba0855c9b53e9f3`

## Source inspection result

Mihomo already exposes reusable package-level entry points:

- `config.Parse` for configuration parsing.
- `hub.Parse` and `hub.ApplyConfig` for applying a configuration.
- `hub/executor.ParseWithBytes` and `ApplyConfig` for the CLI-style lifecycle.
- `hub/executor.Shutdown` for controlled teardown.

There is no existing OHOS C ABI. A small Go `main` wrapper with cgo exports is required.

The repository contains platform-specific paths for:

- iptables and TProxy;
- Linux process and UID lookup;
- socket marks and reuse options;
- automatic TUN creation;
- FakeTCP and path-MTU discovery;
- Android-specific DNS/time-zone behavior;
- core self-update and executable naming.

These features must not accidentally compile as normal Linux features merely because the first experiment uses the Linux Go runtime.

## Preferred experiment

Do not begin by porting the Go runtime to a new `GOOS`. HarmonyOS uses a Linux kernel and provides an NDK/Clang/sysroot, so first test a smaller approach:

1. Build with `GOOS=linux`, `GOARCH=arm64`, and `CGO_ENABLED=1`.
2. Link cgo using HarmonyOS NDK Clang and its sysroot.
3. Add the custom build tag `ohos`.
4. Make Linux-only files use `linux && !ohos` where their behavior is unavailable in the application sandbox.
5. Add OHOS stubs/adapters for only the required interfaces.
6. Disable `iptables`, TProxy, FakeTCP, core updater, process matching, and Mihomo-owned TUN creation during M0.
7. Produce `libmihomo_ohos.so` with C exports for create/start/reload/status/stop.
8. Pass the HarmonyOS-created TUN FD directly to the core.

This approach preserves Go's mature networking and protocol implementation while minimizing runtime changes. It is accepted only if the resulting ELF library loads on HarmonyOS 6 and survives the full M0 test gate.

## First ABI scope

The first library must expose only:

```c
int mihomo_create(const char* home_dir, const char* config_path, void** handle);
int mihomo_start(void* handle, int tun_fd);
int mihomo_reload(void* handle, const char* config_path);
int mihomo_status(void* handle, char* output, unsigned long output_size);
int mihomo_stop(void* handle, int timeout_ms);
void mihomo_destroy(void* handle);
```

No packet buffers cross this ABI. Go retains no ArkTS or Node-API objects. The C++ layer owns lifecycle synchronization and duplicates/transfers file descriptors explicitly.

## Experiment order

1. Use the installed DevEco Studio 6.1.1 and API 24 Native SDK.
2. Compile and load a trivial C++ `.so` in the HAP.
3. Compile and load a trivial Go `c-shared` library using the OHOS NDK linker.
4. Call a deterministic Go function through C++ and Node-API.
5. Build Mihomo configuration parsing only.
6. Start the core with DIRECT and local HTTP/SOCKS listeners, without VPN.
7. Add externally supplied TUN FD support.
8. Test socket protection and loop prevention.
9. Enable protocols incrementally and run differential tests.

## Current spike result

- Go 1.24.9 can cross-compile a `c-shared` probe with the HarmonyOS NDK Clang/sysroot.
- ARM64 and x86_64 OHOS ELF libraries build successfully and depend only on `libc.so`.
- Both libraries are packaged into the matching HAP ABI directories.
- The Go library has an explicit `libclash_go_spike.so` SONAME so host build paths do not leak into ELF dependencies.
- The C++ bridge loads the Go library with `dlopen` and fails closed if loading or symbol resolution fails.
- On-device loading reaches the HarmonyOS musl linker, but Go's `c-shared` output is rejected because its `initial-exec TLS` relocation resolves to a dynamically loaded definition.
- This matches the still-open upstream Go issue [golang/go#54805](https://github.com/golang/go/issues/54805); the unmodified `GOOS=linux` approach is therefore rejected.
- The application isolates native-core loading and remains usable with VPN routing disabled after this failure.
- The next data-plane spike is the native OHOS Rust target with ClashRS, which exposes TUN-by-file-descriptor support and avoids a custom Go runtime fork. Mihomo remains the compatibility reference and fallback only if a maintainable OHOS Go runtime port is proven.

## Failure conditions

Abandon this build approach if any of these remain after focused investigation:

- Go runtime syscalls are blocked or incompatible in normal HarmonyOS applications.
- A c-shared library cannot be loaded or initialized reliably on both phone and PC.
- cgo/NDK linking requires an unmaintainable toolchain fork.
- Linux build tags cause a broad, fragile patch set across upstream.
- idle memory, power, or startup cost cannot meet the proposal's provisional budgets.

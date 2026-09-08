# Mihomo OHOS Port

This directory records and will contain the minimal integration layer for the Mihomo data plane.

`upstream.json` is the reproducible upstream lock for the M0 spike. Upstream source is deliberately not vendored yet. The first experiment will use an external checkout at the locked commit so platform patches and licensing material remain explicit and auditable.

The initial build hypothesis is:

- retain the Linux Go runtime and target ARM64;
- use HarmonyOS NDK Clang and sysroot for cgo/linking;
- introduce an `ohos` build tag to exclude Linux-only iptables, TProxy, process inspection, FakeTCP, and automatic TUN creation;
- export a small C ABI from a dedicated Go `main` wrapper;
- let HarmonyOS create the TUN and pass its FD to the core.

This is a hypothesis, not a compatibility claim. It must pass the M0 device gates before being adopted.

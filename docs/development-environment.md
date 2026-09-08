# Development Environment Inventory

Checked on 2026-09-08.

## Installed tools

| Component | Version | Location |
|---|---:|---|
| DevEco Studio | 6.1.1 | `/Applications/DevEco-Studio.app` |
| HarmonyOS SDK | 6.1.1.125 / API 24 Release | DevEco bundled SDK |
| Hvigor | 6.24.4 | DevEco bundled tools |
| OHPM | 6.1.2.285 | DevEco bundled tools |
| HDC | 3.2.0d | DevEco bundled SDK |
| HarmonyOS Native Clang | 15.0.4 | DevEco bundled Native SDK |
| CMake | 3.28.2 | DevEco bundled Native SDK |
| Ninja | 1.12.0 | DevEco bundled Native SDK |
| Node.js | 18.20.1 | DevEco bundled tools |
| DevEco JBR | OpenJDK 21.0.8 | DevEco bundled runtime |

The Native sysroot contains `aarch64-linux-ohos`, `arm-linux-ohos`, and `x86_64-linux-ohos`, including the Node-API and HiLog libraries used by this project.

The tools are not globally available on the interactive shell `PATH`. `tools/hvigorw` sets `DEVECO_SDK_HOME` and `NODE_HOME` to the installed all-in-one DevEco locations.

## Emulator and device state

Configured virtual devices:

- Mate X7, phone, ARM64, HarmonyOS 6.1.1 / API 24.
- Pura 90, phone, ARM64, HarmonyOS 6.1.1 / API 24.
- MateBook Pro, PC, ARM64, HarmonyOS 6.1.1 / API 24.
- MatePad Pro 13, tablet, ARM64, HarmonyOS 6.1.1 / API 24.

Installed system images:

- PC ARM image is installed under the HarmonyOS 6.1.1 system-image directory.
- Phone image is not currently installed even though phone virtual-device configurations exist.
- A temporary/incomplete tablet image directory exists.

Current HDC state:

- `127.0.0.1:5555` is registered but offline.
- Physical device `192.168.1.5:46871` is connected over wireless HDC.
- Device model: `SGT-AL00`; device type: phone; ABI: `arm64-v8a`.
- Device system: `OpenHarmony-7.0.0.105`; API version: 26.
- The physical device is above the project's API 20 minimum and API 24 target.

## Build verification

The project successfully completed:

- Hvigor build-script type checking.
- HarmonyOS profile and resource validation.
- ArkTS compilation.
- Native CMake/Ninja compilation.
- ARM64 and x86_64 `libclash_core.so` packaging.
- Unsigned HAP packaging.
- Host-side C++ test through CMake/CTest.

Build outputs:

`entry/build/default/outputs/default/entry-default-unsigned.hap`

`entry/build/default/outputs/default/entry-default-signed.hap`

Project-specific automatic debug signing is configured locally and was verified on the connected phone. The credential-bearing `build-profile.json5` is ignored by Git; `build-profile.example.json5` is the publishable unsigned template. Signing credentials from other projects must never be copied into this repository.

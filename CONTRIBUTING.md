# Contributing to Clash HOS

Thank you for helping improve Clash HOS. Repository documentation defaults to English; Chinese context is also welcome.

## Before opening an issue

- Search existing issues first.
- Remove subscription URLs, tokens, passwords, addresses, UUIDs, certificates, and identifying logs.
- Include HarmonyOS/API version, device family, architecture, engine path, and reproducible steps.
- For UI reports, include appearance mode and phone/wide-screen context.

## Workflow

1. Fork the repository and create a focused branch.
2. Copy `build-profile.example.json5` to `build-profile.json5`; configure signing locally only.
3. Make the smallest coherent change.
4. Run `node tools/check-project.mjs`.
5. Run CMake/CTest for native bridge or lifecycle changes.
6. Build the HAP and test affected behavior on a device or emulator.
7. Open a pull request with behavior, verification, limitations, and UI screenshots when applicable.

## Engineering rules

- Keep packet processing and high-frequency I/O in native code.
- Keep ArkTS/native interfaces coarse-grained and lifecycle-safe.
- Pin upstream commits in `upstream.json`; never track moving branches.
- Carry HarmonyOS changes as small, reviewable patches.
- Never commit generated libraries, HAPs, build directories, signing profiles, IDE state, or real provider data.
- Preserve phone and PC/2-in-1 behavior and support both light and dark appearance.
- Explain user-facing failures without leaking secrets.

Use concise imperative commit subjects. Pull requests should state what changed, why, affected engines/devices, verification performed, and known follow-up work.

By contributing, you agree that your contribution is licensed under Apache-2.0.

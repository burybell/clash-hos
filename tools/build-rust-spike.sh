#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_root="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
llvm_bin="${sdk_root}/default/openharmony/native/llvm/bin"

build_one() {
  local rust_target="$1"
  local ohos_abi="$2"
  local env_target="$3"
  local linker="${llvm_bin}/${rust_target}-clang"

  if [[ ! -x "${linker}" ]]; then
    echo "HarmonyOS Rust linker not found: ${linker}" >&2
    exit 1
  fi

  cd "${project_dir}/core/rust-spike"
  env \
    RUSTC_BOOTSTRAP=1 \
    "CARGO_TARGET_${env_target}_LINKER=${linker}" \
    cargo build --release --target "${rust_target}" -Z build-std=std,panic_abort

  mkdir -p "${project_dir}/entry/libs/${ohos_abi}"
  cp "${project_dir}/core/rust-spike/target/${rust_target}/release/libclash_hos_rust_spike.so" \
    "${project_dir}/entry/libs/${ohos_abi}/libclash_hos_rust_spike.so"
  file "${project_dir}/entry/libs/${ohos_abi}/libclash_hos_rust_spike.so"
}

build_one aarch64-unknown-linux-ohos arm64-v8a AARCH64_UNKNOWN_LINUX_OHOS
build_one x86_64-unknown-linux-ohos x86_64 X86_64_UNKNOWN_LINUX_OHOS

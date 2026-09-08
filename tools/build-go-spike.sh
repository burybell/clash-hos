#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_root="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
native_root="${sdk_root}/default/openharmony/native"
clang="${native_root}/llvm/bin/clang"
if [[ ! -x "${clang}" ]]; then
  echo "HarmonyOS NDK Clang not found: ${clang}" >&2
  exit 1
fi

cd "${project_dir}/core/go-spike"

build_one() {
  local goarch="$1"
  local ohos_abi="$2"
  local clang_target="$3"
  local output_dir="${project_dir}/core/go-spike/build/${ohos_abi}"

  mkdir -p "${output_dir}"
  CGO_ENABLED=1 \
  GOOS=linux \
  GOARCH="${goarch}" \
  CC="${clang} --target=${clang_target} --sysroot=${native_root}/sysroot" \
  CGO_CFLAGS="--target=${clang_target} --sysroot=${native_root}/sysroot" \
  CGO_LDFLAGS="--target=${clang_target} --sysroot=${native_root}/sysroot -Wl,-soname,libclash_go_spike.so" \
  go build -trimpath -buildmode=c-shared -tags=ohos \
    -o "${output_dir}/libclash_go_spike.so" .

  mkdir -p "${project_dir}/entry/libs/${ohos_abi}"
  cp "${output_dir}/libclash_go_spike.so" \
    "${project_dir}/entry/libs/${ohos_abi}/libclash_go_spike.so"

  file "${output_dir}/libclash_go_spike.so"
}

build_one arm64 arm64-v8a aarch64-linux-ohos
build_one amd64 x86_64 x86_64-linux-ohos

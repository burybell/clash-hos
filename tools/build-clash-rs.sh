#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
metadata="${project_dir}/core/clash-rs/upstream.json"
patch_dir="${project_dir}/core/clash-rs/patches"
source_dir="${project_dir}/.build/clash-rs"

repository="$(sed -n 's/.*"repository": "\([^"]*\)".*/\1/p' "${metadata}")"
commit="$(sed -n 's/.*"commit": "\([^"]*\)".*/\1/p' "${metadata}")"
license_sha256="$(sed -n 's/.*"licenseSha256": "\([^"]*\)".*/\1/p' "${metadata}")"

sdk_native="${OHOS_SDK_NATIVE:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
llvm_bin="${sdk_native}/llvm/bin"
cmake_bin="${sdk_native}/build-tools/cmake/bin"

for required in cargo git "${llvm_bin}/aarch64-unknown-linux-ohos-clang" \
  "${llvm_bin}/x86_64-unknown-linux-ohos-clang" "${llvm_bin}/llvm-ar" \
  "${cmake_bin}/cmake"; do
  if ! command -v "${required}" >/dev/null 2>&1 && [[ ! -x "${required}" ]]; then
    echo "Missing required build tool: ${required}" >&2
    exit 1
  fi
done

if [[ ! -d "${source_dir}/.git" ]]; then
  mkdir -p "$(dirname "${source_dir}")"
  git clone --filter=blob:none "${repository}" "${source_dir}"
fi

if ! git -C "${source_dir}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
  git -C "${source_dir}" fetch --depth=1 origin "${commit}"
fi
if [[ "$(git -C "${source_dir}" rev-parse HEAD)" != "${commit}" ]]; then
  git -C "${source_dir}" checkout --detach "${commit}"
fi

actual_license_sha256="$(shasum -a 256 "${source_dir}/LICENSE" | awk '{print $1}')"
if [[ "${actual_license_sha256}" != "${license_sha256}" ]]; then
  echo "ClashRS license hash does not match pinned metadata" >&2
  exit 1
fi

patch_state="${source_dir}/.clash-hos-patchset"
patch_hash="$(shasum -a 256 "${patch_dir}"/*.patch | shasum -a 256 | awk '{print $1}')"
applied_hash=""
if [[ -f "${patch_state}" ]]; then
  applied_hash="$(sed -n '1p' "${patch_state}")"
fi
if [[ "${applied_hash}" != "${patch_hash}" ]]; then
  if ! git -C "${source_dir}" diff --quiet; then
    echo "ClashRS source has untracked patch changes; remove .build/clash-rs and retry" >&2
    exit 1
  fi
  for patch_file in "${patch_dir}"/*.patch; do
    git -C "${source_dir}" apply "${patch_file}"
  done
  printf '%s\n' "${patch_hash}" > "${patch_state}"
fi

build_one() {
  local target="$1"
  local abi="$2"
  local linker="${llvm_bin}/${target}-clang"
  local cc_key="CC_${target//-/_}"
  local ar_key="AR_${target//-/_}"
  local target_key
  target_key="$(printf '%s' "${target}" | tr '[:lower:]-' '[:upper:]_')"
  local linker_key="CARGO_TARGET_${target_key}_LINKER"

  env \
    RUSTC_BOOTSTRAP=1 \
    OHOS_SDK_NATIVE="${sdk_native}" \
    CMAKE="${cmake_bin}/cmake" \
    PATH="${cmake_bin}:${PATH}" \
    "${cc_key}=${linker}" \
    "${ar_key}=${llvm_bin}/llvm-ar" \
    "${linker_key}=${linker}" \
    cargo build \
      --manifest-path "${source_dir}/Cargo.toml" \
      -p clash-ffi \
      --release \
      --target "${target}" \
      -Z build-std=std,panic_abort

  mkdir -p "${project_dir}/entry/libs/${abi}"
  cp "${source_dir}/target/${target}/release/libclashrs.so" \
    "${project_dir}/entry/libs/${abi}/libclashrs.so"
}

build_one aarch64-unknown-linux-ohos arm64-v8a
build_one x86_64-unknown-linux-ohos x86_64

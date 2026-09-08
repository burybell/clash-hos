#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_dir}"

"${project_dir}/tools/build-rust-spike.sh"
"${project_dir}/tools/build-clash-rs.sh"
"${project_dir}/tools/build-xray-rust.sh"

"${project_dir}/tools/hvigorw" assembleHap \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --no-daemon

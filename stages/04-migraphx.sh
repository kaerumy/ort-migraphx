#!/bin/bash
# Stage 04: build MIGraphX (tag $MIGRAPHX_TAG, default rocm-10.1) against the
# ROCm $ROCM_VERSION SDK + the locally built rocMLIR, for $GPU_TARGETS.
#
# Usage:
#   04-migraphx.sh            # configure + build + install
#   04-migraphx.sh configure  # configure only (fast sanity check, no build)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"
source "$HERE/common.sh"

PHASE=${1:-all}
case "$PHASE" in configure|all) ;; *) die "phase must be 'configure' or 'all'" ;; esac

export CCACHE_DIR

[ -x "$ROCM_HOME/llvm/bin/clang" ] || {
  echo "ERROR: ROCm SDK clang not found at $ROCM_HOME/llvm/bin/clang (need TheRock ROCm $ROCM_VERSION)" >&2
  exit 1
}
[ -d "$ROCKMLIR_DIR/install" ] || {
  echo "ERROR: rocMLIR install prefix missing ($ROCKMLIR_DIR/install) — run the rocmlir stage first (make rocmlir)" >&2
  exit 1
}
[ -d "$DEPS_PREFIX" ] || {
  echo "ERROR: deps prefix missing ($DEPS_PREFIX) — run the deps stage first (make deps)" >&2
  exit 1
}

echo "=== AMDMIGraphX @ $MIGRAPHX_TAG ==="
get_source "$MIGRAPHX_DIR/src" https://github.com/ROCm/AMDMIGraphX.git "$MIGRAPHX_TAG" tag

echo "=== cmake configure: migraphx (GPU_TARGETS=$GPU_TARGETS) ==="
cmake -S "$MIGRAPHX_DIR/src" -B "$MIGRAPHX_DIR/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ROCM_HOME/llvm/bin/clang" \
  -DCMAKE_CXX_COMPILER="$ROCM_HOME/llvm/bin/clang++" \
  -DGPU_TARGETS="$GPU_TARGETS" \
  -DCMAKE_PREFIX_PATH="$ROCKMLIR_DIR/install;$DEPS_PREFIX;$ROCM_HOME;$ROCM_HOME/llvm" \
  -DCMAKE_INSTALL_PREFIX="$MIGRAPHX_DIR/install" \
  -DMIGRAPHX_ENABLE_PYTHON=Off \
  -DMIGRAPHX_ENABLE_TENSORFLOW=Off \
  -DMIGRAPHX_ENABLE_ONNX=On \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

if [ "$PHASE" = "configure" ]; then
  echo "MIGRAPHX_CONFIGURE_DONE (build not started; run 'make migraphx' to build)"
  exit 0
fi

echo "=== cmake build: migraphx (-j$JOBS) ==="
cmake --build "$MIGRAPHX_DIR/build" -j"$JOBS"

cmake --install "$MIGRAPHX_DIR/build"

echo "MIGRAPHX_BUILD_DONE -> $MIGRAPHX_DIR/install"
stamp 04-migraphx

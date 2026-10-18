#!/bin/bash
# Stage 03: build rocMLIR (Triton/MLIR JIT codegen stack) for ROCm
# $ROCM_VERSION, with the $GPU_TARGETS targets. This is the longest stage
# (hours). Per MIGraphX $MIGRAPHX_TAG requirements.txt:
#   ROCm/rocmlirTriton@$ROCKMLIR_BRANCH -DBUILD_FAT_LIBROCKCOMPILER=On
#   -DLLVM_INCLUDE_TESTS=Off -DMLIR_ENABLE_ROCM_RUNNER=Off -DMLIR_INCLUDE_TESTS=Off
#   -DLLVM_TARGETS_TO_BUILD=X86;AMDGPU
#
# Usage:
#   03-rocmlir.sh            # configure + build + install
#   03-rocmlir.sh configure  # configure only (fast sanity check, no build)
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
require_cmd ninja ccache

echo "=== rocmlirTriton @ $ROCKMLIR_BRANCH ==="
get_source "$ROCKMLIR_DIR/src" https://github.com/ROCm/rocmlirTriton.git "$ROCKMLIR_BRANCH" tag

echo "=== cmake configure: rocmlir ==="
cmake -S "$ROCKMLIR_DIR/src" -B "$ROCKMLIR_DIR/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER="$ROCM_HOME/llvm/bin/clang" \
  -DCMAKE_CXX_COMPILER="$ROCM_HOME/llvm/bin/clang++" \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
  -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DBUILD_FAT_LIBROCKCOMPILER=ON \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DMLIR_ENABLE_ROCM_RUNNER=OFF \
  -DMLIR_INCLUDE_TESTS=OFF \
  -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU" \
  -DROCM_PATH="$ROCM_HOME" \
  -DCMAKE_INSTALL_PREFIX="$ROCKMLIR_DIR/install"

if [ "$PHASE" = "configure" ]; then
  echo "ROCKMLIR_CONFIGURE_DONE (build not started; run 'make rocmlir' to build)"
  exit 0
fi

echo "=== cmake build: rocmlir (-j$JOBS) ==="
cmake --build "$ROCKMLIR_DIR/build" -j"$JOBS"

cmake --install "$ROCKMLIR_DIR/build"

echo "ROCKMLIR_BUILD_DONE -> $ROCKMLIR_DIR/install"
stamp 03-rocmlir

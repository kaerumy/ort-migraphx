#!/bin/bash
# Stage 02: build the composable_kernel (CK) host / codegen JIT from the
# MIGraphX-pinned commit. Per MIGraphX $MIGRAPHX_TAG requirements.txt:
#   ROCm/composable_kernel@$CK_COMMIT, build the codegen/ dir.
# The codegen template driver is what MIGraphX's kernel JIT invokes at
# runtime, so it must match the MIGraphX-pinned CK commit exactly.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"
source "$HERE/common.sh"

SRC=$DEPS_DIR/src
BLD=$DEPS_DIR/build
LOG=$DEPS_DIR/build-deps.log
mkdir -p "$SRC" "$BLD"
export CCACHE_DIR

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

[ -x "$ROCM_HOME/llvm/bin/clang" ] || {
  echo "ERROR: ROCm SDK clang not found at $ROCM_HOME/llvm/bin/clang (need TheRock ROCm $ROCM_VERSION)" >&2
  exit 1
}

log "=== composable_kernel @ $CK_COMMIT ==="
get_source "$SRC/composable_kernel" https://github.com/ROCm/composable_kernel.git "$CK_COMMIT" commit

log "=== cmake configure: ck-host ==="
cmake -S "$SRC/composable_kernel/codegen" -B "$BLD/ck-host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ROCM_HOME/llvm/bin/clang" \
  -DCMAKE_CXX_COMPILER="$ROCM_HOME/llvm/bin/clang++" \
  -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
  -DCMAKE_PREFIX_PATH="$ROCM_HOME" \
  -DBUILD_TESTING=Off

log "=== cmake build: ck-host ==="
cmake --build "$BLD/ck-host" -j"$JOBS" >>"$LOG" 2>&1
cmake --install "$BLD/ck-host" >>"$LOG" 2>&1
log "CK_HOST_DONE -> $DEPS_PREFIX"
stamp 02-ck

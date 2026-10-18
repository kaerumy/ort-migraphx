#!/bin/bash
# Stage 05: build ONNX Runtime $ORT_TAG (default v1.31.0, Release, shared lib)
# with the MIGraphX execution provider enabled, against the locally built
# MIGraphX (stage 04).
#
# Toolchain: system clang-22 ($ORT_CC / $ORT_CXX, overridable).
#   - GCC 15 trips -Werror=maybe-uninitialized false positive in libstdc++
#     bits/unicode.h
#   - SDK clang 24 trips -Werror,-Wdeprecated-attributes on the pinned
#     abseil/googletest/onnx/protobuf headers (lifetime_capture_by(this))
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"
source "$HERE/common.sh"

export CCACHE_DIR

SRC=$ORT_DIR/onnxruntime
[ -x "$(command -v "$ORT_CC")" ] || {
  echo "ERROR: $ORT_CC not found — the ORT stage needs system clang-22 (see header note)." >&2
  echo "       override with ORT_CC=<compiler> ORT_CXX=<compiler> if your box differs." >&2
  exit 1
}
[ -d "$MIGRAPHX_DIR/install" ] || {
  echo "ERROR: MIGraphX install prefix missing ($MIGRAPHX_DIR/install) — run the migraphx stage first (make migraphx)" >&2
  exit 1
}

# --- Clone (resume-safe: existing checkout is kept and built incrementally)
echo "=== onnxruntime @ $ORT_TAG ==="
get_source "$SRC" https://github.com/microsoft/onnxruntime.git "$ORT_TAG" tag

# --- Apply the MIGraphX-EP build fixes from ../patches/ (idempotent)
PATCH=$REPO_ROOT/patches/ort-v1.31.0-migraphx-ep-cosmetic.patch
echo "=== patch: $(basename "$PATCH") ==="
if git -C "$SRC" apply --check "$PATCH" 2>/dev/null; then
  git -C "$SRC" apply "$PATCH"
  echo "    applied"
elif git -C "$SRC" apply --check -R "$PATCH" 2>/dev/null; then
  echo "    already applied (skipping)"
else
  echo "ERROR: patch applies neither forward nor reverse — checkout state unexpected." >&2
  echo "       rm -rf $SRC and re-run to re-clone a clean tree." >&2
  exit 1
fi

export CC="$ORT_CC" CXX="$ORT_CXX"

echo "=== onnxruntime build.sh (Release, shared, MIGraphX EP) ==="
cd "$SRC"
# NOTE: build dir is incremental across reruns (kept for resume).
./build.sh --config Release \
  --build_shared_lib \
  --parallel \
  --skip_tests \
  --use_migraphx \
  --migraphx_home "$MIGRAPHX_DIR/install"

echo "ORT_BUILD_DONE -> $SRC/build/Linux/Release"
stamp 05-ort

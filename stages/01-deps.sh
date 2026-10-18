#!/bin/bash
# Stage 01: build the MIGraphX $MIGRAPHX_TAG pinned prerequisites into
# $DEPS_PREFIX. Versions are pinned per the MIGraphX tag's requirements.txt
# (see config/build.env) plus this project's build provenance.
#
#   1. rocm-cmake  (pinned commit)
#   2. abseil      (kept to mirror the validated deps prefix)
#   3. nlohmann/json
#   4. msgpack-c
#   5. eigen
#   6. pcre 8.45   (pfultz2 fork, per rocm-recipes; autotools build)
#
# zstd 1.5.7 and sqlite3 come from system dev packages instead of source
# builds (Ubuntu ships exactly the pinned versions).
#
# IMPORTANT — protobuf is NOT built here, on purpose. The validated stack
# links the system libprotobuf.so.32 (Ubuntu libprotobuf32t64) dynamically:
# MIGraphX's CMake does `find_package(protobuf QUIET CONFIG)` and, finding
# nothing, falls back to module mode, which resolves the system protoc and
# the system shared protobuf. If a protobuf CMake config were present in
# this prefix, MIGraphX would statically link its own protobuf — a second
# protobuf runtime in the process alongside ORT's bundled one, which breaks
# the MIGraphX EP at runtime (segfault in EP::Compile).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"
source "$HERE/common.sh"

SRC=$DEPS_DIR/src
BLD=$DEPS_DIR/build
TMP=$DEPS_DIR/tmp
LOG=$DEPS_DIR/build-deps.log
mkdir -p "$SRC" "$BLD" "$TMP"

# --- Prerequisites (install yourself; this script does not sudo) ----------
require_pkg libzstd-dev libsqlite3-dev libprotobuf-dev protobuf-compiler autoconf automake git cmake curl

# protobuf comes exclusively from the system; verify the version floor.
sys_pb=$(dpkg-query -W -f'${Version}' libprotobuf-dev 2>/dev/null || true)
if [ -z "$sys_pb" ] || ! dpkg --compare-versions "$sys_pb" ge "$MIN_PROTOBUF"; then
  echo "ERROR: system protobuf >= $MIN_PROTOBUF required (found: ${sys_pb:-none})" >&2
  exit 1
fi
log "system protobuf $sys_pb (module-mode fallback for MIGraphX) OK"

export CCACHE_DIR
CCL=()
command -v ccache >/dev/null 2>&1 && CCL=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
build_cmake() { # name srcdir cmake...
  local name=$1 srcdir=$2; shift 2
  log "=== cmake configure: $name ==="
  cmake -S "$SRC/$srcdir" -B "$BLD/$name" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "${CCL[@]}" "$@"
  log "=== cmake build: $name ==="
  cmake --build "$BLD/$name" -j"$JOBS" >>"$LOG" 2>&1
  cmake --install "$BLD/$name" >>"$LOG" 2>&1
  log "=== installed: $name ==="
}

# 1. rocm-cmake (pinned commit from MIGraphX requirements)
log "=== rocm-cmake @ $ROCM_CMAKE_COMMIT ==="
get_source "$SRC/rocm-cmake" https://github.com/RadeonOpenCompute/rocm-cmake.git "$ROCM_CMAKE_COMMIT" commit
build_cmake rocm-cmake rocm-cmake

# 2. abseil (historically a protobuf-v30 dependency; kept so the prefix
#    mirrors the validated deps layout exactly)
log "=== abseil-cpp @ $ABSEIL_TAG ==="
get_source "$SRC/abseil-cpp" https://github.com/abseil/abseil-cpp.git "$ABSEIL_TAG" tag shallow
build_cmake abseil abseil-cpp -DABSL_ENABLE_INSTALL=ON

# 3. nlohmann/json
log "=== nlohmann/json @ $JSON_TAG ==="
get_source "$SRC/json" https://github.com/nlohmann/json.git "$JSON_TAG" tag shallow
build_cmake json json -DBUILD_TESTING=Off

# 4. msgpack-c
log "=== msgpack-c @ $MSGPACK_TAG ==="
get_source "$SRC/msgpack-c" https://github.com/msgpack/msgpack-c.git "$MSGPACK_TAG" tag shallow
build_cmake msgpack msgpack-c -DMSGPACK_BUILD_TESTS=Off -DMSGPACK_BUILD_EXAMPLES=Off -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF

# 5. eigen (header-only tarball)
log "=== eigen $EIGEN_VERSION ==="
if [ ! -f "$SRC/eigen/CMakeLists.txt" ]; then
  rm -rf "$SRC/eigen"
  mkdir -p "$SRC/eigen"
  curl -fsSL "https://gitlab.com/libeigen/eigen/-/archive/$EIGEN_VERSION/eigen-$EIGEN_VERSION.tar.gz" -o "$TMP/eigen.tar.gz"
  tar xzf "$TMP/eigen.tar.gz" -C "$SRC/eigen" --strip-components=1
fi
build_cmake eigen eigen -DBUILD_TESTING=Off -DEIGEN_BUILD_DOC=Off -DEIGEN_BUILD_LAPACK=Off

# 6. pcre 8.45 (pfultz2 fork per rocm-recipes; no pcre1 package in Ubuntu 26.10)
log "=== pcre @ $PCRE_BRANCH ==="
get_source "$SRC/pcre" https://github.com/pfultz2/pcre.git "$PCRE_BRANCH" tag shallow
# The repo ships pre-generated autotools files (from automake 1.16). Clone
# checkout timestamps jitter, which can make `make` think aclocal.m4 is stale
# and try to regenerate it via the old 1.16 rules (aclocal-1.16 may not exist
# on this system). Keep the generated artifacts newer than the .ac/.am/.m4
# inputs so no regeneration is attempted.
touch "$SRC/pcre/aclocal.m4" "$SRC/pcre/configure" "$SRC/pcre/Makefile.in"
log "=== build pcre (autotools) ==="
(
  cd "$SRC/pcre"
  [ -x ./configure ] || autoreconf -fi
  ./configure --prefix="$DEPS_PREFIX" CFLAGS="-fPIC"
  make -j"$JOBS"
  make install
) >>"$LOG" 2>&1
log "=== installed: pcre ==="

log "ALL DEPS DONE -> $DEPS_PREFIX"
stamp 01-deps

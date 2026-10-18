#!/bin/bash
# Print the resolved build configuration and check the local environment.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

ok()   { printf '  [ ok ] %s\n' "$1"; }
miss() { printf '  [MISS] %s\n' "$1"; }

echo "=== configuration (config/build.env) ==="
echo "  GPU targets : $GPU_TARGETS"
echo "  package     : $PKG_NAME  ($PKG_VERSION)"
echo "  ROCm        : $ROCM_VERSION at $ROCM_HOME (core libdir: $ROCM_CORE_LIBDIR)"
echo "  ORT         : $ORT_TAG        MIGraphX: $MIGRAPHX_TAG ($MIGRAPHX_VERSION)"
echo "  rocMLIR     : $ROCKMLIR_BRANCH"
echo "  CK commit   : $CK_COMMIT"
echo "  deps pins   : rocm-cmake=$ROCM_CMAKE_COMMIT abseil=$ABSEIL_TAG json=$JSON_TAG"
echo "                msgpack=$MSGPACK_TAG eigen=$EIGEN_VERSION pcre=$PCRE_BRANCH protobuf=system(>=$MIN_PROTOBUF)"
echo "  ORT cc      : $ORT_CC / $ORT_CXX     JOBS: $JOBS"
echo "  build root  : $BUILD_ROOT"
echo "  package dir : $PACKAGE_ROOT"
echo "  dist dir    : $DIST_DIR"
echo
echo "=== environment ==="
if [ -x "$ROCM_HOME/llvm/bin/clang" ]; then
  ok "ROCm SDK clang ($ROCM_HOME/llvm/bin/clang)"
else
  miss "ROCm SDK clang at $ROCM_HOME/llvm/bin/clang (install TheRock ROCm $ROCM_VERSION, or ROCM_HOME=/path)"
fi
for t in git cmake curl ninja ccache patchelf gcc make dpkg-deb; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else miss "$t"; fi
done
if command -v "$ORT_CC" >/dev/null 2>&1; then
  ok "$ORT_CC (ORT stage compiler)"
else
  miss "$ORT_CC (ORT stage compiler; override with ORT_CC/ORT_CXX)"
fi
for p in libzstd-dev libsqlite3-dev autoconf automake; do
  if dpkg-query -W "$p" >/dev/null 2>&1; then ok "$p"; else miss "$p"; fi
done
echo
echo "=== amdrocm packages (TheRock $ROCM_VERSION) ==="
for t in $GPU_TARGETS; do
  for p in "amdrocm-runtime$ROCM_VERSION" "amdrocm-dnn$ROCM_VERSION-$t" "amdrocm-blas$ROCM_VERSION-$t"; do
    if v=$(dpkg-query -W -f'${Version}' "$p" 2>/dev/null); then
      ok "$p ($v)"
    else
      miss "$p (needed at install time; TheRock repo + apt-get install)"
    fi
  done
done

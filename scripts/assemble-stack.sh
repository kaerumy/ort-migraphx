#!/bin/bash
# Assemble the stack built under $BUILD_ROOT into the dpkg payload tree:
#
#   $PACKAGE_ROOT/$PKG_NAME/
#     usr/lib/$PKG_NAME/lib/        ORT + MIGraphX libraries (RPATH-hardened)
#     usr/lib/$PKG_NAME/test/       smoke-test binaries + model
#     usr/share/doc/$PKG_NAME/      package README
#
# Prerequisite: the full build (make deps ck rocmlir migraphx ort).
# The resulting tree is packaged by scripts/build-deb.sh (make deb).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

die() { echo "ERROR: $*" >&2; exit 1; }

PAYLOAD_ROOT=$PACKAGE_ROOT/$PKG_NAME
LIB=$PAYLOAD_ROOT/usr/lib/$PKG_NAME/lib
TEST=$PAYLOAD_ROOT/usr/lib/$PKG_NAME/test
ORT_SRC=$ORT_DIR/onnxruntime
ORT_BLD=$ORT_SRC/build/Linux/Release
MG_INSTALL=$MIGRAPHX_DIR/install

# --- Safety: the payload root must live inside the repo ----------------------
case "$PAYLOAD_ROOT" in
  "$REPO_ROOT"/*) ;;
  *) die "payload root ($PAYLOAD_ROOT) is not inside $REPO_ROOT — refusing" ;;
esac

# --- Build outputs present? ---------------------------------------------------
ls "$ORT_BLD"/libonnxruntime.so.1.* >/dev/null 2>&1 \
  || die "ORT build missing ($ORT_BLD) — run: make ort"
[ -f "$MG_INSTALL/lib/migraphx/lib/libmigraphx_gpu.so.2018000.0" ] \
  || die "MIGraphX build missing ($MG_INSTALL) — run: make migraphx"
command -v patchelf >/dev/null 2>&1 || die "patchelf not found (apt-get install patchelf)"
command -v gcc >/dev/null 2>&1 || die "gcc not found (apt-get install gcc)"

rm -rf "$PAYLOAD_ROOT"
mkdir -p "$LIB/migraphx/lib" "$TEST" "$PAYLOAD_ROOT/usr/share/doc/$PKG_NAME"

echo "==> ORT libraries from $ORT_BLD"
# main lib (versioned file + .so / .so.1 symlinks) + provider libs
cp -a "$ORT_BLD"/libonnxruntime.so.1.* "$LIB/"
cp -a "$ORT_BLD"/libonnxruntime.so "$ORT_BLD"/libonnxruntime.so.1 "$LIB/"
cp -a "$ORT_BLD"/libonnxruntime_providers_migraphx.so* "$LIB/"
cp -a "$ORT_BLD"/libonnxruntime_providers_shared.so* "$LIB/"

echo "==> MIGraphX libraries (preserving the lib/migraphx/lib layout)"
cp -a "$MG_INSTALL/lib"/libmigraphx_c.so* "$LIB/"
cp -a "$MG_INSTALL/lib/migraphx/lib/." "$LIB/migraphx/lib/"

echo "==> Hardening RPATHs so the stack resolves ROCm without the ld cache"
# libmigraphx_gpu.so has 6 ROCm NEEDED entries (amdhip64, hiprtc, MIOpen,
# rocblas, hipblaslt, hsa-runtime64). TheRock debs do not register $ROCM_HOME
# with ldconfig, and some systems resolve libamdhip64 from elsewhere (masking
# the rest). Add the ROCm dirs to the GPU lib's (inherited) DT_RPATH so the
# target dlopen resolves all of them even without any ldconfig registration.
GPU_LIB="$LIB/migraphx/lib/libmigraphx_gpu.so.2018000.0"
CUR_RPATH=$(readelf -d "$GPU_LIB" | awk -F'[][]' '/\(RPATH\)|\(RUNPATH\)/{print $2; exit}')
if [ -n "$CUR_RPATH" ]; then NEW_RPATH="$CUR_RPATH:$ROCM_CORE_LIBDIR:$ROCM_LIBDIR"; else NEW_RPATH="$ROCM_CORE_LIBDIR:$ROCM_LIBDIR"; fi
patchelf --force-rpath --set-rpath "$NEW_RPATH" "$GPU_LIB"
echo "    rpath now: $(readelf -d "$GPU_LIB" | awk -F'[][]' '/\(RPATH\)/{print $2}')"
# The provider lib carries a stale build-time RUNPATH (this box's migraphx
# install prefix + $ROCM_HOME/lib). Replace it with self-relative dirs (so the
# provider finds libmigraphx_c and the chain next to itself) plus the ROCm
# dirs (its NEEDED libamdhip64.so.7 must resolve even if ROCm is not in the
# ld cache).
PROV_LIB="$LIB/libonnxruntime_providers_migraphx.so"
patchelf --force-rpath --set-rpath "\$ORIGIN:\$ORIGIN/migraphx/lib:$ROCM_CORE_LIBDIR:$ROCM_LIBDIR" "$PROV_LIB"
echo "    provider rpath now: $(readelf -d "$PROV_LIB" | awk -F'[][]' '/\(RPATH\)/{print $2}')"

echo "==> Test binaries (from test/) + test model"
gcc -O2 -std=c11 -o "$TEST/test_ort_mgx" "$REPO_ROOT/test/test_ort_mgx.c" \
  -I "$ORT_SRC/include/onnxruntime/core/session" -L "$ORT_BLD" -lonnxruntime \
  -Wl,-rpath,'$ORIGIN/../lib' -lm
gcc -O2 -o "$TEST/test_darktable_path" "$REPO_ROOT/test/test_darktable_path.c" \
  -I "$ORT_SRC/include/onnxruntime/core/session"
cp -a "$REPO_ROOT/test/test_mgx.onnx" "$REPO_ROOT/test/x_input.bin" "$REPO_ROOT/test/y_expected.bin" "$TEST/"

echo "==> Package README"
sed -e "s|@PKG_NAME@|$PKG_NAME|g" \
    -e "s|@ORT_VERSION@|$ORT_VERSION|g" \
    -e "s|@ROCM_VERSION@|$ROCM_VERSION|g" \
    -e "s|@GPU_TARGETS@|$GPU_TARGETS|g" \
    "$REPO_ROOT/templates/package-readme.md.in" \
    > "$PAYLOAD_ROOT/usr/share/doc/$PKG_NAME/README.md"

echo "==> Stripping"
strip --strip-unneeded "$LIB"/libonnxruntime.so.1.* 2>/dev/null || true
strip --strip-unneeded "$LIB/libonnxruntime_providers_migraphx.so" 2>/dev/null || true
strip --strip-unneeded "$LIB/libmigraphx_c.so.3.0"
# strip real files only (skip symlinks)
for f in "$LIB"/migraphx/lib/*.so.*.*; do
  [ -L "$f" ] && continue
  strip --strip-unneeded "$f"
done

echo "ASSEMBLE DONE — payload tree at $PAYLOAD_ROOT"
echo "Package it with:  make deb"
echo "Verify it with:   make test   (needs the AMD GPU + ROCm $ROCM_VERSION)"

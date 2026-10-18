#!/bin/bash
# Smoke test a staged or installed stack (needs the AMD GPU + ROCm).
#
#   make test             -> the payload tree (package/<pkg>/usr/lib/<pkg>)
#   make test-installed   -> /usr/lib/<pkg>   (requires: make install-deb)
#
#   1. test_darktable_path: dlopen the versioned lib, request C API v24
#      (what darktable 5.6.2 was built against), check the MIGraphX provider.
#   2. test_ort_mgx: create a session with the MIGraphX EP (device 0),
#      run a tiny model, compare the output. First run is slow (MIGraphX
#      Triton JIT for the target); results are cached under ~/.cache/migraphx.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "${1:-}" = "--installed" ]; then
  ROOT=/usr/lib/$PKG_NAME
else
  ROOT=$PACKAGE_ROOT/$PKG_NAME/usr/lib/$PKG_NAME
fi
LIBF="$ROOT/lib/libonnxruntime.so.$ORT_VERSION"
[ -f "$LIBF" ] || die "$LIBF not found — run: make assemble (or make install-deb)"
[ -x "$ROOT/test/test_ort_mgx" ] || die "test binaries missing under $ROOT/test — run: make assemble"

echo "===== test_darktable_path ($LIBF) ====="
"$ROOT/test/test_darktable_path" "$LIBF"
echo
echo "===== test_ort_mgx (MIGraphX EP inference) ====="
(cd "$ROOT/test" && ./test_ort_mgx test_mgx.onnx x_input.bin y_expected.bin 4)
echo
echo "SMOKE TEST PASSED"

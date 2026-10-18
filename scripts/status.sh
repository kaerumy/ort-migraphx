#!/bin/bash
# Show where a build stands: completion stamps + generated artifacts.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

STAGES=(
  "01-deps|$DEPS_DIR/src"
  "02-ck|$DEPS_DIR/build/ck-host"
  "03-rocmlir|$ROCKMLIR_DIR/build"
  "04-migraphx|$MIGRAPHX_DIR/build"
  "05-ort|$ORT_DIR/onnxruntime/build"
)

printf '%-13s  %s\n' "STAGE" "STATE"
for entry in "${STAGES[@]}"; do
  s=${entry%%|*}; d=${entry#*|}
  if [ -f "$STAMP_DIR/$s.done" ]; then
    printf '%-13s  done (%s)\n' "$s" "$(cut -d' ' -f1 "$STAMP_DIR/$s.done")"
  elif [ -d "$d" ]; then
    printf '%-13s  in progress (no completion stamp)\n' "$s"
  else
    printf '%-13s  not started\n' "$s"
  fi
done
echo
if [ -f "$PACKAGE_ROOT/$PKG_NAME/usr/lib/$MULTIARCH/$PKG_NAME/lib/libonnxruntime.so.$ORT_VERSION" ]; then
  echo "payload : staged  ($PACKAGE_ROOT/$PKG_NAME)"
else
  echo "payload : not staged (run: make assemble)"
fi
if ls "$DIST_DIR"/${PKG_NAME}_*.deb >/dev/null 2>&1; then
  echo "deb     : $(ls "$DIST_DIR"/${PKG_NAME}_*.deb | sed 's|^|          |' | tr '\n' ' ')"
else
  echo "deb     : none in $DIST_DIR (run: make deb)"
fi

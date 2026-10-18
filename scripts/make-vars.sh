#!/bin/bash
# Print resolved config values for the Makefile.
#   make-vars.sh            -> VAR=value lines (all known vars)
#   make-vars.sh VAR [VAR..]-> the value(s) only (one per line)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"
KNOWN=(PKG_NAME PKG_VERSION ORT_VERSION MIGRAPHX_VERSION ROCM_VERSION GPU_TARGETS \
       ORT_TAG MIGRAPHX_TAG ROCKMLIR_BRANCH CK_COMMIT JOBS \
       REPO_ROOT BUILD_ROOT PACKAGE_ROOT DIST_DIR ROCM_HOME)
if [ $# -eq 0 ]; then
  for v in "${KNOWN[@]}"; do printf '%s=%s\n' "$v" "${!v}"; done
else
  for v in "$@"; do
    [[ " ${KNOWN[*]} " == *" $v "* ]] || { echo "unknown var: $v" >&2; exit 2; }
    printf '%s\n' "${!v}"
  done
fi

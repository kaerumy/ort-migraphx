#!/bin/bash
# Install the built .deb. Uses apt so the Depends (amdrocm runtime +
# Ubuntu libs) are resolved from the configured repositories — this is the
# user-facing install path the package is designed for.
#
#   make install-deb           -> newest .deb in dist/
#   make install-deb /path.deb -> a specific .deb
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

DEB=${1:-}
if [ -z "$DEB" ]; then
  DEB=$(ls -t "$DIST_DIR"/${PKG_NAME}_*.deb 2>/dev/null | head -n1 || true)
fi
[ -n "$DEB" ] && [ -f "$DEB" ] || {
  echo "ERROR: no .deb found in $DIST_DIR — run: make deb" >&2
  exit 1
}

run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

echo "Installing: $DEB"
run_root apt-get install -y "$DEB"
echo
echo "Installed. Verify with:  make test-installed"
echo "Uninstall with:          make uninstall-deb"

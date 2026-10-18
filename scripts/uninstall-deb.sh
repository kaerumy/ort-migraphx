#!/bin/bash
# Uninstall (purge) the package: removes the files, runs postrm (which
# drops the ld.so.conf.d fragment postinst may have created).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

if ! dpkg-query -W "$PKG_NAME" >/dev/null 2>&1; then
  echo "$PKG_NAME is not installed — nothing to do."
  exit 0
fi

run_root apt-get purge -y "$PKG_NAME"
echo "Purged $PKG_NAME."

# Shared helpers for the stage scripts (sourced, never executed directly).
# Requires: config/build.env sourced first.

# --- logging -------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- prerequisite checks ----------------------------------------------------
# require_cmd CMD...   — binaries must be on PATH
require_cmd() {
  local c missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] \
    || die "missing tools: ${missing[*]} (apt-get install, see README.md Prerequisites)"
}

# require_pkg PKG...   — Ubuntu/Debian packages must be installed
require_pkg() {
  local p missing=()
  for p in "$@"; do dpkg-query -W "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [ ${#missing[@]} -gt 0 ]; then
    die "missing system packages: ${missing[*]}
       install with:  sudo apt-get install ${missing[*]}"
  fi
}

# --- source fetching (resume-safe: an existing checkout is kept as-is) ----
# get_source DIR URL REF [kind] [shallow]
#   kind=tag    -> git clone --branch REF  (rocmlirTriton, AMDMIGraphX, onnxruntime)
#   kind=commit -> full clone + shallow fetch of the pinned commit (rocm-cmake, CK)
#   shallow     -> --depth 1 (small deps: abseil, json, msgpack, pcre)
get_source() {
  local dir=$1 url=$2 ref=$3 kind=${4:-tag} shallow=${5:-}
  if [ -d "$dir/.git" ]; then
    log "    using existing checkout: $dir (pin: $ref)"
    return 0
  fi
  log "    cloning $url @ $ref"
  rm -rf "$dir"
  if [ "$kind" = "commit" ]; then
    # GitHub does not serve raw commits in clone --branch; fetch it shallow.
    git clone --quiet "$url" "$dir"
    git -C "$dir" fetch --quiet --depth 1 origin "$ref"
    git -C "$dir" checkout --quiet "$ref"
  elif [ -n "$shallow" ]; then
    git clone --quiet --depth 1 --branch "$ref" "$url" "$dir"
  else
    git clone --quiet --branch "$ref" "$url" "$dir"
  fi
}

# --- stage bookkeeping -------------------------------------------------------
# stamp NAME — record stage completion (read by `make status`).
stamp() {
  mkdir -p "$STAMP_DIR"
  printf '%s  (%s)\n' "$(date -Is)" "$1" > "$STAMP_DIR/$1.done"
}

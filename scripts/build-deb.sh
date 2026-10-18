#!/bin/bash
# Build the $PKG_NAME .deb from the payload tree created by assemble-stack.sh:
#   * render DEBIAN/{control,postinst,postrm} from templates/
#   * derive the Depends field from the staged libraries' NEEDED entries
#     (no hardcoded lists — it adapts to new ROCm versions / GPU targets)
#   * generate md5sums and run dpkg-deb -> $DIST_DIR/
#
# Prerequisite: make assemble  (the payload tree must exist).
#
#   -> dist/$PKG_NAME_$PKG_VERSION_amd64.deb
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config/build.env"

die() { echo "ERROR: $*" >&2; exit 1; }

PAYLOAD_ROOT=$PACKAGE_ROOT/$PKG_NAME
LIBDIR=$PAYLOAD_ROOT/usr/lib/$PKG_NAME
DEBIAN=$PAYLOAD_ROOT/DEBIAN
ARCH=amd64
DEB=$DIST_DIR/${PKG_NAME}_${PKG_VERSION}_${ARCH}.deb

[ -f "$LIBDIR/lib/libonnxruntime.so.$ORT_VERSION" ] \
  || die "payload tree missing ($PAYLOAD_ROOT) — run: make assemble"
command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found (apt-get install dpkg-dev)"
command -v readelf >/dev/null 2>&1 || die "readelf not found (apt-get install binutils)"

# =============================================================================
# Derive Depends from the staged libraries' NEEDED entries
# =============================================================================
# Collect, over every real (non-symlink) ELF under usr/:
#   bundled  — the SONAMEs we provide ourselves
#   required — every NEEDED entry (our own plus external)
# external = required - bundled  ->  must be satisfied by Depends
elf_files=()
while IFS= read -r -d '' f; do elf_files+=("$f"); done \
  < <(find "$PAYLOAD_ROOT/usr" -type f -print0)

bundled=() required=()
for f in "${elf_files[@]}"; do
  dyn=$(readelf -d "$f" 2>/dev/null) || continue
  s=$(printf '%s\n' "$dyn" | awk -F'[][]' '/\(SONAME\)/ {print $2}')
  [ -n "$s" ] && bundled+=("$s")
  while IFS= read -r n; do
    [ -n "$n" ] && required+=("$n")
  done < <(printf '%s\n' "$dyn" | awk -F'[][]' '/\(NEEDED\)/ {print $2}')
done

declare -A BUNDLED_SET=() SEEN_EXT=() EXTERNAL=()
for s in ${bundled[@]+"${bundled[@]}"}; do BUNDLED_SET["$s"]=1; done
for n in ${required[@]+"${required[@]}"}; do
  [ -n "${BUNDLED_SET[$n]:-}" ] && continue
  [ -n "${SEEN_EXT[$n]:-}" ] && continue
  SEEN_EXT["$n"]=1; EXTERNAL["$n"]=1
done

# owning_package FILE -> package name (first field of `dpkg -S`), or empty
owning_package() {
  local out
  out=$(dpkg -S "$1" 2>/dev/null | head -n1 | cut -d: -f1)
  printf '%s' "${out%%:*}"
}

# map_soname SONAME -> one package per line that satisfies it
map_soname() {
  local soname=$1 rule s fam target p fam2 t found
  # 1. explicit rules from config (SONAME_RULES="soname|family;...")
  if [ -n "$SONAME_RULES" ]; then
    local oldIFS=$IFS; IFS=';'
    for rule in $SONAME_RULES; do
      IFS=$oldIFS
      s=${rule%%|*}; fam=${rule#*|}
      if [ "$s" = "$soname" ]; then
        case "$fam" in
          runtime) echo "amdrocm-runtime$ROCM_VERSION" ;;
          dnn)     for target in $GPU_TARGETS; do echo "amdrocm-dnn$ROCM_VERSION-$target"; done ;;
          blas)    for target in $GPU_TARGETS; do echo "amdrocm-blas$ROCM_VERSION-$target"; done ;;
          pkg:*)   echo "${fam#pkg:}" ;;
          *) die "bad family in SONAME_RULES: '$fam' (want runtime|dnn|blas|pkg:<name>)" ;;
        esac
        return 0
      fi
      IFS=';'
    done
    IFS=$oldIFS
  fi
  # 2. ask dpkg which installed package owns the file
  local dir
  for dir in "$ROCM_CORE_LIBDIR" "$ROCM_LIBDIR" /usr/lib/x86_64-linux-gnu /usr/lib; do
    [ -e "$dir/$soname" ] || continue
    p=$(owning_package "$dir/$soname")
    if [ -n "$p" ]; then
      # amdrocm-*-host<ver> -> the per-target package (it Depends on the host lib)
      if [[ $p =~ ^amdrocm-([a-z0-9]+)-host ]]; then
        fam2=${BASH_REMATCH[1]}; found=0
        for target in $GPU_TARGETS; do
          t=amdrocm-${fam2}${ROCM_VERSION}-${target}
          if dpkg -s "$t" >/dev/null 2>&1; then echo "$t"; found=1; fi
        done
        [ "$found" -eq 1 ] && return 0
      fi
      echo "$p"
      return 0
    fi
  done
  return 1
}

deps=() rocm_libs=()
declare -A DEP_SEEN=()
for n in $(printf '%s\n' "${!EXTERNAL[@]}" | sort); do
  if ! map_out=$(map_soname "$n"); then
    die "cannot map NEEDED soname '$n' to a package.
       Add an explicit rule to SONAME_RULES in config/build.env, e.g.
       SONAME_RULES='$n|pkg:<package-name>'"
  fi
  is_rocm=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [[ $p == amdrocm* ]] && is_rocm=1
    [ -n "${DEP_SEEN[$p]:-}" ] && continue
    DEP_SEEN["$p"]=1
    v=$(dpkg-query -W -f'${Version}' "$p" 2>/dev/null || true)
    if [ -n "$v" ]; then deps+=("$p (>= $v)"); else deps+=("$p"); fi
  done <<< "$map_out"
  [ "$is_rocm" -eq 1 ] && rocm_libs+=("$n")
done

if [ -n "$EXTRA_DEPENDS" ]; then
  IFS=',' read -ra _x <<< "$EXTRA_DEPENDS"
  for p in "${_x[@]}"; do
    p=${p// /}
    [ -n "$p" ] && deps+=("$p")
  done
fi
mapfile -t deps < <(printf '%s\n' "${deps[@]}" | sort -u)
DEPENDS=$(printf '%s, ' "${deps[@]}"); DEPENDS=${DEPENDS%, }
echo "==> Derived Depends: $DEPENDS"

# =============================================================================
# Render DEBIAN/ files from templates/ (bash string substitution — the
# REQUIRED_LIBS block is multi-line, which sed handles badly)
# =============================================================================
render() { # template out
  local t
  t=$(<"$1")
  t=${t//@PKG_NAME@/$PKG_NAME}
  t=${t//@PKG_VERSION@/$PKG_VERSION}
  t=${t//@MAINTAINER@/$MAINTAINER}
  t=${t//@DEPENDS@/$DEPENDS}
  t=${t//@ORT_VERSION@/$ORT_VERSION}
  t=${t//@MIGRAPHX_VERSION@/$MIGRAPHX_VERSION}
  t=${t//@ROCM_VERSION@/$ROCM_VERSION}
  t=${t//@GPU_TARGETS@/$GPU_TARGETS}
  t=${t//@ROCM_LIB_DIRS@/$ROCM_DIRS}
  t=${t//@REQUIRED_LIBS@/$ROCM_LIBS_BLOCK}
  printf '%s\n' "$t" > "$2"
}

# postinst fragments: the ROCm sonames this stack needs from the system, and
# the candidate dirs that may provide them (most specific first).
ROCM_LIBS_BLOCK=""
for n in $(printf '%s\n' ${rocm_libs[@]+"${rocm_libs[@]}"} | sort -u); do
  ROCM_LIBS_BLOCK+="      $n"$'\n'
done
[ -z "$ROCM_LIBS_BLOCK" ] && ROCM_LIBS_BLOCK="      # (none — no ROCm libs needed)"$'\n'
ROCM_DIRS=""
for d in "$ROCM_CORE_LIBDIR" "$ROCM_LIBDIR"; do ROCM_DIRS+="$d "; done
ROCM_DIRS=${ROCM_DIRS% }

mkdir -p "$DEBIAN"
rm -f "$DEBIAN/control" "$DEBIAN/postinst" "$DEBIAN/postrm" "$DEBIAN/md5sums"
render "$REPO_ROOT/templates/control.in"  "$DEBIAN/control"
render "$REPO_ROOT/templates/postinst.in" "$DEBIAN/postinst"
chmod 0755 "$DEBIAN/postinst"
render "$REPO_ROOT/templates/postrm.in"   "$DEBIAN/postrm"
chmod 0755 "$DEBIAN/postrm"

# =============================================================================
# md5sums + build
# =============================================================================
cd "$PAYLOAD_ROOT"
find usr -type f -print0 | xargs -0 md5sum > DEBIAN/md5sums

mkdir -p "$DIST_DIR"
rm -f "$DEB"
dpkg-deb --build --root-owner-group "$PAYLOAD_ROOT" "$DEB"
sha256sum "$DEB"
echo "DEB DONE -> $DEB"

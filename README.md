# ort-migraphx

Build **ONNX Runtime with the AMD MIGraphX execution provider** on ROCm
(TheRock), and release it as a Debian package that users can install and
uninstall with `apt`.

- Initial target GPU: **gfx1201** (RDNA4 — RX 9070 XT / R9700)
- Initial target ROCm: **10.1** (TheRock `amdrocm` packages)
- Initial target distro: **Ubuntu 26.10** (the build machine's distro)
- The stack is intended for darktable's AI features (any other ONNX
  consumer works too).

Everything (versions, GPU targets, paths) lives in one file:
[`config/build.env`](config/build.env).

## Quick start

```sh
make info            # resolved config + environment check
make                 # full build: deps → ck → rocmlir → migraphx → ort (hours)
make assemble        # stage the built stack into the dpkg payload tree
make deb             # -> dist/ort-migraphx-gfx1201_1.31.0-1_amd64.deb
make test            # smoke test the staged stack (needs the GPU)
```

Resume a failed build at any stage: `make deps|ck|rocmlir|migraphx|ort`
(stages are incremental; an existing checkout/build tree is reused).
`make rocmlir-configure` runs the (fast) configure step of the long stages
without building — useful to validate a toolchain before committing hours.

User-side install/uninstall (secondary goal):

```sh
sudo apt-get install ./dist/ort-migraphx-gfx1201_1.31.0-1_amd64.deb   # or: make install-deb
sudo apt-get purge ort-migraphx-gfx1201                               # or: make uninstall-deb
```

## Requirements

Build machine (no GPU needed to build; the GPU is only needed for `make test`):

- **ROCm 10.1 TheRock SDK** at `/opt/rocm` (from the `amdrocm` debs on
  `repo.radeon.com`; must include `/opt/rocm/llvm/bin/clang`).
- **Ubuntu 26.10** with the system packages:
  `git cmake curl ninja-build ccache gcc make autoconf automake patchelf
  libzstd-dev libsqlite3-dev` and **`clang-22`/`clang++-22`** for the ORT
  stage (see below for why not GCC / SDK clang).
- Network access to github.com / gitlab.com (stages clone pinned sources).

`make info` checks all of the above and prints what is missing.

### Why system clang-22 for the ORT stage

- GCC 15 trips `-Werror=maybe-uninitialized` false positives in libstdc++
  `bits/unicode.h`.
- The TheRock SDK clang (24) trips `-Werror,-Wdeprecated-attributes` on the
  pinned abseil/googletest/onnx/protobuf headers.

Override with `ORT_CC`/`ORT_CXX` if your box differs.

## Repository layout

```
Makefile               entry point (make help for the target list)
build.sh               thin alias: ./build.sh [stage]  (old muscle memory)
config/build.env       single source of truth: targets, ROCm, pins, paths
stages/                the source build, in order (see "Build stages")
  common.sh            shared helpers (logging, checks, resume-safe clones, stamps)
  01-deps.sh .. 05-ort.sh
scripts/
  assemble-stack.sh    build outputs -> dpkg payload tree (RPATH-hardened)
  build-deb.sh         payload tree -> .deb (renders DEBIAN/, derives Depends)
  run-test.sh          smoke test (staged tree or /usr/lib/<pkg>)
  install-deb.sh / uninstall-deb.sh
  info.sh / status.sh  config+env check / build progress
templates/             control.in, postinst.in, postrm.in, package README
patches/               ORT v1.31.0 MIGraphX-EP build fixes (applied by stage 05)
test/                  smoke-test sources + tiny model
build/  package/  dist/  generated (gitignored)
```

## Build stages

| Stage | Builds | Notes |
|---|---|---|
| `01-deps` | rocm-cmake, abseil, nlohmann/json, msgpack-c, eigen, pcre 8.45 | into `build/deps/prefix`; pins per MIGraphX `rocm-10.1` requirements.txt. **No protobuf** — see "Why the dependencies are split" |
| `02-ck` | composable_kernel host / codegen JIT | the CK commit MIGraphX pins; ROCm SDK clang |
| `03-rocmlir` | rocMLIR (Triton/MLIR JIT codegen) | **the long stage (hours)**; fat `librocmcompiler` |
| `04-migraphx` | MIGraphX `rocm-10.1` | against the ROCm SDK + local rocMLIR, for `$GPU_TARGETS` |
| `05-ort` | ONNX Runtime `v1.31.0` (Release, shared) | `--use_migraphx`; auto-applies `patches/`; system clang-22 |

Outputs land under `build/` (`deps/`, `rocmlir/`, `migraphx/`,
`ort/onnxruntime/build/Linux/Release`). `make status` shows which stages are
done (completion stamps) and where artifacts stand.

## Configuration (`config/build.env`)

Every value can be overridden from the environment, e.g.
`GPU_TARGETS="gfx1201 gfx1202" make build`.

| Variable | Default | Meaning |
|---|---|---|
| `GPU_TARGETS` | `gfx1201` | space-separated gfx targets to build for (and depend on) |
| `PKG_NAME` | derived: `ort-migraphx-<targets>` | deb package name; a distinct name per target set keeps per-GPU installs side by side |
| `ROCM_VERSION` | `10.1` | TheRock release; drives `core-<ver>` libdir + `amdrocm-*` Depends names |
| `ROCM_HOME` | `/opt/rocm` | ROCm SDK prefix |
| `ORT_TAG` | `v1.31.0` | ONNX Runtime release (latest with the MIGraphX EP) |
| `MIGRAPHX_TAG` | `rocm-$ROCM_VERSION` | MIGraphX release tag |
| `ROCKMLIR_BRANCH` | `release/rocm-rel-$ROCM_VERSION` | rocMLIR branch |
| `CK_COMMIT`, `ROCM_CMAKE_COMMIT`, `ABSEIL_TAG`, `JSON_TAG`, `MSGPACK_TAG`, `EIGEN_VERSION`, `PCRE_BRANCH` | see file | stage-01/02 source pins |
| `MIN_PROTOBUF` | `3.21` | minimum system protobuf version (build-time floor check) |
| `ORT_CC` / `ORT_CXX` | `clang-22` / `clang++-22` | ORT-stage compiler |
| `JOBS` | `nproc` | parallelism |
| `BUILD_ROOT` | `./build` | all build areas |
| `PKG_REVISION`, `MAINTAINER` | `1`, `kaeru <…>` | deb metadata; bump `PKG_REVISION` when packaging changes |
| `EXTRA_DEPENDS`, `SONAME_RULES` | empty | escape hatches for the Depends generator |

## Packaging & release

`make assemble` assembles the built stack into the dpkg payload tree
(`package/<pkg>/`), mirroring the layout the package installs:

```
usr/lib/<pkg>/lib/        libonnxruntime.so.1.31.0 (+ .so, .so.1), provider libs,
                          MIGraphX (lib/migraphx/lib nesting preserved)
usr/lib/<pkg>/test/       test binaries + tiny model
usr/share/doc/<pkg>/      package README
```

RPATH hardening (what makes the tree relocatable and independent of the
ld cache):

- `libmigraphx_gpu` gets the ROCm libdirs (`/opt/rocm/core-10.1/lib`,
  `/opt/rocm/lib`) appended to its RPATH, so its six ROCm NEEDED entries
  resolve even though TheRock debs don't register `/opt/rocm` with ldconfig.
- the MIGraphX provider lib gets `$ORIGIN:$ORIGIN/migraphx/lib:<rocm dirs>`,
  replacing its stale build-time RUNPATH.

`make deb` then builds the `.deb`:

- renders `DEBIAN/control`, `postinst`, `postrm` from `templates/`;
- **derives `Depends` automatically**: it scans the `NEEDED` entries of every
  staged ELF, drops the sonames the package provides itself, and maps each
  remaining soname to the package that owns it (`dpkg -S`), preferring the
  per-target `amdrocm-dnn/bl<ver>-<target>` packages over their `-host`
  providers. Nothing is hardcoded, so a new ROCm version or GPU target just
  works. (Escape hatches: `EXTRA_DEPENDS`, `SONAME_RULES`.)
- generates `md5sums`, runs `dpkg-deb --build --root-owner-group`, and prints
  the sha256.

Install-time behaviour:

- `postinst` registers the missing ROCm library dirs with ldconfig **only if**
  a required soname is absent from the dynamic linker cache (it prefers
  `/opt/rocm/core-10.1/lib`), writing `/etc/ld.so.conf.d/<pkg>.conf`.
  Non-intrusive on systems where ROCm is already registered.
- `postrm` removes that conf on `purge`.
- the bundled libs already carry the RPATHs above, so the stack works even
  with zero ldconfig registration.

### Why the MIGraphX libraries are bundled (no distro package to depend on)

Checked 2026-10 against the TheRock and Ubuntu (26.10) repos:

- TheRock `amdrocm` 10.1 ships **no MIGraphX at all** — `amdrocm-dnn*` is
  MIOpen/hipDNN only (AMD dropped MIGraphX from TheRock in the 10.x line).
- The Debian ROCm team's `migraphx` 10.0 (Ubuntu universe) is C-ABI
  compatible but CK/hiprtc-JIT-only — **no rocMLIR/Triton stack** — and gfx1201
  is exactly the target where MIGraphX needs the Triton JIT path (which is why
  this build links rocMLIR into `libmigraphx_gpu`). It is also tied to the
  ROCm *10.0* runtime, not TheRock 10.1.
- `migraphx7.2.4` (Ubuntu) has a full Triton JIT for gfx1201 but is the
  ROCm **7.2.4** runtime.

So the vendored MIGraphX (`rocm-10.1`) + amdrocm 10.1 runtime is the only
combination that gives ROCm 10.1 + MIGraphX + gfx1201. Revisit if TheRock ever
ships a `migraphx` package, or a distro build gains the rocMLIR gfx1201 JIT
for ROCm ≥ 10.1 — then the bundled MIGraphX can be dropped in favor of
`Depends: libmigraphx-c3 (>= …)`.

### Why the dependencies are split (system debs vs source pins)

Stage 01 builds rocm-cmake/abseil/json/msgpack/eigen/pcre from source
because **no upstream package provides the pinned version** on Ubuntu 26.10
(TheRock ships no rocm-cmake; Ubuntu has no msgpack/pcre1, and its
abseil/eigen/json are different builds). Everything that *does* come from
upstream debs:

- zstd (`libzstd-dev`) and sqlite (`libsqlite3-dev`) — Ubuntu ships the
  pinned versions;
- **protobuf, build-time and runtime** — `libprotobuf-dev` +
  `protobuf-compiler` (system protoc) are the *only* protobuf in the
  pipeline. The staged `libmigraphx_onnx.so` NEEDs the system
  `libprotobuf.so.32` (Ubuntu `libprotobuf32t64`), and the Depends generator
  picks it up;
- the whole ROCm runtime on the target is the `amdrocm` deb set (in `Depends`).

Why no source-built protobuf? MIGraphX's CMake runs
`find_package(protobuf QUIET CONFIG)` before falling back to the system
package. A protobuf CMake config in the deps prefix (e.g. a source-built
protobuf v30) makes it **statically link its own protobuf** instead of the
system one. That puts a second protobuf runtime in the process alongside the
one ORT bundles — and the MIGraphX EP then segfaults in `Compile`. The
validated stack always used the system shared protobuf, so the deps prefix
deliberately contains no protobuf (and stage 01 verifies the system version
is at least `MIN_PROTOBUF`).

## Using it from darktable

darktable keeps its bundled CPU ONNX Runtime and only switches to this GPU
stack via a library path override:

```ini
# darktaberc
plugins/ai/ort_library_path = /usr/lib/ort-migraphx-gfx1201/lib/libonnxruntime.so.1.31.0
```

```sh
# or environment
export DT_ORT_LIBRARY=/usr/lib/ort-migraphx-gfx1201/lib/libonnxruntime.so.1.31.0
```

The C API is additive: `GetApi()` of any lower version works, so darktable
built against ORT 1.24 (API v24) links fine against 1.31.

## Smoke test

`make test` (staged tree) or `make test-installed` (after install) runs:

1. `test_darktable_path` — dlopen the versioned lib, request C API v24
   (darktable's version), check the MIGraphX provider is registered;
2. `test_ort_mgx` — create a session with the MIGraphX EP (device 0), run a
   4-float model, compare against the expected output.

Needs the AMD GPU + ROCm. The first inference of each model is slow
(MIGraphX Triton JIT for gfx1201); results are cached under
`~/.cache/migraphx`.

## Bumping versions (future ROCm / ORT / MIGraphX)

1. `ROCM_VERSION=10.2` (or whatever). This cascades: `core-10.2` libdir,
   `amdrocm-*-10.2` Depends names, `MIGRAPHX_TAG=rocm-10.2`,
   `ROCKMLIR_BRANCH=release/rocm-rel-10.2`.
2. Re-read the new MIGraphX tag's `requirements.txt` and update
   `CK_COMMIT` + the stage-01 pins if they moved.
3. `ORT_TAG` — bump when a new ORT release keeps the MIGraphX EP; re-validate
   the `patches/` fixup (it is a 3-line cosmetic build fix; re-generate it if
   the files changed).
4. Full rebuild; `make info` and `make deb` will surface any mapping gaps
   (the Depends generator fails loudly on a soname it cannot map — extend
   `SONAME_RULES` if the naming scheme changed).

## Adding a GPU target

`GPU_TARGETS="gfx1201 gfx1202" make build …` produces one stack that covers
both targets; the package name becomes `ort-migraphx-gfx1201-gfx1202` and the
Depends gain the `amdrocm-dnn10.1-gfx1202` / `amdrocm-blas10.1-gfx1202`
packages automatically. Alternatively build per-target packages (separate
`GPU_TARGETS` + fresh `build/` per target) so users pick the package matching
their GPU — they install side by side without file clashes, since each
package uses its own `/usr/lib/<pkg>/` tree.

## Migrating from the original repo (ort-migraphx-initial)

The original package installed to `/usr/lib/ort-migraphx/`; this one
installs to `/usr/lib/<pkg>/` (per-target, so multiple targets can be
installed side by side). The package *name* is unchanged
(`ort-migraphx-gfx1201`), so on a machine with the old install:

```sh
sudo apt-get install ./dist/ort-migraphx-gfx1201_1.31.0-1_amd64.deb
```

upgrades in place — dpkg removes the old `/usr/lib/ort-migraphx/` tree (the
old version's files) and installs the new one. After that, point darktable's
`plugins/ai/ort_library_path` (or `DT_ORT_LIBRARY`) at the **new** path
`/usr/lib/ort-migraphx-gfx1201/lib/libonnxruntime.so.1.31.0`.

## Provenance

Refactored from `~/src/ort-migraphx-initial` (the original, proven build +
packaging). The build recipes (stage order, cmake flags, pins, RPATH
hardening, maintainer-script logic) are preserved from that proven tree; the
packaging (control/Depends/maintainer scripts) is now generated at build
time instead of committed, and the payload installs to a per-package
directory. The original's committed prebuilt payload was used to validate
this project's packaging pipeline end-to-end (deb build → GPU smoke test),
after which a fresh `make build` regenerates everything from source.

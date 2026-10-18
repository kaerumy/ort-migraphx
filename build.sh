#!/bin/bash
# Thin alias for the Makefile (muscle memory from the original repo layout):
#   ./build.sh            # full build: deps -> ck -> rocmlir -> migraphx -> ort
#   ./build.sh <stage>    # resume from a stage: deps|ck|rocmlir|migraphx|ort
# Everything else: see `make help`.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
exec make -C "$HERE" "${1:-build}"

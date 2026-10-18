# ort-migraphx — top-level entry point. See README.md.
#
#   make                 full source build: deps → ck → rocmlir → migraphx → ort
#   make deps|ck|rocmlir|migraphx|ort   run a single stage (resume-safe)
#   make rocmlir-configure|migraphx-configure   configure-only sanity check
#   make assemble        assemble the built stack into the dpkg payload tree
#   make deb             build the .deb into dist/
#   make test            smoke test the staged stack (needs the AMD GPU)
#   make test-installed  smoke test /usr/lib/<multiarch>/<pkg> (after make install-deb)
#   make install-deb / uninstall-deb   install / purge via the deb
#   make info | status   resolved config / build progress
#   make clean | distclean
#
# Thin alias for `./build.sh [stage]` from the original repo layout.

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Load the resolved configuration (config/build.env) — one lookup per var.
MV := bash $(REPO_ROOT)/scripts/make-vars.sh
PKG_NAME         := $(shell $(MV) PKG_NAME)
PKG_VERSION      := $(shell $(MV) PKG_VERSION)
ORT_VERSION      := $(shell $(MV) ORT_VERSION)
MIGRAPHX_VERSION := $(shell $(MV) MIGRAPHX_VERSION)
ROCM_VERSION     := $(shell $(MV) ROCM_VERSION)
GPU_TARGETS      := $(shell $(MV) GPU_TARGETS)

.DEFAULT_GOAL := build
.PHONY: help build deps ck rocmlir rocmlir-configure migraphx migraphx-configure \
        ort assemble deb test test-installed install-deb uninstall-deb \
        info status clean distclean

help:
	@echo "ort-migraphx — $(PKG_NAME) $(PKG_VERSION) (ROCm $(ROCM_VERSION), targets: $(GPU_TARGETS))"
	@echo
	@echo "Build (hours on first run; stages are resume-safe):"
	@echo "  make / make build          all stages: deps → ck → rocmlir → migraphx → ort"
	@echo "  make deps|ck|rocmlir|...   a single stage"
	@echo "  make rocmlir-configure     configure-only sanity check (also migraphx-configure)"
	@echo
	@echo "Package & release:"
	@echo "  make assemble              stage the built stack into package/ (payload tree)"
	@echo "  make deb                   build the .deb into dist/"
	@echo
	@echo "Verify & install (needs the AMD GPU for the real test):"
	@echo "  make test                  smoke test the staged stack"
	@echo "  make install-deb           install the .deb (apt, resolves Depends)"
	@echo "  make test-installed        smoke test the installed /usr/lib/<multiarch>/$(PKG_NAME)"
	@echo "  make uninstall-deb         purge the package"
	@echo
	@echo "Ops:"
	@echo "  make info | status | clean | distclean"

build: deps ck rocmlir migraphx ort

deps:
	@echo "#### stage 01-deps ####"
	bash $(REPO_ROOT)/stages/01-deps.sh

ck:
	@echo "#### stage 02-ck ####"
	bash $(REPO_ROOT)/stages/02-ck.sh

rocmlir:
	@echo "#### stage 03-rocmlir ####"
	bash $(REPO_ROOT)/stages/03-rocmlir.sh

rocmlir-configure:
	@echo "#### stage 03-rocmlir (configure only) ####"
	bash $(REPO_ROOT)/stages/03-rocmlir.sh configure

migraphx:
	@echo "#### stage 04-migraphx ####"
	bash $(REPO_ROOT)/stages/04-migraphx.sh

migraphx-configure:
	@echo "#### stage 04-migraphx (configure only) ####"
	bash $(REPO_ROOT)/stages/04-migraphx.sh configure

ort:
	@echo "#### stage 05-ort ####"
	bash $(REPO_ROOT)/stages/05-ort.sh

assemble:
	bash $(REPO_ROOT)/scripts/assemble-stack.sh

deb:
	bash $(REPO_ROOT)/scripts/build-deb.sh

test:
	bash $(REPO_ROOT)/scripts/run-test.sh

test-installed:
	bash $(REPO_ROOT)/scripts/run-test.sh --installed

install-deb:
	bash $(REPO_ROOT)/scripts/install-deb.sh

uninstall-deb:
	bash $(REPO_ROOT)/scripts/uninstall-deb.sh

info:
	bash $(REPO_ROOT)/scripts/info.sh

status:
	bash $(REPO_ROOT)/scripts/status.sh

clean:
	rm -rf $(REPO_ROOT)/package $(REPO_ROOT)/dist
	@echo "removed package/ and dist/ (build trees kept)"

distclean: clean
	rm -rf $(REPO_ROOT)/build
	@echo "removed build/ (sources, build trees, prefixes)"

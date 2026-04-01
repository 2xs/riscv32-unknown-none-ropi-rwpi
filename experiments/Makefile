.DEFAULT_GOAL := help

ROOT := $(abspath $(CURDIR)/..)
EXPERIMENTS := $(ROOT)/experiments
CLASSIC := $(EXPERIMENTS)/classic
BLOB := $(EXPERIMENTS)/blob
RUST := $(EXPERIMENTS)/rust
CPP := $(EXPERIMENTS)/cpp
QEMU ?= /opt/homebrew/bin/qemu-system-riscv32
DATA_BASES ?= 0x80010000 0x80024000

.PHONY: help build run \
	tools \
	classic classic-smoke classic-matrix \
	cpp \
	rust rust-dyn rust-dyn-neg rust-unknown \
	blob blob-matrix \
	neg-text neg-tls \
	clean

help:
	@printf '%s\n' \
		'RWPI experiments' \
		'' \
		'Targets:' \
		'  make build         Build the LLVM tools used by the experiments' \
		'  make run           Run the smoke test, classic campaign, and blob campaigns' \
		'  make classic       Run the full ELF-based regression campaign (includes classic-matrix)' \
		'  make classic-smoke Run the semihosting startup smoke test' \
		'  make classic-matrix Run the ELF relocation matrix under QEMU' \
		'  make cpp           Check the C++ unknown-segment examples through final link' \
		'  make rust          Run the minimal Rust -> llc -> RWPI QEMU demo' \
		'  make rust-dyn      Run the Rust &dyn Trait dispatch experiment' \
		'  make rust-dyn-neg  Alias for make rust-dyn' \
		'  make rust-unknown  Show that current Rust lowering does not expose this pattern as an ambiguous external-constant case' \
		'  make blob          Run the house blob smoke test' \
		'  make blob-matrix   Run the house blob relocation matrix' \
		'  make neg-text      Check that relocated text is rejected cleanly' \
		'  make neg-tls       Check that TLS payloads are rejected cleanly' \
		'  make clean         Remove small generated artefacts from the workspace' \
		'' \
		'Variables:' \
		'  QEMU=$(QEMU)' \
		'  DATA_BASES=$(DATA_BASES)'

build: tools

tools:
	@cd $(ROOT) && ./build-llvm.sh

run: classic-smoke classic blob blob-matrix neg-text neg-tls

classic:
	@cd $(ROOT) && QEMU="$(QEMU)" bash "$(CLASSIC)/run_all_rwpi_checks.sh"

classic-smoke:
	@cd $(ROOT) && QEMU="$(QEMU)" bash "$(CLASSIC)/run_hello_qemu.sh"

classic-matrix:
	@cd $(ROOT) && QEMU="$(QEMU)" bash "$(CLASSIC)/run_reloc_matrix_qemu.sh"

cpp:
	@cd $(ROOT) && bash "$(CPP)/run_cpp_ambiguous_checks.sh"

rust:
	@cd $(ROOT) && QEMU="$(QEMU)" bash "$(RUST)/run_rust_qemu.sh"

rust-dyn:
	@cd $(ROOT) && QEMU="$(QEMU)" bash "$(RUST)/run_rust_dyn_negative.sh"

rust-dyn-neg: rust-dyn

rust-unknown:
	@cd $(ROOT) && bash "$(RUST)/run_rust_unknown_segment.sh"

blob:
	@cd $(ROOT) && QEMU="$(QEMU)" DATA_BASES="$(DATA_BASES)" bash "$(BLOB)/run_blob_qemu.sh"

blob-matrix:
	@cd $(ROOT) && QEMU="$(QEMU)" DATA_BASES="$(DATA_BASES)" bash "$(BLOB)/run_blob_matrix_qemu.sh"

neg-text:
	@cd $(ROOT) && bash "$(BLOB)/run_blob_text_negative_qemu.sh"

neg-tls:
	@cd $(ROOT) && bash "$(BLOB)/run_blob_tls_negative.sh"

clean:
	@rm -rf $(CURDIR)/blob/__pycache__
	@rm -f $(ROOT)/hello-crt0.o $(ROOT)/hello-semihost.o $(ROOT)/hello-semihost.elf $(ROOT)/example.elf

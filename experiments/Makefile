.DEFAULT_GOAL := help

ROOT := $(abspath $(CURDIR)/..)
EXPERIMENTS := $(ROOT)/experiments
CLASSIC := $(EXPERIMENTS)/classic
BLOB := $(EXPERIMENTS)/blob
QEMU ?= /opt/homebrew/bin/qemu-system-riscv32
DATA_BASES ?= 0x80010000 0x80024000

.PHONY: help build run \
	tools \
	classic classic-smoke classic-matrix \
	blob blob-matrix \
	neg-text neg-tls \
	clean

help:
	@printf '%s\n' \
		'RWPI experiments' \
		'' \
		'Targets:' \
		'  make build         Build the LLVM tools used by the experiments' \
		'  make run           Run the main classic and blob test campaigns' \
		'  make classic       Run the existing ELF-based regression campaign' \
		'  make classic-smoke Run the semihosting startup smoke test' \
		'  make classic-matrix Run the ELF relocation matrix under QEMU' \
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

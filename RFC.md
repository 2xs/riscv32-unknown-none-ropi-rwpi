Title: RFC: RISC-V ropi-rwpi profile with gp-based runtime data addressing

I would like to propose an experimental RISC-V code generation profile for
bare-metal split flash/RAM systems, tentatively named
`riscv32-unknown-none-ropi-rwpi`.

## Summary

The target use case is an execution model where:
- `.text` stays executable in flash without any runtime relocation,
- writable data is relocated into RAM at startup,
- a dedicated base register (`gp`) points to the runtime data area,
- all runtime data accesses are lowered relative to that base register,
- function/control-flow addresses may remain PC-relative as usual.

This is different from the current standard RISC-V `gp` relaxation model. The
goal is not linker relaxation for small data, but an ABI/profile where `gp` is
a stable runtime data base, in the same general direction as RWPI-style code
generation on other architectures.

## Motivation

Some embedded systems have disjoint executable and writable address spaces, for
example code in flash/XIP and writable data in RAM. On such systems, an MPU may
also be used to isolate multiple applications from one another, with separate
flash and RAM regions per application.

In that environment, it is useful to support an ABI where:
- code is relocatable within executable storage,
- writable data is relocatable independently within RAM,
- code does not require runtime relocation in `.text`,
- runtime data accesses go through a dedicated base register initialized by the
  startup/runtime.

This split code/data relocation model is already practical on ARM. Existing ARM
toolchains can support a similar setup by using PIC code generation together
with a dedicated data base register (`r10` / `sl`), so that flash-resident code
can remain executable as-is while writable data is relocated separately in RAM.
In Clang/LLVM terms, representative options are:

`-fPIC -ffreestanding -msingle-pic-base -mpic-register=sl -mno-pic-data-is-text-relative`

This model maps well to embedded MPU-based isolation because it avoids runtime
patching of `.text` while still allowing each application's writable state to
be placed independently in RAM.

RISC-V appears to have the architectural building blocks for a similar model.
In particular, `gp` is a natural candidate for a stable runtime data base
register. However, the current standard RISC-V lowering paths favor
PC-relative, GOT-relative, and small-data relaxation schemes that do not
directly provide the same split flash/RAM ABI contract.

The goal of this proposal is to explore an experimental RISC-V `ropi-rwpi`
profile where writable globals are addressed relative to a stable runtime base
(`gp`), while code remains independently relocatable and does not require
runtime relocation in `.text`.

## Proposal

The proposed initial scope is intentionally small:
- RV32 only,
- no dynamic linking / PLT,
- no TLS,
- no runtime relocation in `.text`,
- first milestone limited to lowering simple global data accesses via `gp`.

The current prototype scope is also intentionally narrow at the instruction
selection level.

It only covers direct `gp`-relative `lo12` forms. In theory, those forms use a
signed 12-bit immediate. In the current prototype, however, `__rwpi_anchor` is
placed at the beginning of the writable RWPI region and globals are addressed
as positive offsets from that anchor. This means the usable direct-addressing
range is currently about 2 KiB of RWPI globals, not the full 4 KiB signed
window.

This is a prototype limitation, not a fundamental ABI limitation. Larger RWPI
regions would require additional lowering patterns for out-of-range accesses.

The intent is to start with an experimental subtarget/profile and validate the
basic ABI/codegen contract before discussing whether a target triple or a more
formal ABI surface makes sense.

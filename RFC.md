Title: RFC: RISC-V ropi-rwpi profile with gp-based runtime data addressing

I would like to propose an experimental RISC-V code generation profile for
bare-metal split flash/RAM systems, tentatively named
`riscv32-unknown-none-ropi-rwpi`.

## Summary

The target use case is an execution model where:
- `.text` stays executable in flash without any runtime relocation,
- relocatable data is moved into its runtime data area at startup,
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
- relocatable data is relocatable independently within RAM,
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

## RWPI/ROPI discipline

The profile needs a stricter classification rule than "mutable globals are
RWPI".

The important distinction is between:

- true ROPI data
- RWPI data
- read-only data whose contents still require runtime relocation

The proposed discipline is:

1. True ROPI data

- read-only after link
- contains no address value that must be fixed up at runtime
- may remain in flash alongside code-side read-only data

2. RWPI data

- writable at runtime
- relocated in the runtime data image
- addressed relative to `gp`

3. RO-reloc data

- logically read-only to the program
- but its initializer contains address-bearing values that must be fixed up
  when the image is placed at runtime
- is therefore not true ROPI, even if it originates from source-level `const`
- is copied into a dedicated runtime RAM read-only region
- is addressed relative to `gp`, like RWPI data
- may be made read-only by the runtime after relocation has completed

This third class matters because not every read-only object is safe to leave in
flash unchanged.

Examples include:

- read-only pointers
- read-only arrays of pointers
- read-only aggregates containing function or data addresses

Under this discipline:

- writable globals lower as RWPI
- read-only globals with no runtime-relocatable address in their initializer
  remain true ROPI
- read-only globals with any runtime-relocatable address in their initializer
  are classified as RO-reloc

The intended runtime memory contract is therefore:

- true ROPI stays in flash / execute-in-place storage
- RWPI is copied or initialized into writable RAM
- RO-reloc is copied into a distinct RAM read-only region, relocated there, and
  then left read-only for the program

This implies that RO-reloc and RWPI share the same `gp`-relative addressing
discipline in generated code, but not necessarily the same final memory
protection or linker output region.

The current prototype may temporarily materialize RO-reloc in a generic
relocatable data section such as `.data.rel.ro`, but the ABI intent is a
distinct `ramro`-style output region in the final image.

## Proposal

The proposed initial scope is intentionally small:
- RV32 only,
- no dynamic linking / PLT,
- no TLS,
- no runtime relocation in `.text`,
- first milestone limited to lowering simple global data accesses via `gp`.

The same initial scope also implies:

- unsupported symbol classes should be rejected or left on existing lowering
  paths explicitly
- no object that requires runtime relocation of its contents should be treated
  as true ROPI by accident

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

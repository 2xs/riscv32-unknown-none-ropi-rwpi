Title: RFC: RISC-V ropi-rwpi code model with gp-based runtime data addressing

I would like to propose an experimental RISC-V code model / execution model
for bare-metal split flash/RAM systems.

The repository and prototype branch still use the shorthand
`riscv32-unknown-none-ropi-rwpi`, but that should now be read as a prototype
label, not as a claim that the right long-term upstream surface is a new
target triple.

## Summary

The target use case is an execution model where:
- `.text` stays executable in flash without any runtime relocation,
- relocatable data is moved into its runtime data area at startup,
- a dedicated base register (`gp`) points to the runtime data area,
- all runtime data accesses are lowered relative to that base register,
- function/control-flow addresses may remain PC-relative as usual.

This is different from the current standard RISC-V `gp` relaxation model. The
goal is not linker relaxation for small data, but a code model / execution
model where `gp` is a stable runtime data base, in the same general direction
as RWPI-style code generation on other architectures.

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
code model where writable globals are addressed relative to a stable runtime
base (`gp`), while code remains independently relocatable and does not require
runtime relocation in `.text`.

This direction is close in spirit to the earlier RISC-V ePIC proposal:

- code-side objects are reached through a PC-relative discipline,
- data-side objects are reached through `gp`,
- and data that still requires load-time rewriting must not remain in the
  code segment even if it is logically read-only afterwards.

The current prototype in this repository should therefore not be read as an
alternative universe to ePIC, but rather as a bare-metal-oriented exploration
of the same general execution-model family, with more emphasis on:

- startup/runtime construction of the final image,
- explicit runtime data classes (`dataro`, `dataramro`, `datarw`),
- and end-to-end validation through linker scripts, `crt0`, and QEMU.

## RWPI/ROPI discipline

The execution model needs a stricter classification rule than "mutable globals are
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

The intended ABI section naming for those classes is:

- `dataro` for true ROPI data
- `dataramro` for RO-reloc data
- `.rela.dataramro` for the runtime relocation table applied to `dataramro`
- `datarw` for writable runtime data
- `datarw.bss` for zero-initialized writable runtime data

This implies that RO-reloc and RWPI share the same `gp`-relative addressing
discipline in generated code, but not necessarily the same final memory
protection or linker output region.

This is also the point where the current prototype most clearly overlaps with
ePIC. In ePIC terms, pointer-bearing read-only objects that still require
load-time relocation do not remain in the code segment; they move to the data
side so that the loader may rewrite them before execution begins. The current
prototype makes that same distinction explicit under the `RO-reloc` /
`dataramro` naming.

The current prototype still uses some transitional writable-data section names
such as `.data` and `.bss`, but RO-reloc data now already uses `.dataramro`.
The intended ABI contract remains the `data*` naming above.

For the relocation table associated with `dataramro`, the current direction is
to keep the standard ELF relocation-section naming and format. In other words,
the runtime relocation table is `.rela.dataramro`, with ordinary `SHT_RELA`
entries retained in the output when linking with `--emit-relocs`.

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

The current prototype scope is still intentionally narrow at the instruction
selection level, but it is no longer limited to direct `gp`-relative `lo12`
forms.

The current compiler lowering systematically materializes RWPI addresses with a
full `gp`-relative sequence:

- `lui %rwpi_hi(symbol)`
- `add ..., gp, ...`
- `addi/load/store ..., %rwpi_lo(symbol)`

This is an intentional prototype choice.

The compiler does not try to predict whether a given symbol will end up within a
signed 12-bit offset from `__gp_data_start` after link. Instead, it always emits
the robust full-address form for RWPI-generated code. This avoids making code
generation depend on final linker placement.

The linker may then optimize that full form back into a short `gp + imm12`
form when the final linked displacement is in range and the emitted pattern is
recognized as relaxable. This keeps the compiler rule simple while still
recovering compact code where layout permits it.

As a consequence:

- out-of-range RWPI accesses are supported by the compiler and linker path
- the compiler does not depend on final linker placement
- `lld` can recover the short `gp + lo12` form automatically for in-range
  cases
- the short form also remains available when written explicitly, for example
  in hand-written assembly

The intent is to start with an experimental code-model-style lowering mode and
validate the basic ABI/codegen contract before discussing the long-term
frontend surface.

Based on later feedback, the most plausible upstream-facing direction now
looks like:

- a new code model (for example through `-mcmodel=` or an equivalent backend
  selection surface),
- plus explicit object marking so the linker can reject incompatible mixtures,
- rather than a new target triple or an extension to `-mabi`.

One important open point, however, is that the current prototype does not yet
cover the full "unknown segment" case as explicitly as ePIC does. In other
words, the prototype already validates the `gp`-relative runtime-data model and
the startup/link/runtime contract, but it does not yet claim to solve every
case where the compiler cannot know early enough whether a symbol will finally
belong to the code-side or data-side addressing discipline.

## Open issue: unknown segment

The most important remaining design issue is the "unknown segment" case.

The current prototype already covers cases where the toolchain can classify
objects early enough into:

- true ROPI / code-side read-only data,
- writable runtime data,
- read-only but load-time-relocatable runtime data.

However, there are still source-language patterns where the compiler may not be
able to know soon enough whether the final object placement should follow the
code-side PC-relative discipline or the data-side `gp`-relative discipline.

The ePIC proposal addresses that problem explicitly by introducing
link-time-rewrite relocations for ambiguous address-generation sequences.

That is a useful reference point for this work.

In practice, this implies an important implementation rule: the ambiguous case
should not start from a short low-12-only form. If the compiler or assembler
chooses a short form too early, the linker may later discover that the symbol
really belongs to the other side of the split and needs a full address
materialization instead. That would require growing code at link time, which is
not what relaxation machinery is designed for.

The more robust strategy is therefore:

- always start from one canonical long ambiguous form for data references,
- make that form valid for either PC-relative or `gp`-relative rewriting,
- let the linker choose the final side once placement is known,
- then let the linker shrink the chosen form when the final displacement makes
  that possible.

In short:

- compiler/assembler: emit a long ambiguous form,
- linker: choose, rewrite, and shrink if possible.

The current prototype should therefore be understood as:

- a validation of the execution model,
- a validation of the runtime-data classification rule,
- a validation of the startup/link/runtime contract,
- but not yet a full solution to every "unknown segment" case.

Any future psABI proposal derived from this work will likely need to address
that question explicitly, either:

- by adopting an ePIC-like link-time rewrite strategy,
- or by defining a different but equally explicit late classification mechanism.

# RISC-V `riscv32-unknown-none-ropi-rwpi` Hacking Plan

## Goal

Build a minimal compilation profile for RISC-V that matches the FAE execution
model:

- `.text` / `.rom` executes from flash
- writable runtime data executes from RAM
- `gp` is the runtime base for relocated writable data
- no runtime relocation or instruction patching in `.text`
- runtime relocation is restricted to writable cells

This is not ordinary ELF PIC.

This is a dedicated split flash/RAM ABI profile.

## Toolchain chain

The full chain we eventually want is:

1. Clang frontend
2. LLVM IR
3. RISC-V backend lowering
4. `llc` / integrated codegen
5. `lld` or GNU linker with a dedicated linker script
6. `rustc` reusing the same LLVM backend behavior
7. `build_fae` validating the emitted ELF profile

## Minimal strategy

Do not start by creating a completely new backend.

Start by teaching the existing RISC-V backend a new profile:

- target name: `riscv32-unknown-none-ropi-rwpi`
- conceptual ABI rule: all runtime data accesses go through `gp`

The first objective is not completeness.

The first objective is to make one simple global data access lower to:

- `gp + offset`

instead of:

- `HI20/LO12`
- `PCREL_HI20/LO12`
- standard GOT recovery

## Phase 1: LLVM-only proof

### Deliverable

One tiny C input compiled by Clang to assembly where:

- `gp` is reserved
- a mutable global is accessed through `gp + offset`
- `.text` contains no runtime data address formation through PC-relative
  sequences

### Likely areas to inspect in `llvm-project`

Target backend:

- `llvm/lib/Target/RISCV/`

Key files to inspect first:

- `llvm/lib/Target/RISCV/RISCVISelLowering.cpp`
- `llvm/lib/Target/RISCV/RISCVISelLowering.h`
- `llvm/lib/Target/RISCV/RISCVInstrInfo.td`
- `llvm/lib/Target/RISCV/RISCVSubtarget.{cpp,h}`
- `llvm/lib/Target/RISCV/RISCVRegisterInfo.{cpp,h}`
- `llvm/lib/Target/RISCV/RISCVCallingConv.td`

Driver/target parsing:

- `clang/lib/Basic/Targets/RISCV.cpp`
- `clang/lib/Driver/ToolChains/Clang.cpp`

### First backend changes

1. Add a subtarget feature or ABI knob for the new profile.
Suggested temporary knob:

- `+fae-gp-data`

2. Reserve `gp` for the profile.

3. Lower selected `GlobalAddress` nodes to a dedicated form meaning:

- runtime data base register is `gp`
- symbol is represented as an offset in the writable runtime image

4. For the first prototype, support only:

- mutable globals
- initialized writable globals

5. Forbid or reject for now:

- TLS
- dynamic linking
- standard GOT/PLT
- exotic code models

## Phase 2: Clang-facing profile

### Deliverable

A Clang invocation like:

```bash
clang --target=riscv32-unknown-none-ropi-rwpi ...
```

that reaches the new lowering path.

### Work items

1. Decide how the new profile is exposed:

- a true new triple spelling
- or existing triple + feature/ABI flag

For fast iteration, start with:

- existing RISC-V triple
- new backend feature / ABI flag

Then add the final spelling once behavior works.

2. Thread the choice through Clang target feature handling.

3. Add a minimal test that checks emitted assembly.

## Phase 3: Link-time shape

### Deliverable

A linked ELF with:

- `.rom`
- `.rom.ram`
- `.ram`
- no forbidden relocations in `.text`

### Work items

1. Provide a dedicated linker script.

2. Ensure emitted writable symbols are organized around the runtime data base
expected by `gp`.

3. Decide the first out-of-range policy for globals beyond direct `gp` window:

- simplest first option: reject at link/build validation time
- next option: multi-instruction sequence from `gp`

## Phase 4: Broaden supported access kinds

After mutable globals work, extend in this order:

1. pointer-valued globals
2. function-pointer globals
3. constant data referenced via writable pointer cells
4. larger data models / out-of-range handling

This order matches the pain points found in `try-risc-v`.

## Phase 5: Rust integration

### Deliverable

`rustc` can target the same profile and trigger the same LLVM lowering.

### Likely areas in the Rust tree

- `rust/compiler/rustc_target/src/spec/`
- `rust/compiler/rustc_codegen_llvm/`

### Work items

1. Add a new target spec for:

- `riscv32-unknown-none-ropi-rwpi`

2. Pass the backend feature / ABI choice to LLVM.

3. Keep the Rust-side target spec minimal:

- no host OS
- no dynamic linking
- explicit relocation model expectations

## Phase 6: FAE validation

Once codegen exists, update the FAE tooling so the profile is enforceable.

### `build_fae` should validate

- no runtime-data-targeting relocations in `.text`
- only allowed relocations in writable sections
- expected section layout
- expected machine / ABI profile

## Immediate next steps

These are the first practical actions to take in order.

1. Add a short backend note describing the target contract.

2. Inspect how `GlobalAddress` is currently lowered in the RISC-V backend.

3. Add a temporary subtarget feature for `fae-gp-data`.

4. Make one mutable global load/store lower to `gp + offset`.

5. Add one LLVM test for the resulting assembly.

6. Only then expose the profile through Clang.

## Success criteria for the first milestone

The first milestone is reached when all of the following are true:

- a tiny C file compiles through Clang/LLVM
- assembly uses `gp + offset` for writable global access
- no `HI20/LO12` or `PCREL_*` is used for runtime writable globals
- the linked ELF keeps `.text` free of runtime data relocation shapes

That milestone is enough to prove the backend direction is viable.

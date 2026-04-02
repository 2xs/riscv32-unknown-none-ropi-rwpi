# Bare-Metal GP-Relative Code Model Cookbook

This note is a short implementation recipe for reproducing the same execution
model on another LLVM target.

## 1. Define the execution model

Goal:

- keep `.text` PC-relative and free of runtime patching,
- copy writable runtime data to RAM at startup,
- use one stable data-base register (`gp` on RISC-V),
- split runtime data into:
  - `dataro`: true ROM data,
  - `dataramro`: read-only-after-init data that still carries addresses,
  - `datarw`: writable runtime data.

For unknown-segment cases, always emit one long ambiguous form and let the
linker choose the final addressing mode.

## 2. Backend / IR-to-asm lowering (`llc`, `clang`)

### What to add

- one classification helper for:
  - certainly-code symbols,
  - certainly-data symbols,
  - ambiguous symbols.
- one canonical long GP-relative form for data,
- one canonical long ambiguous form for "PC or GP, linker decides later".

### Where to hook it

RISC-V example:

- classification:
  [RISCVRelocatableData.cpp](llvm-project/llvm/lib/Target/RISCV/RISCVRelocatableData.cpp)
- SDAG lowering:
  [RISCVISelLowering.cpp](llvm-project/llvm/lib/Target/RISCV/RISCVISelLowering.cpp)
- GlobalISel lowering:
  [RISCVInstructionSelector.cpp](llvm-project/llvm/lib/Target/RISCV/GISel/RISCVInstructionSelector.cpp)
- asm operand printing:
  [RISCVAsmPrinter.cpp](llvm-project/llvm/lib/Target/RISCV/RISCVAsmPrinter.cpp)

### Code idea

1. In `lowerGlobalAddress`, classify the global.
2. If it is certainly data-side, emit the normal GP-relative long form.
3. If it is ambiguous, emit one long ambiguous form:
   `HI(sym) + base-register-add + LO(sym)`.
4. If it is certainly code-side, keep normal PC-relative lowering.

The key rule is: never emit a short form for an ambiguous symbol.

## 3. Assembler / MC layer (`llvm-mc`)

### What to add

- new target-specific relocation specifiers for the ambiguous form,
- new fixups,
- ELF relocation numbers for these fixups.

### Where to hook it

RISC-V example:

- relocation kinds:
  [RISCVMCAsmInfo.h](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVMCAsmInfo.h)
- MO flags:
  [RISCVBaseInfo.h](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVBaseInfo.h)
- parser:
  [RISCVAsmParser.cpp](llvm-project/llvm/lib/Target/RISCV/AsmParser/RISCVAsmParser.cpp)
- MC expression names:
  [RISCVMCExpr.cpp](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVMCExpr.cpp)
- fixups:
  [RISCVFixupKinds.h](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVFixupKinds.h)
- code emitter:
  [RISCVMCCodeEmitter.cpp](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVMCCodeEmitter.cpp)
- asm backend:
  [RISCVAsmBackend.cpp](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVAsmBackend.cpp)
- ELF relocation mapping:
  [RISCVELFObjectWriter.cpp](llvm-project/llvm/lib/Target/RISCV/MCTargetDesc/RISCVELFObjectWriter.cpp)

### Code idea

Define one `HI` and one `LO` relocation family for the ambiguous form. The MC
layer should do nothing clever: it only needs to preserve the canonical long
sequence until link time.

## 4. Linker (`lld`)

### What to add

- final section classification: "data-side" vs "code-side",
- pattern matching for the canonical ambiguous sequence,
- link-time rewrite:
  - keep long GP-relative,
  - shrink to short GP-relative if possible,
  - or rewrite to PC-relative if the symbol ended in code/ROM.

### Where to hook it

RISC-V example:

- relocation handling and relaxation:
  [RISCV.cpp](llvm-project/lld/ELF/Arch/RISCV.cpp)
- make retained relocation sections runtime-visible:
  [OutputSections.cpp](llvm-project/lld/ELF/OutputSections.cpp)
  and
  [LinkerScript.cpp](llvm-project/lld/ELF/LinkerScript.cpp)

### Code idea

1. Detect the ambiguous `HI + add-base + LO` pattern.
2. Look at the final output section of the referenced symbol.
3. If the symbol is data-side:
   - keep the long GP-relative form,
   - or shrink to `base + imm12` if in range.
4. If the symbol is code-side:
   - rewrite the same sequence into a PC-relative form.

This step is the whole point of the design.

## 5. Runtime / linker script

### What to add

- linker symbols for:
  - text bounds,
  - linked data-window bounds,
  - load addresses,
  - retained relocation-table bounds.
- startup code to:
  - copy `dataramro`,
  - copy `datarw`,
  - zero `datarw.bss`,
  - initialize the base register,
  - apply the retained runtime relocations if your model keeps them.

### Where to hook it

RISC-V example:

- linker script:
  [experiments/classic/linker-qemu-virt.ld](experiments/classic/linker-qemu-virt.ld)
- startup:
  [experiments/classic/crt0.s](experiments/classic/crt0.s)

### Code idea

For the simple bare-metal runtime, a restricted relocator is enough:

- keep only `R_*_32`,
- read the already-linked 32-bit word,
- if it points into the linked data window, add the data delta,
- if it points into linked text/ROM, keep it or add a text delta if your test
  setup relocates code too.

## 6. Validation

Validate each layer separately:

1. codegen tests: does the backend emit the intended long canonical form?
2. MC tests: do the new fixups and ELF relocs exist?
3. linker tests: does the linker choose GP vs PC correctly?
4. runtime tests: does the program still run after moving the runtime data
   window?

RISC-V examples:

- MC test:
  [epic-lo.s](llvm-project/llvm/test/MC/RISCV/Relocations/epic-lo.s)
- linker test:
  [riscv-epic-ambiguous.s](llvm-project/lld/test/ELF/riscv-epic-ambiguous.s)
- end-to-end experiments:
  [experiments/](experiments)

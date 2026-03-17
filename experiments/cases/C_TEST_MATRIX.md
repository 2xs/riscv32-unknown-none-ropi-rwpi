# RWPI C Test Matrix

This directory contains small C probes used to check what the current
`+rwpi-gp-data` prototype actually supports.

The observations below matter in a very specific setup:

- `clang_cc1 -target-feature +rwpi-gp-data`
- `clang -S`
- `llc -mattr=+rwpi-gp-data`
- `llvm-mc`
- `ld.lld`

The matrix below therefore describes the current prototype capability as
observed through the backend feature itself.

Important distinction:

- the code generation path already works through `clang_cc1` / `clang -S`
- the driver-facing `-frwpi` surface for RISC-V is also wired up now
- this matrix is therefore mostly about backend behavior and emitted code shape

## Summary

Observed as working through the prototype path:

- writable scalar globals
- writable arrays with constant indices
- writable arrays with dynamic indices
- writable structure fields
- writable globals containing data pointers
- writable globals containing function pointers

Observed as intentionally staying on the standard non-RWPI path:

- constant globals in `.rodata`
- external globals

Still not covered by this matrix:

- TLS
- weak symbols
- address spaces other than 0
- more complex mixed ROPI/RWPI initializer patterns

Note:

- out-of-range RWPI accesses are now covered by dedicated LLVM/LLD tests using
  the full `%rwpi_hi` / `%rwpi_lo` sequence
- this matrix still focuses on small C probes, not on far-placement linker
  stress cases

## Detailed results

### `01_scalar_global.c`

Status:

- supported

Observed lowering:

- `&g` lowers through a full RWPI address materialization
- direct loads/stores use the same `%rwpi_hi` / `%rwpi_lo` base
- exact instruction shape may differ slightly between SDAG and GlobalISel

Conclusion:

- this is the basic RWPI case
- it works as intended

### `02_array_const_index.c`

Status:

- supported

Observed lowering:

- base array address lowers through RWPI
- element access uses a constant local offset from that base

Observed example:

- `lui a0, %rwpi_hi(g)`
- `add a0, gp, a0`
- local constant indexing is then applied from that base

Conclusion:

- arrays with constant indices are already handled well by the current
  prototype

### `03_array_dynamic_index.c`

Status:

- supported

Observed lowering:

- base array address lowers through RWPI
- dynamic index arithmetic is applied on top of that base

Observed example:

- `slli a0, a0, 2`
- RWPI base address materialization for `g`
- `add a0, a0, a1`
- `lw a0, 0(a0)`

Conclusion:

- dynamic array indexing is not a blocker for the current prototype
- the backend already handles this simple derived-address case

### `04_struct_field.c`

Status:

- supported

Observed lowering:

- base object lowers through RWPI
- field access uses a constant field offset

Observed example:

- RWPI base address materialization for `g`
- `lw a0, 4(a0)`

Conclusion:

- simple structure-field accesses already fit the current model

### `05_global_pointer_rwpi.c`

Status:

- supported

Observed lowering:

- the pointer cell `pg` is accessed through RWPI
- the data initializer remains a plain relocation in `.data`

Observed relocations in the object:

- `.rela.text`: `R_RISCV_CUSTOM194 pg`
- `.rela.text`: `R_RISCV_CUSTOM192 pg`
- `.rela.data`: `R_RISCV_32 target`

Observed linked code:

- RWPI base materialization for `pg`
- `lw a0, %rwpi_lo(pg)(base)`
- `lw a0, 0(a0)`

Conclusion:

- a writable global containing a pointer to writable data works in the current
  prototype
- the text-side access is RWPI
- the stored pointer value is resolved through normal data relocation
- this behavior is also covered by the direct Clang codegen test for
  `+rwpi-gp-data`

### `06_global_function_pointer.c`

Status:

- supported

Observed lowering:

- the pointer cell `pf` is accessed through RWPI
- the function pointer initializer remains a plain relocation in `.data`

Observed relocations in the object:

- `.rela.text`: `R_RISCV_CUSTOM194 pf`
- `.rela.text`: `R_RISCV_CUSTOM192 pf`
- `.rela.data`: `R_RISCV_32 f`

Observed linked code:

- RWPI base materialization for `pf`
- `lw a5, %rwpi_lo(pf)(base)`
- `jr a5`

Conclusion:

- a writable global containing a function pointer works in the current
  prototype
- the indirect call itself is not the hard part
- the pointer cell lives naturally in RWPI, while the function target remains
  code-side
- this behavior is also covered by the direct Clang codegen test for
  `+rwpi-gp-data`

### `07_constant_global.c`

Status:

- intentionally non-RWPI

Observed lowering:

- `get_c` lowers through standard `HI20/LO12`
- `load_c` folds to an immediate constant

Observed relocations in the object:

- `.rela.text`: `R_RISCV_HI20 c`
- `.rela.text`: `R_RISCV_LO12_I c`

Observed linked layout:

- `c` remains in `.rodata`

Conclusion:

- constants remain in the ROPI / rodata world
- this is the intended behavior of the current prototype

### `08_external_global.c`

Status:

- intentionally non-RWPI

Observed lowering:

- standard non-RWPI addressing
- no `%rwpi_hi` / `%rwpi_lo`

Conclusion:

- declarations are intentionally excluded by the current RWPI eligibility rule

## Current practical reading of the prototype

The current prototype already handles more simple cases than initially
expected.

In particular, it already covers:

- scalar RWPI globals
- simple derived addresses from RWPI globals
- pointer-valued writable globals
- function-pointer-valued writable globals

The main gaps are not these simple access patterns anymore.

The main remaining gaps are:

- unsupported symbol classes such as TLS and weak symbols
- broader mixed ROPI/RWPI initialization patterns

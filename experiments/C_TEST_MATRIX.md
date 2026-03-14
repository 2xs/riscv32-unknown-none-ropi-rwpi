# RWPI C Test Matrix

This directory contains small C probes used to check what the current
`+rwpi-gp-data` prototype actually supports.

The observations below matter in a very specific setup:

- `clang -S -emit-llvm`
- `llc -mattr=+rwpi-gp-data`
- `llvm-mc`
- `ld.lld`

This matters because the direct `clang -c` path does not yet expose the same
 behavior for all tested cases. The matrix below therefore describes the
 current prototype capability, not a finished frontend surface.

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
- out-of-range RWPI accesses
- more complex mixed ROPI/RWPI initializer patterns

## Detailed results

### `01_scalar_global.c`

Status:

- supported

Observed lowering:

- `&g` lowers to `addi a0, gp, %rwpi_lo(g)`
- `load g` lowers to `lw a0, %rwpi_lo(g)(gp)`
- `store g` lowers to `sw a0, %rwpi_lo(g)(gp)`

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

- `addi a0, gp, %rwpi_lo(g)`
- `lw a0, 8(a0)`

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
- `addi a1, gp, %rwpi_lo(g)`
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

- `addi a0, gp, %rwpi_lo(g)`
- `lw a0, 4(a0)`

Conclusion:

- simple structure-field accesses already fit the current model

### `05_global_pointer_rwpi.c`

Status:

- supported in the prototype path

Observed lowering through `llc`:

- the pointer cell `pg` is accessed through RWPI
- the data initializer remains a plain relocation in `.data`

Observed relocations in the object:

- `.rela.text`: `R_RISCV_CUSTOM192 pg`
- `.rela.data`: `R_RISCV_32 target`

Observed linked code:

- `lw a0, 0x4(gp)`
- `lw a0, 0(a0)`

Conclusion:

- a writable global containing a pointer to writable data works in the current
  prototype
- the text-side access is RWPI
- the stored pointer value is resolved through normal data relocation

Important note:

- with direct `clang -c`, this case currently falls back to standard
  `HI20/LO12` in `.text`
- the full RWPI behavior is observed through the `IR -> llc -> llvm-mc -> lld`
  path

### `06_global_function_pointer.c`

Status:

- supported in the prototype path

Observed lowering through `llc`:

- the pointer cell `pf` is accessed through RWPI
- the function pointer initializer remains a plain relocation in `.data`

Observed relocations in the object:

- `.rela.text`: `R_RISCV_CUSTOM192 pf`
- `.rela.data`: `R_RISCV_32 f`

Observed linked code:

- `lw a5, 0x0(gp)`
- `jr a5`

Conclusion:

- a writable global containing a function pointer works in the current
  prototype
- the indirect call itself is not the hard part
- the pointer cell lives naturally in RWPI, while the function target remains
  code-side

Important note:

- with direct `clang -c`, this case currently falls back to standard
  `HI20/LO12` in `.text`
- the full RWPI behavior is observed through the `IR -> llc -> llvm-mc -> lld`
  path

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

- standard `HI20/LO12`
- no `%rwpi_lo`

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

- the direct Clang frontend surface
- unsupported symbol classes such as TLS and weak symbols
- out-of-range accesses beyond the current direct `gp` window
- broader mixed ROPI/RWPI initialization patterns

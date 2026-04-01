# C++ Unknown-Segment Checks

This directory contains a few small C++ probes used to document and
reproduce the "unknown segment" issue discussed in the RISC-V ePIC work.

The background references are:

- ePIC proposal PR #343:
  <https://github.com/riscv-non-isa/riscv-elf-psabi-doc/pull/343>
- combined FDPIC/ePIC proposal PR #429:
  <https://github.com/riscv-non-isa/riscv-elf-psabi-doc/pull/429>

The key issue described there is the following:

- the compiler may need to form the address of a data object,
- but it may not know early enough whether the final symbol will belong to the
  code-side relocation discipline or the data-side relocation discipline,
- so a late linker decision may be needed.

In this repository, that late-decision problem is currently prototyped with a
new ambiguous form:

```asm
lui   rd, %epic_hi(sym)
add   rd, gp, rd
addi  rd, rd, %epic_lo(sym)
```

The intent is:

- compiler/assembler: emit a long ambiguous form
- linker: decide whether the final symbol is code-side or data-side
- linker: rewrite to PC-relative or `gp`-relative form
- linker: shrink further when possible

This README documents four concrete situations.

## 1. `extern const`: true ambiguous case

Files:

- [extern_const_decl.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/extern_const_decl.cpp)
- [extern_const_def.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/extern_const_def.cpp)

The declaration-only translation unit sees:

```cpp
extern const int extc;
```

At that point, the backend does not commit to either:

- code-side PC-relative addressing
- or data-side `gp`-relative addressing

Instead, it emits the ambiguous `%epic_hi/%epic_lo` pair.

What this example validates:

- in the declaration TU, the object file contains
  `R_RISCV_CUSTOM196` / `R_RISCV_CUSTOM197`
- after final link, the linker sees that `extc` really ends up code-side and
  rewrites the sequence to PC-relative form (`auipc` + low part)

This is the cleanest current demonstration of the new ambiguous-addressing
prototype.

## 2. Why the PR-style constructor case is not hard for this prototype

Files:

- [ctor_unknown_decl.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/ctor_unknown_decl.cpp)
- [ctor_unknown_def.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/ctor_unknown_def.cpp)

This case is inspired by the kind of example highlighted in the ePIC discussion:

```cpp
struct Box {
  Box();
  int x;
};

extern const Box box;
```

At first sight, this looks like exactly the kind of case that should remain
ambiguous for a long time.

What happens today in this prototype:

- in the current Clang/LLVM pipeline, the declaration already reaches the
  backend as an `external global`, not as an `external constant`
- that means the object is already treated as data-side
- so the object file uses direct RWPI relocations
  `R_RISCV_CUSTOM194` / `R_RISCV_CUSTOM192`,
- and the final link produces `gp`-relative code.

So this second example is not a hard case for this prototype.

The reason is important:

- in our current model, the hard question is not "is this C++?"
- the hard question is "does the declaration side still see something that
  might later end up either code-side or data-side?"

For the constructor-based object, the frontend has already answered that
question before the new ambiguous linker-driven machinery is needed.

It is still useful because it shows two things:

- the C++ non-trivial object case links and lowers consistently in the current
  pipeline,
- and the current frontend/IR pipeline is already strong enough to classify
  this particular case as data-side before the new ambiguous machinery is
  needed.

That makes it a good "control" example next to the real ambiguous `extern
const` case.

## 3. A tempting RO-reloc aggregate case that is also not hard for this pipeline

Another tempting source pattern is a read-only aggregate that contains an
address:

```cpp
struct Table {
  const int *ptr;
};

extern const Table table;
```

At first sight, this also looks like a perfect unknown-segment example.

In the current Clang/LLVM pipeline, however, this declaration does not reach
the backend as an `external constant`. It already reaches it as an
`external global`, so the backend directly chooses the RWPI path.

That means this pattern is not a true hard case for this prototype either.

This matters for the discussion around the ePIC examples:

- the community "hard case" is hard when the declaration-side lowering still
  cannot decide between code-side and data-side placement,
- but for our current pipeline, several apparently difficult C++ source forms
  are already classified as data-side before the new linker-driven ambiguous
  mechanism is needed.

## 4. Genuine hard case for this prototype: const pointer declaration, RO-reloc definition

Files:

- [roreloc_unknown_decl.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/roreloc_unknown_decl.cpp)
- [roreloc_unknown_def.cpp](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/roreloc_unknown_def.cpp)

This is the most useful current hard example:

```cpp
extern const int * const p;
```

The declaration-side translation unit reaches the backend as:

- an `external constant`
- with no local initializer
- and therefore with no early proof that the final symbol must already be
  treated as data-side

But the defining translation unit provides:

```cpp
extern const int target = 23;
extern const int * const p = &target;
```

So the final definition is:

- logically read-only,
- but pointer-bearing,
- therefore not true ROM data,
- and finally emitted in `dataramro`

This is exactly the kind of case the ambiguous `%epic_hi/%epic_lo` path is
meant to support:

- declaration side: still ambiguous
- final link: choose data-side
- final code: `gp`-relative
- final image: `.dataramro`

## Reproducing the checks

From the repository root:

```sh
make -C experiments cpp
```

This runs:

- [run_cpp_ambiguous_checks.sh](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/cpp/run_cpp_ambiguous_checks.sh)

The script:

1. rebuilds the local LLVM tools if needed
2. compiles the declaration and definition translation units
3. inspects relocations in the declaration object files
4. links final ELF files with the reference linker script
5. disassembles the linked result
6. checks that the expected final addressing discipline was chosen

Expected outcome:

- `extern const` declaration object:
  `R_RISCV_CUSTOM196` and `R_RISCV_CUSTOM197`
- linked `extern const` ELF:
  PC-relative sequence in the accessor
- `Box` declaration object:
  `R_RISCV_CUSTOM194` and `R_RISCV_CUSTOM192`
- linked `Box` ELF:
  `gp`-relative sequence in the accessor
- `const pointer` declaration object:
  `R_RISCV_CUSTOM196` and `R_RISCV_CUSTOM197`
- linked `const pointer` ELF:
  `gp`-relative sequence in the accessor and a `.dataramro` section

Final success message:

```text
C++ ambiguous-segment checks OK
```

## Reading the results

If you want to inspect the declaration object yourself, the most useful
commands are:

```sh
./build-rwpi-moved/bin/llvm-readobj -r /tmp/some-object.o
./build-rwpi-moved/bin/llvm-objdump -dr --no-show-raw-insn -M no-aliases /tmp/some-object.o
```

The main interpretation is:

- `CUSTOM196/197` means "ambiguous, linker decides later"
- `CUSTOM194/192` means "already known data-side, direct RWPI path"

At the moment, that is the most compact way to see whether a source pattern is
still truly ambiguous in the current pipeline, or whether LLVM has already
classified it before the linker step.

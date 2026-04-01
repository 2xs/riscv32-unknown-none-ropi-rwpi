# `riscv32-unknown-none-ropi-rwpi`

Notes, RFC material, and experiments for an experimental RISC-V
ROPI/RWPI execution model with `gp`-based runtime data addressing.

The repository name still uses `riscv32-unknown-none-ropi-rwpi` as a compact
prototype label, but the current direction is no longer "new target triple
first". The design should instead be read as a candidate code model /
execution model for split flash/RAM bare-metal systems.

The companion experiments also include some early Rust probes. They are useful
for validating that the execution model is not limited to C, but they should
not currently be read as proving full parity with the C/C++ unknown-segment
story. In the Rust source patterns tested so far, current Rust lowering does
not expose the key hard case as an ambiguous `external constant`; it is
already presented to the backend as data-side.

This direction is also close in spirit to the RISC-V ePIC proposal:

- code remains PC-relative,
- runtime data is addressed relative to `gp`,
- data that must still be rewritten at load time does not remain in the code
  segment,
- and the final image is constructed by startup/runtime code.

The main difference in this repository is emphasis:

- the prototype is deliberately bare-metal-oriented,
- it makes the startup/runtime contract concrete through linker-script,
  `crt0`, QEMU, and blob-format experiments,
- and it gives explicit names to the runtime data classes (`dataro`,
  `dataramro`, `datarw`).

What is still not covered as completely as in ePIC is the full "unknown
segment" problem, where the compiler cannot know early enough whether a symbol
will finally belong to the code-side or data-side relocation discipline.

The intended way to tackle that case is:

- do not emit a short low-12-only form too early,
- always start from one long ambiguous form,
- then let the linker choose, rewrite, and shrink it after final placement.

So the practical rule is "long ambiguous first, linker decision later", not
"short form first and try to grow it later".

Useful links:

- notes repository: <https://github.com/2xs/riscv32-unknown-none-ropi-rwpi>
- LLVM/LLD prototype branch:
  <https://github.com/2xs/llvm-project/tree/riscv32-unknown-none-ropi-rwpi-proposal>

## Target section naming

The intended ABI naming is now:

- `dataro` for true read-only data that stays in ROM
- `dataramro` for RO-reloc data copied to RAM then treated as read-only
- `.rela.dataramro` for the standard ELF `SHT_RELA` relocation table
  associated with `dataramro`
- `datarw` for writable runtime data
- `datarw.bss` for zero-initialized writable runtime data

The current prototype implementation still uses some transitional ELF section
names such as `.rodata`, `.data`, and `.bss`, but RO-reloc data now already
uses `.dataramro`.

Those current names should be read as implementation detail. The intended ABI
contract is the `data*` family above.

## Current prototype scope

The current prototype focuses on direct RWPI accesses lowered relative to
`gp`.

In current upstream-facing discussions, the most likely long-term shape is:

- a code-model-style selection surface,
- explicit object marking so the linker can reject incompatible inputs,
- and only then, if still justified, a more formal psABI surface.

In other words, this repository should not be read as evidence that a new
target triple is necessarily the right public interface.

The current compiler lowering no longer tries to choose between a short
`gp + lo12` form and a larger out-of-range form.

Instead, RWPI-eligible addresses are materialized systematically as a full
`gp`-relative address:

```asm
lui   t0, %rwpi_hi(symbol)
add   t0, gp, t0
addi  t0, t0, %rwpi_lo(symbol)
```

Loads and stores then use that materialized address.

This means:

- the compiler does not need to know the final linked offset of the symbol
- out-of-range RWPI accesses beyond the signed 12-bit `lo12` window work
- the short `gp + lo12` form is still valid in hand-written assembly when the
  author chooses it explicitly

In other words, the compiler currently always emits the robust full form for
RWPI data, and does not perform a "short form if possible" optimization by
itself.

However, the linker now performs a targeted RWPI relaxation when possible.

If `lld` sees the full compiler-emitted pattern and the final offset from
`__gp_data_start` fits in a signed 12-bit immediate, it can shrink:

```asm
lui   t0, %rwpi_hi(symbol)
add   t0, gp, t0
addi  t0, t0, %rwpi_lo(symbol)
```

into:

```asm
addi  t0, gp, imm12
```

Likewise, a full-address load/store sequence can be relaxed back to
`lw/sw ... imm12(gp)`.

So the current model is:

- the compiler always emits the safe full form
- `lld` relaxes it to the short `gp + imm12` form when the final placement
  allows it
- hand-written assembly may still use either form explicitly

## Minimum example

From the repository root:

```sh
./build-llvm.sh
./example.sh
```

This builds `clang` and `lld` in `build-rwpi-moved/`, then writes a minimal
RWPI-linked ELF to `./example.elf`.

The link step uses the reference linker script
[linker-rwpi-ramro.ld](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/linker-rwpi-ramro.ld).
It models the intended split with the target naming:

- `.text` / `.dataro` in ROM
- `.dataramro` first in the `gp`-addressable RAM window
- `.datarw` writable initialized data after `.dataramro`
- `.datarw.bss` as the zero-init tail of the same runtime data window

In terms of the target ABI naming above, that corresponds to:

- `.rodata` -> `dataro`
- `.dataramro` -> `dataramro`
- `.data` -> `datarw`
- `.bss` -> `datarw.bss`

The script also exposes the startup-facing symbols:

- `__gp_data_start`
- `__dataramro_start`, `__dataramro_end`, `__dataramro_load_start`
- `__datarw_start`, `__datarw_end`, `__datarw_load_start`
- `__datarw_bss_start`, `__datarw_bss_end`

`__gp_data_start` is the linker-script symbol at the start of the runtime `gp`
window. It does not rely on a synthetic object being emitted by the input
files.

For RO-reloc contents, the associated runtime relocation table is not renamed
to a custom ABI section. The linker keeps the natural ELF relocation section
name `.rela.dataramro` when relocations are retained in the output with
`--emit-relocs`.

The intended final `crt0` sequence is:

1. copy `.dataramro` from `__dataramro_load_start` to `__dataramro_start`
2. copy `.datarw` from `__datarw_load_start` to `__datarw_start`
3. zero `.datarw.bss`
4. apply the `Elf32_Rela` entries from `.rela.dataramro` to `.dataramro`
5. initialize `gp` from `__gp_data_start`
6. optionally make `.dataramro` read-only once relocations and initialization are done

The current ELF/QEMU `crt0` experiment in [experiments/classic/crt0.s](/Users/gilles/Documents/Code/backend-riscv32-unknown-none-ropi-rwpi/experiments/classic/crt0.s)
does not yet implement step 4 generically. If `.rela.dataramro` is non-empty,
it stops deliberately instead of pretending to have relocated the image.

So the current repository demonstrates two different runtime states:

- the classic ELF/QEMU path validates the linker/startup/data-placement
  contract and rejects unresolved retained `SHT_RELA` runtime relocation
  tables explicitly,
- the house blob experiment validates an actual post-copy relocation loop,
  but with a compact custom relocation table rather than retained ELF
  `SHT_RELA`.

If you want to observe the generated RWPI code directly, the simplest way is to
ask the experimental `clang` for assembly:

```sh
./build-rwpi-moved/bin/clang -target riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -frwpi -S ./experiments/cases/rwpi_probe_plain.c -o -
```

In the `.s` output, you should see `gp`-relative accesses built from
`%rwpi_hi(...)` and `%rwpi_lo(...)`.

After final link, some of those sequences may have been relaxed by `lld` back
to shorter `gp + imm12` instructions.

## About `objdump`

A generic host `objdump` may not understand this RISC-V ELF at all.

For RWPI object files, use the LLVM tools built in `build-rwpi-moved/bin`.

Example:

```sh
./build-rwpi-moved/bin/clang -target riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -frwpi -c ./experiments/cases/rwpi_probe_plain.c -o /tmp/rwpi-probe.o
./build-rwpi-moved/bin/llvm-objdump -dr --no-show-raw-insn -M no-aliases /tmp/rwpi-probe.o
./build-rwpi-moved/bin/llvm-readobj -r /tmp/rwpi-probe.o
```

This shows both:

- the `gp`-relative instructions in `.text`
- the custom RWPI relocations such as `R_RISCV_CUSTOM194` and
  `R_RISCV_CUSTOM192`

So, in practice:

- use `clang -S` to inspect source-level code generation
- use `llvm-objdump -dr` and `llvm-readobj -r` to inspect RWPI `.o` files

# `riscv32-unknown-none-ropi-rwpi`

Notes, RFC material, and experiments for an experimental RISC-V
`riscv32-unknown-none-ropi-rwpi` profile.

Useful links:

- notes repository: <https://github.com/2xs/riscv32-unknown-none-ropi-rwpi>
- LLVM/LLD prototype branch:
  <https://github.com/GGrimaud-2XS/llvm-project/tree/riscv32-unknown-none-ropi-rwpi-proposal>

## Current prototype scope

The current prototype focuses on direct RWPI accesses lowered relative to
`gp`.

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
It models the intended split:

- `.text` / `.rodata` in ROM
- `.ramro` first in the `gp`-addressable RAM window
- `.rwpi` writable initialized data after `.ramro`
- `.rwpi.bss` as the zero-init tail of the same runtime data window

The script also exposes the startup-facing symbols:

- `__gp_data_start`
- `__ramro_start`, `__ramro_end`, `__ramro_load_start`
- `__rwpi_data_start`, `__rwpi_data_end`, `__rwpi_data_load_start`
- `__rwpi_bss_start`, `__rwpi_bss_end`

`__gp_data_start` is the linker-script symbol at the start of the runtime `gp`
window. It does not rely on a synthetic object being emitted by the input
files.

The intended `crt0` sequence is:

1. copy `.ramro` from `__ramro_load_start` to `__ramro_start`
2. copy `.rwpi` from `__rwpi_data_load_start` to `__rwpi_data_start`
3. zero `.rwpi.bss`
4. initialize `gp` from `__gp_data_start`
5. optionally make `.ramro` read-only once relocations and initialization are done

If you want to observe the generated RWPI code directly, the simplest way is to
ask the experimental `clang` for assembly:

```sh
./build-rwpi-moved/bin/clang -target riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -frwpi -S ./experiments/rwpi_probe_plain.c -o -
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
./build-rwpi-moved/bin/clang -target riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -frwpi -c ./experiments/rwpi_probe_plain.c -o /tmp/rwpi-probe.o
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

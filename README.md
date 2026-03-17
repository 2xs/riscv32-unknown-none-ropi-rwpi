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

The implemented instruction forms are currently `lo12`-based direct accesses.
In theory, those forms use a signed 12-bit immediate around `gp`. In practice,
the current prototype places `__gp_data_start` at the beginning of the writable
RWPI region and addresses globals as positive offsets from that anchor.

This means the prototype currently provides about 2 KiB of directly addressable
RWPI globals, not the full 4 KiB signed window that would be available with a
symmetric layout around `gp`.

This is a prototype implementation choice. It is not intended to define the
long-term ABI limit.

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

You should see `gp`-relative accesses such as `%rwpi_lo(...)`.

## About `objdump`

A generic host `objdump` may not understand this RISC-V ELF at all.

Even when a tool does understand RISC-V ELF, object files that still contain
the prototype's custom RWPI relocations are a separate question.

In practice, the most direct way to inspect the prototype remains the
`clang -S` command above.

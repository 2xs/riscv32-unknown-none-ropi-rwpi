# RISC-V `riscv32-unknown-none-ropi-rwpi` Hacking Plan

## Initial plan

The initial plan is simple.

We want a minimal RISC-V compilation profile for split flash/RAM bare-metal
systems.

The target contract is:

- `.text` / `.rom` executes from flash
- writable runtime data executes from RAM
- `gp` is the runtime base for writable relocated data
- `.text` is never patched at runtime
- runtime relocation is restricted to writable memory

The intended toolchain chain is:

1. Clang frontend
2. LLVM IR
3. RISC-V backend lowering
4. MC / object emission
5. `lld`
6. `rustc` reusing the same LLVM behavior
7. FAE tooling validating the emitted ELF profile

The initial implementation strategy is also simple.

We do not start by writing a new backend. We start by teaching the existing
RISC-V backend a new profile. The conceptual ABI rule is:

- runtime writable data is addressed relative to `gp`

The first expected milestone is small:

- one mutable global lowered to `gp + offset`
- no `PCREL_*` or `HI20/LO12` used for that access
- one tiny test proving it

At that stage, the plan is still mostly about proving that the direction is
possible.

## Actual situation

The project is now past that first proof stage.

There is a working experimental prototype in the local `llvm-project` clone.
The current branch is:

- `riscv32-unknown-none-ropi-rwpi-proposal`

The current profile name is:

- `riscv32-unknown-none-ropi-rwpi`

The experimental backend feature used during the prototype is now:

- `+rwpi-gp-data`

The prototype already includes:

- experimental RISC-V lowering for selected writable globals via `gp`
- matching MC support for `%rwpi_lo(...)`
- experimental RWPI fixups and ELF relocations
- experimental `lld` support resolving RWPI relocations against
  `__rwpi_anchor`
- LLVM tests for code generation
- LLVM tests for MC / relocations
- `lld` tests for successful resolution and for missing-anchor failure

The current prototype also has an important scope limit:

- it only lowers direct RWPI accesses through `lo12` forms
- `__rwpi_anchor` currently sits at the beginning of the RWPI region
- globals are therefore addressed as positive offsets from the anchor
- the practical direct-addressing budget is currently about 2 KiB of RWPI
  globals

That is a prototype layout choice. It is not the intended long-term ABI limit.

This changes the status of the project in an important way.

The problem is no longer just:

- "stock GCC/LLVM flags do not get us there"

It is now:

- "a dedicated LLVM/LLD path exists and works as a prototype"

At the same time, the prototype is still clearly experimental.

It is not yet an upstreamable ABI surface.

What remains intentionally rough:

- the feature spelling is still experimental
- the relocations are still prototype-grade
- Clang integration is not the main finished entry point yet
- Rust integration is not done
- the set of supported access patterns is still narrow compared to a full ABI
- the long-term shape of target triple vs feature vs ABI flag is still open

So the current state is good enough to prove viability, but not good enough to
claim that the ABI is finished.

## Next milestone

make the prototype easier to understand, easier to reproduce, and easier to
discuss upstream

In practice, that means:

1. Stabilize the current prototype surface.

- keep the feature naming coherent
- keep the tests green
- keep the LLVM and `lld` parts aligned

2. Clarify the user-facing entry point.

- decide whether the next public surface is:
  - a target feature
  - a target profile
  - or an explicit target triple spelling

3. Tighten the documented contract.

- what is RWPI-eligible
- what is resolved against `__rwpi_anchor`
- what stays PC-relative
- what is still unsupported
- how the current 2 KiB direct-addressing limit follows from the current anchor
  placement
- what the out-of-range strategy should become

4. Improve Clang-facing usage.

- make it easy to demonstrate the prototype from a small C file
- reduce the amount of manual setup needed to reproduce the behavior

The most sensible next expansion are:

- support more access patterns
- improve the relocation shape
- improve the public frontend surface

The best next milestone is probably this:

- compile and link a small C example through Clang/LLVM/`lld`
- using the experimental RWPI path
- with the resulting ELF and relocations documented
- and with the unsupported cases stated explicitly

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

## RWPI/ROPI discipline

The project now needs a more explicit translation discipline than the original
"mutable globals go through `gp`" rule.

The working model is:

- `.text` remains true ROPI code: executable from flash, not patched at
  runtime
- not all read-only data is true ROPI data
- the classification must be driven by relocation semantics, not just by C
  `const`

The discipline distinguishes three logical classes of global data:

1. True ROPI data

- read-only after link
- contains no address value that must be fixed up at runtime
- may stay in flash / execute-in-place storage
- may be addressed with the normal code-side ROPI mechanisms

2. RWPI data

- writable at runtime
- relocated independently in the runtime data area
- addressed relative to `gp`

3. RO-reloc data

- logically read-only for the program
- but its initializer contains one or more address values that must be fixed up
  when the image is placed at runtime
- is therefore not true ROPI data, even if the source language spells it as
  `const`
- travels in the relocatable data image
- is addressed relative to `gp`, like RWPI
- is intended to live in a dedicated RAM read-only region after startup

For the current prototype, the important rule is:

- if a global requires runtime relocation of its contents, it must not remain
  in true ROPI

That includes obvious cases such as:

- read-only pointers to data
- read-only pointers to functions
- read-only arrays or structs containing addresses
- any aggregate whose initializer embeds a relocatable symbol value

This is the key subtlety of the profile.

A global may be read-only from the language point of view and still be
incompatible with true ROPI placement.

The intended runtime image contract is:

- true ROPI remains in flash
- RWPI is copied or initialized in writable RAM
- RO-reloc is copied into a separate RAM read-only region, relocated there by
  startup code, then left read-only if the platform can enforce that policy

This means the distinction between RWPI and RO-reloc is not about how code
addresses them. Both are expected to use the same `gp`-relative discipline in
generated code. The distinction is about final placement, relocation handling,
and memory protection.

The current prototype still uses the simplest intermediate materialization:

- keep the logical distinction between RWPI and RO-reloc
- allow both classes to flow through a generic relocatable-data representation
  for now

That keeps the semantic model honest while postponing the final linker-section
split.

The classification rules should therefore be read as translation rules:

- writable global -> RWPI
- read-only global with no runtime-relocatable address in its initializer ->
  true ROPI
- read-only global with any runtime-relocatable address in its initializer ->
  RO-reloc
- TLS remains outside this discipline for now
- unsupported symbol classes should be rejected explicitly rather than silently
  misclassified

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
  `__gp_data_start`
- LLVM tests for code generation
- LLVM tests for MC / relocations
- `lld` tests for successful resolution and for missing-anchor failure

The current prototype also has an important scope limit:

- it only lowers direct RWPI accesses through `lo12` forms
- `__gp_data_start` currently sits at the beginning of the RWPI region
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

This is especially true because the current prototype still needs a systematic
audit of which global declarations and initializer forms must be classified as:

- true ROPI
- RWPI
- RO-reloc

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
- what is RO-reloc and why it is not true ROPI
- what is resolved against `__gp_data_start`
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
- make the RWPI/ROPI/RO-reloc classification systematic
- improve the relocation shape
- improve the public frontend surface
- propagate the RO-reloc contract through linker section layout and startup
  conventions

## Linker and startup impact

The next linker-facing milestone is now clearer.

The compiler-side classification is no longer enough on its own. The linker and
startup contract must make the logical classes visible in the final image.

The expected impact is:

1. Input section policy

- the backend needs a stable input-section convention for RO-reloc data
- the current use of generic `.data.rel.ro` is acceptable as a temporary
  materialization
- the target ABI intent is a distinct logical `ramro` class

2. Linker script / output section policy

- the linker must place true ROPI in flash / ROM output sections
- the linker must place RWPI in writable RAM data output sections
- the linker must place RO-reloc in a distinct RAM read-only output section,
  conceptually `ramro`
- that output section should remain within the `gp`-addressable runtime data
  window if the ABI continues to require `gp` access for both RWPI and RO-reloc

3. Startup / `crt0` policy

- startup code must copy or initialize RWPI into RAM as usual
- startup code must also copy RO-reloc into its RAM destination
- startup code must apply the required runtime relocations before handing
  control to the program
- if the platform provides MPU/MMU protection, startup may then mark the RO-reloc
  region read-only

4. Validation impact

- linker tests should verify that RO-reloc input ends up in the intended output
  region
- startup documentation should spell out the copy/relocate/protect sequence
- the ABI notes should make explicit that RO-reloc is `gp`-addressed even
  though it is logically read-only

The best next milestone is probably this:

- compile and link a small C example through Clang/LLVM/`lld`
- using the experimental RWPI path
- with the resulting ELF and relocations documented
- and with the unsupported cases stated explicitly

# Response to the RFC: How to Build a ROPI/RWPI-Like Execution Format

This note is meant as a practical response to the RFC in this repository.

It does not restate the proposal at a high level. Instead, it explains what a
toolchain must actually do, component by component, to produce the intended
execution format:

- code remains executable in place,
- runtime data is addressed through a dedicated base register,
- writable data and relocatable read-only data are split from true ROM data,
- the linker and startup code expose an explicit runtime image contract.

The text is written so that a reader could use it as a guide for reproducing
the same design on another architecture, not only on RISC-V.

One important update to the framing of the work is this:

- the prototype repository still uses `riscv32-unknown-none-ropi-rwpi` as a
  compact label,
- but the more plausible upstream direction is now a code model / execution
  model,
- not a new target triple as the primary public surface.

Another important update is that this work is best understood in relation to
the RISC-V ePIC proposal.

The current prototype is close to ePIC in its core execution assumptions:

- code stays on the PC-relative side,
- runtime data stays on the `gp`-relative side,
- and data that must still be rewritten at load time does not remain in the
  code segment even if it is logically read-only after startup.

What this repository adds is mainly a different emphasis:

- a bare-metal startup/runtime point of view,
- explicit runtime data-class naming (`dataro`, `dataramro`, `datarw`),
- and end-to-end validation of the loader/startup contract.

What it still does not cover as fully as ePIC is the complete "unknown
segment" problem, where the compiler cannot know soon enough whether the final
symbol placement will require PC-relative or `gp`-relative treatment.

## Open issue: unknown segment

The strongest remaining limitation of the prototype is the handling of symbols
whose final residence cannot be decided early enough.

This matters because the execution model has two distinct addressing
disciplines:

- PC-relative for the code-side segment,
- `gp`-relative for the runtime-data segment.

For many objects, the current classification rules are already sufficient.
But for some language-level constructs, especially in C++-like scenarios, the
compiler may not know soon enough whether the final object will belong to the
code-side or data-side relocation discipline.

This is where the ePIC work is especially relevant. ePIC defines a canonical
ambiguous sequence and lets the linker rewrite it into the appropriate final
form once segment residence is known.

The important consequence is that the ambiguous case should not start from a
short low-12-only form. If a short form is chosen too early, the linker may
later discover that the symbol actually belongs to the other side of the split
and needs a full address materialization. That would require growing code at
link time, which is the opposite of what relaxation machinery is meant to do.

So the practical design rule is:

- compiler/assembler: emit one long ambiguous form,
- linker: decide whether the symbol is code-side or data-side,
- linker: rewrite to the proper PC-relative or `gp`-relative form,
- linker: then shrink the chosen form if the final displacement is small
  enough.

The present prototype does not yet apply that complete strategy from compiler
lowering for all data references, but this is now the clearest direction for
handling the remaining late-placement ambiguity.

So the honest current status is:

- the prototype validates the execution model itself,
- it validates the `gp`-relative data path,
- it validates the startup/runtime contract,
- but it does not yet claim to solve the full late-placement ambiguity problem.

For an eventual psABI proposal, this is likely the most important open design
point to address explicitly.

## 1. Start from the execution model, not from the ISA

The key design choice is not "use register X as a global base".

The key design choice is the execution format:

- executable code is never patched at runtime,
- true read-only data may remain in ROM unchanged,
- runtime data lives in a separate data image,
- code reaches runtime data through one stable base register,
- startup code is responsible for constructing the runtime data image before
  entering the program.

If that execution model is not fixed first, compiler and linker work tends to
collapse back into ordinary PIC, GOT, small-data, or generic ELF relocation
schemes.

That is why the implementation has to be driven by a data-classification
discipline and by an explicit linker/startup contract, not only by instruction
selection.

## 2. Define the data classes before changing code generation

The most important rule is that source-language `const` is not enough to decide
whether an object may remain in ROM.

The toolchain needs three logical classes:

1. True ROPI data

- read-only after link,
- contains no address-bearing value that must be fixed up when the runtime data
  image is placed,
- may remain in ROM.

2. RWPI data

- writable at runtime,
- belongs to the runtime data image,
- must be addressable through the dedicated data base register.

3. RO-reloc data

- logically read-only to the program,
- but its initializer embeds addresses,
- therefore it cannot be treated as true ROM data,
- it belongs to the runtime data image and is also addressed through the data
  base register,
- it may become read-only again after startup if the platform can enforce it.

This classification rule is the first thing that must be made explicit in any
implementation. If it is left implicit, the compiler will eventually leave a
pointer-bearing `const` object in ROM by accident and the whole model becomes
unsound.

In the current prototype, this policy is centralized in one backend-side
classification module instead of being spread across ad hoc tests.

That centralization is important for two reasons:

- multiple subsystems need the same decision,
- the policy is ABI logic, not a lowering detail.

On another architecture, the first reusable lesson is therefore:

- create one helper or module that answers "what class of data is this global?"
- make every consumer call it,
- do not duplicate the classification logic independently in section
  assignment, instruction selection, and object emission.

## 3. Expose a frontend surface, but keep the ABI decision backend-driven

The user needs a visible way to request the execution model.

In this prototype, the practical path was:

- keep an experimental backend feature,
- accept a driver-facing option,
- map that option to the backend feature.

The exact spelling is less important than the structure:

1. the driver must accept the profile for the target,
2. it must enable the backend behavior explicitly,
3. tests must exist at the driver level and at the codegen level.

Why this matters:

- without a driver surface, the work remains a backend experiment only,
- without backend ownership of the semantic decision, the feature becomes a
  driver hack with no precise lowering contract.

For another architecture, the recommendation is:

- start with a clearly experimental frontend switch or code-model surface,
- lower it to one backend-visible capability bit,
- delay target-triple or broader ABI naming decisions until the lowering and
  linker contract are proven,
- prefer a code-model-like public story if the core distinction is execution
  format and relocation discipline rather than register width, calling
  convention, or ISA variant.

## 4. Teach the backend to classify globals and to route them to the right addressing discipline

Once the data classes exist, instruction selection must treat them differently.

The essential split is:

- true ROPI data follows the normal code-side addressing model of the
  architecture,
- RWPI and RO-reloc data follow the runtime-data-base model.

That means the backend must answer at least two questions:

1. Should this global be addressed through the runtime data base register?
2. If yes, how do we materialize that address?

The important design choice in this prototype was to avoid compile-time
distance prediction.

The compiler always emits the robust full form:

```asm
lui   tmp, %rwpi_hi(symbol)
add   tmp, gp, tmp
addi  tmp, tmp, %rwpi_lo(symbol)
```

or the equivalent load/store form using that materialized base.

Why this is better than choosing a short form in the compiler:

- the compiler does not know the final placement of the symbol,
- the linker does,
- the full form works for both near and far placements,
- a later linker relaxation can still shrink it when safe.

This is one of the most transferable lessons for another architecture:

- prefer a compiler-emitted canonical form that is always correct,
- let the linker recover the shorter form after layout,
- do not make frontend or backend code generation depend on speculative final
  placement.

In practice, this affects both SelectionDAG and GlobalISel or their
architecture-specific equivalents. Both paths must agree on the same ABI rule.

## 5. Add dedicated assembler expressions, fixups, and relocations

If the target architecture does not already have a relocation family matching
the runtime-data-base scheme, the MC layer must grow one.

That means:

- new assembler syntax or internal expressions,
- new fixup kinds,
- new ELF relocation numbers or target-specific relocation encodings,
- object writer support,
- assembler and disassembler tests.

In the current prototype, the full-form addressing model required a pair of
relocations rather than a single low relocation:

- a high part,
- a low part.

This is not a RISC-V-specific lesson.

Any architecture that wants a stable data-base register model will usually need
one of these:

- a dedicated relocation family for "base register plus target symbol",
- or a repurposing of an existing relocation family that already means exactly
  that.

The reason is simple:

- generic code relocations usually describe code-side PC-relative or absolute
  addressing,
- they do not by themselves describe the semantic contract "this address is
  anchored to the runtime data base symbol".

So the MC layer is not optional glue. It is part of the ABI definition.

## 6. Give the object file layer an explicit section policy

After classification, globals must land in the right input sections.

A useful pattern is:

- true ROM data -> ordinary read-only sections,
- writable runtime data -> writable data sections,
- relocatable read-only runtime data -> a dedicated input section family.

In this prototype the dedicated input section is `.dataramro`.

The exact name is not universal, but the concept is.

Why a dedicated input section matters:

- the linker cannot preserve a semantic class it cannot see,
- startup code cannot target a region that has no distinct identity,
- later validation is much easier when the class is visible in emitted objects.

This is the point where the classification policy and the linker contract meet.

On another architecture, the advice is:

- introduce one section family per runtime data class that matters,
- keep the mapping simple and stable,
- do not hide RO-reloc inside a generic "read-only after relocation" name if
  the ABI needs stronger semantics than stock ELF conventions provide.

## 7. Make the linker the owner of final placement and late optimization

The linker has three separate responsibilities in this model.

### 7.1 Resolve the new relocation family

The linker must know which symbol anchors the runtime data base.

In this prototype, relocations are resolved against `__gp_data_start`, which is
defined by the linker script.

This is a critical design point:

- the anchor is a linker-script symbol,
- not a synthetic data object,
- not an implementation accident in one object file.

That keeps the ABI contract explicit and avoids fake input objects used only to
manufacture a base symbol.

### 7.2 Lay out the runtime image

The linker script must describe the intended runtime format, not only a generic
ELF layout.

At minimum, the runtime-facing sections must be visible:

- `dataro`
- `dataramro`
- `datarw`
- `datarw.bss`

and the linker script must expose the boundaries startup code needs:

- start/end of each runtime region,
- load addresses for copied sections,
- the base-register anchor,
- a stack symbol if the startup code is responsible for it.

Why this belongs in the linker script:

- these addresses are properties of the final image,
- they are not knowable earlier in the compilation chain,
- startup code must consume exact boundaries, not inferred conventions.

### 7.3 Relax the canonical full form

Once layout is known, the linker can optimize.

In this prototype, `lld` recognizes the full emitted pattern and rewrites it to
the short `gp + imm12` form when the final displacement fits.

That matters because it separates correctness from compactness:

- the compiler is always correct,
- the linker makes it smaller when the layout allows it.

This is a very general porting recommendation.

When an architecture has both a robust long form and a compact short form,
prefer:

- canonical long form in the compiler,
- relaxation in the linker,
- tests for the edge conditions of the relaxation window.

## 8. Be precise about what the runtime relocation table really means

For RO-reloc data, the natural idea is:

- the data lives in `dataramro`,
- its relocation table lives in `.rela.dataramro`,
- startup applies the relocations after copying.

That is the correct conceptual model, but it is important to state one subtle
point clearly.

Keeping the ordinary ELF `SHT_RELA` format is simple and inspectable, but a
fully generic runtime consumer then also needs a way to resolve the symbol
indices referenced by `r_info`.

That means one of two things must eventually happen:

1. the runtime has access to enough symbol information to evaluate the retained
   relocations,
2. or the linker must emit a more runtime-oriented relocation table whose
   entries are already self-contained.

This distinction matters because it explains the current prototype status:

- the fixed linked images already execute correctly in QEMU,
- but a fully general post-link runtime relocator for retained
  `.rela.dataramro` is still an open contract point.

A reader trying to reproduce this work on another architecture should therefore
separate two milestones:

- "the linked image works with the chosen final data base address",
- "the runtime can relocate a retained RO-reloc table after image placement".

These are related, but they are not the same milestone.

## 9. Startup code must mirror the linker contract exactly

The startup code is where the abstract ABI becomes concrete execution.

The required sequence is:

1. initialize a stack,
2. copy `dataramro`,
3. copy `datarw`,
4. zero `datarw.bss`,
5. apply the runtime relocation policy for `dataramro` if retained relocations
   are part of the chosen execution format,
6. initialize the runtime data base register from the linker-defined anchor,
7. transfer control to the program,
8. optionally lock the RO-reloc region back to read-only.

The reason this order matters is that code compiled for the profile assumes:

- runtime data is already in its final place before the program uses it,
- the base register already points at the correct runtime window,
- the linker-provided section boundaries are the source of truth.

This is another strongly transferable point:

- startup code must consume linker-defined symbols,
- not hard-coded addresses,
- not duplicated layout constants in assembly.

In the current repository, the ELF/QEMU `crt0` experiment is already enough to validate:

- copied writable data,
- zeroed BSS,
- base-register initialization,
- execution of RWPI code in QEMU.

It now also provides a deliberately small retained-`SHT_RELA` runtime
relocator for the bare-metal experiments:

- retained `.rela.dataramro` and `.rela.datarw` are consumed at startup,
- only `R_RISCV_32` is supported,
- patched words are rebased by range, using the linked data-window bounds to
  detect data-side pointers and leaving text/ROM-side pointers unchanged unless
  a text delta is configured explicitly.

This is still not a fully generic retained-ELF runtime relocation engine, but
it is enough to exercise the intended startup policy with a standard ELF image.

The repository also contains a separate "house blob" experiment, which does
exercise a real post-copy relocation loop, but through a compact custom
runtime relocation table rather than retained ELF `SHT_RELA` records.

## 10. Validation must happen at every stage of the chain

A profile like this is easy to misunderstand if only one stage is tested.

The useful validation ladder is:

1. Driver tests

- does the frontend option reach the backend as intended?

2. Codegen tests

- does the backend select the expected addressing discipline?

3. MC/object tests

- are the right relocations and sections emitted?

4. Linker tests

- does the linker resolve the new relocation family?
- does it reject missing anchor symbols?
- does it relax the long form correctly at the range boundaries?

5. Small C probes

- do common global forms classify as intended?
- writable scalar,
- array,
- struct,
- pointer,
- function pointer,
- read-only address-bearing aggregates.

6. End-to-end execution tests

- does startup construct the runtime image correctly?
- does the program still work if the runtime data base is moved?

That final point is especially important.

The current QEMU tests do not just show that the code executes once. They show
that the same program still works when the runtime data window is linked at a
different RAM base, which is the whole point of the profile.

## 11. What is architecture-specific and what is not

To port the design to another architecture, separate the work into two groups.

### Architecture-specific parts

- which register becomes the runtime data base,
- which instruction sequences materialize "base register plus symbol",
- which fixups and relocation encodings are needed,
- how linker relaxation is expressed in that ISA,
- what the native code-side ROPI model already looks like.

### Architecture-independent parts

- the three-way data classification,
- the need for a centralized eligibility policy,
- the separation between canonical compiler emission and linker relaxation,
- the dedicated section contract for runtime data classes,
- the linker-defined base symbol,
- the startup copy/zero/relocate/init sequence,
- the staged validation method.

This split is the main reason this note is useful beyond RISC-V.

The assembly syntax and relocation names will change on another architecture.
The overall toolchain shape should not.

## 12. Current prototype status

The current prototype already demonstrates the following successfully:

- frontend entry point,
- centralized RWPI/ROPI/RO-reloc classification,
- backend lowering of runtime-data accesses through the base register,
- full-form addressing plus linker relaxation,
- dedicated RO-reloc section materialization,
- linker-script-defined runtime image contract,
- startup code sufficient for fixed linked images,
- end-to-end execution in QEMU with the runtime data base moved to different
  RAM addresses.

The Rust experiments are encouraging, but they also show an important nuance:
the Rust source patterns tested so far do not expose the C/C++-style
unknown-segment hard case to the backend as an ambiguous `external constant`
reference. In the cases currently exercised, Rust lowering already presents
those foreign/data-bearing statics as data-side.

The main remaining open issue is not basic code generation anymore.

It is the final runtime relocation contract for retained `.rela.dataramro`
tables when the startup code must perform generic post-link relocation from the
ELF relocation records themselves.

That should be treated as the next design step, not as a detail to be filled in
later.

## 13. Recommended order for anyone reproducing this on another architecture

1. Write down the execution format and the three data classes.
2. Centralize the classification policy.
3. Add a frontend switch that enables one backend capability.
4. Teach the backend to route RWPI and RO-reloc through the dedicated base
   register.
5. Add the relocation family and object emission support.
6. Introduce a dedicated RO-reloc section family.
7. Teach the linker to resolve the new relocation family against one explicit
   linker-defined anchor.
8. Add linker relaxation only after the full canonical form works.
9. Define the linker-script runtime image and its boundary symbols.
10. Write startup code against those symbols.
11. Validate with object-level inspection and end-to-end execution.
12. Only then freeze the final ABI spelling and broader language/tool support.

That order mirrors what turned out to work best in this prototype.

It keeps correctness ahead of optimization, and ABI semantics ahead of
surface-level flag design.

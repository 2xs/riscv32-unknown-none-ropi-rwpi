	.attribute	4, 16
	.attribute	5, "rv32i2p1_m2p0_a2p1_c2p0_zmmul1p0_zaamo1p0_zalrsc1p0_zca1p0"
	.file	"rwpi_probe.c"
	.option	push
	.option	arch, +a, +c, +m, +zaamo, +zalrsc, +zca, +zmmul
	.text
	.globl	get_g                           # -- Begin function get_g
	.p2align	1
	.type	get_g,@function
get_g:                                  # @get_g
# %bb.0:                                # %entry
	addi	a0, gp, %lo(g-__rwpi_anchor)
	ret
.Lfunc_end0:
	.size	get_g, .Lfunc_end0-get_g
                                        # -- End function
	.option	pop
	.option	push
	.option	arch, +a, +c, +m, +zaamo, +zalrsc, +zca, +zmmul
	.globl	load_g                          # -- Begin function load_g
	.p2align	1
	.type	load_g,@function
load_g:                                 # @load_g
# %bb.0:                                # %entry
	lw	a0, %lo(g-__rwpi_anchor)(gp)
	ret
.Lfunc_end1:
	.size	load_g, .Lfunc_end1-load_g
                                        # -- End function
	.option	pop
	.type	__rwpi_anchor,@object           # @__rwpi_anchor
	.section	.rwpi,"aw",@progbits
	.globl	__rwpi_anchor
__rwpi_anchor:
	.byte	0                               # 0x0
	.size	__rwpi_anchor, 1

	.type	g,@object                       # @g
	.globl	g
	.p2align	2, 0x0
g:
	.word	42                              # 0x2a
	.size	g, 4

	.ident	"clang version 23.0.0git (https://github.com/llvm/llvm-project.git f517b5aa6c712e959de95bebf6e363953e054e34)"
	.section	".note.GNU-stack","",@progbits

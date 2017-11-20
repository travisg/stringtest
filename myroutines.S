.text

#define FUNCTION(x) .global x; .type x,STT_FUNC; x:
#define DATA(x) .global x; .type x,STT_OBJECT; x:
#define LOCAL_FUNCTION(x) .type x,STT_FUNC; x:
#define LOCAL_DATA(x) .type x,STT_OBJECT; x:
#define END(x) .size x, . - x

#ifdef __x86_64__

// ERMS versions of memcpy/memset for x86

// %rax = memcpy(%rdi, %rsi, %rdx)
FUNCTION(mymemcpy)
    // Save return value.
    mov %rdi, %rax
    mov %rdx, %rcx
    rep movsb // while (rcx-- > 0) *rdi++ = *rsi++;
.Lret:
    ret
END(mymemcpy)

// %rax = memset(%rdi, %rsi, %rdx)
FUNCTION(mymemset)
    // Save return value.
    mov %rdi, %r11
    mov %sil, %al
    mov %rdx, %rcx
    rep stosb // while (rcx-- > 0) *rdi++ = al;
    mov %r11, %rax
    ret
END(mymemset)

#elif __aarch64__

/* Copyright (c) 2012, Linaro Limited
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:
       * Redistributions of source code must retain the above copyright
         notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above copyright
         notice, this list of conditions and the following disclaimer in the
         documentation and/or other materials provided with the distribution.
       * Neither the name of the Linaro nor the
         names of its contributors may be used to endorse or promote products
         derived from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */

/*
 * Copyright (c) 2015 ARM Ltd
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the company may not be used to endorse or promote
 *    products derived from this software without specific prior written
 *    permission.
 *
 * THIS SOFTWARE IS PROVIDED BY ARM LTD ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL ARM LTD BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* Assumptions:
 *
 * ARMv8-a, AArch64, unaligned accesses.
 *
 */

#define dstin	x0
#define src	x1
#define count	x2
#define dst	x3
#define srcend	x4
#define dstend	x5
#define A_l	x6
#define A_lw	w6
#define A_h	x7
#define A_hw	w7
#define B_l	x8
#define B_lw	w8
#define B_h	x9
#define C_l	x10
#define C_h	x11
#define D_l	x12
#define D_h	x13
#define E_l	src
#define E_h	count
#define F_l	srcend
#define F_h	dst
#define tmp1	x9

#define L(l) .L ## l

	.macro def_fn f p2align=0
	.text
	.p2align \p2align
	.global \f
	.type \f, %function
\f:
	.endm

/* Copies are split into 3 main cases: small copies of up to 16 bytes,
   medium copies of 17..96 bytes which are fully unrolled. Large copies
   of more than 96 bytes align the destination and use an unrolled loop
   processing 64 bytes per iteration.
   Small and medium copies read all data before writing, allowing any
   kind of overlap, and memmove tailcalls memcpy for these cases as
   well as non-overlapping copies.
*/

def_fn mymemcpy p2align=6
	prfm	PLDL1KEEP, [src]
	add	srcend, src, count
	add	dstend, dstin, count
	cmp	count, 16
	b.ls	L(copy16)
	cmp	count, 96
	b.hi	L(copy_long)

	/* Medium copies: 17..96 bytes.  */
	sub	tmp1, count, 1
	ldp	A_l, A_h, [src]
	tbnz	tmp1, 6, L(copy96)
	ldp	D_l, D_h, [srcend, -16]
	tbz	tmp1, 5, 1f
	ldp	B_l, B_h, [src, 16]
	ldp	C_l, C_h, [srcend, -32]
	stp	B_l, B_h, [dstin, 16]
	stp	C_l, C_h, [dstend, -32]
1:
	stp	A_l, A_h, [dstin]
	stp	D_l, D_h, [dstend, -16]
	ret

	.p2align 4
	/* Small copies: 0..16 bytes.  */
L(copy16):
	cmp	count, 8
	b.lo	1f
	ldr	A_l, [src]
	ldr	A_h, [srcend, -8]
	str	A_l, [dstin]
	str	A_h, [dstend, -8]
	ret
	.p2align 4
1:
	tbz	count, 2, 1f
	ldr	A_lw, [src]
	ldr	A_hw, [srcend, -4]
	str	A_lw, [dstin]
	str	A_hw, [dstend, -4]
	ret

	/* Copy 0..3 bytes.  Use a branchless sequence that copies the same
	   byte 3 times if count==1, or the 2nd byte twice if count==2.  */
1:
	cbz	count, 2f
	lsr	tmp1, count, 1
	ldrb	A_lw, [src]
	ldrb	A_hw, [srcend, -1]
	ldrb	B_lw, [src, tmp1]
	strb	A_lw, [dstin]
	strb	B_lw, [dstin, tmp1]
	strb	A_hw, [dstend, -1]
2:	ret

	.p2align 4
	/* Copy 64..96 bytes.  Copy 64 bytes from the start and
	   32 bytes from the end.  */
L(copy96):
	ldp	B_l, B_h, [src, 16]
	ldp	C_l, C_h, [src, 32]
	ldp	D_l, D_h, [src, 48]
	ldp	E_l, E_h, [srcend, -32]
	ldp	F_l, F_h, [srcend, -16]
	stp	A_l, A_h, [dstin]
	stp	B_l, B_h, [dstin, 16]
	stp	C_l, C_h, [dstin, 32]
	stp	D_l, D_h, [dstin, 48]
	stp	E_l, E_h, [dstend, -32]
	stp	F_l, F_h, [dstend, -16]
	ret

	/* Align DST to 16 byte alignment so that we don't cross cache line
	   boundaries on both loads and stores.	 There are at least 96 bytes
	   to copy, so copy 16 bytes unaligned and then align.	The loop
	   copies 64 bytes per iteration and prefetches one iteration ahead.  */

	.p2align 4
L(copy_long):
	and	tmp1, dstin, 15
	bic	dst, dstin, 15
	ldp	D_l, D_h, [src]
	sub	src, src, tmp1
	add	count, count, tmp1	/* Count is now 16 too large.  */
	ldp	A_l, A_h, [src, 16]
	stp	D_l, D_h, [dstin]
	ldp	B_l, B_h, [src, 32]
	ldp	C_l, C_h, [src, 48]
	ldp	D_l, D_h, [src, 64]!
	subs	count, count, 128 + 16	/* Test and readjust count.  */
	b.ls	2f
1:
	stp	A_l, A_h, [dst, 16]
	ldp	A_l, A_h, [src, 16]
	stp	B_l, B_h, [dst, 32]
	ldp	B_l, B_h, [src, 32]
	stp	C_l, C_h, [dst, 48]
	ldp	C_l, C_h, [src, 48]
	stp	D_l, D_h, [dst, 64]!
	ldp	D_l, D_h, [src, 64]!
	subs	count, count, 64
	b.hi	1b

	/* Write the last full set of 64 bytes.	 The remainder is at most 64
	   bytes, so it is safe to always copy 64 bytes from the end even if
	   there is just 1 byte left.  */
2:
	ldp	E_l, E_h, [srcend, -64]
	stp	A_l, A_h, [dst, 16]
	ldp	A_l, A_h, [srcend, -48]
	stp	B_l, B_h, [dst, 32]
	ldp	B_l, B_h, [srcend, -32]
	stp	C_l, C_h, [dst, 48]
	ldp	C_l, C_h, [srcend, -16]
	stp	D_l, D_h, [dst, 64]
	stp	E_l, E_h, [dstend, -64]
	stp	A_l, A_h, [dstend, -48]
	stp	B_l, B_h, [dstend, -32]
	stp	C_l, C_h, [dstend, -16]
	ret

END(mymemcpy)

#undef dstin
#undef src
#undef count
#undef dst
#undef srcend
#undef dstend
#undef A_l
#undef A_lw
#undef A_h
#undef A_hw
#undef B_l
#undef B_lw
#undef B_h
#undef C_l
#undef C_h
#undef D_l
#undef D_h
#undef E_l
#undef E_h
#undef F_l
#undef F_h
#undef tmp1

#undef L

/* Assumptions:
 *
 * ARMv8-a, AArch64, unaligned accesses
 *
 */


#define dstin	x0
#define val	x1
#define valw	w1
#define count	x2
#define dst	x3
#define dstend	x4
#define tmp1	x5
#define tmp1w	w5
#define tmp2	x6
#define tmp2w	w6
#define zva_len x7
#define zva_lenw w7

#define L(l) .L ## l

#if 0
.macro def_fn f p2align=0
	.text
	.p2align \p2align
	.global \f
	.type \f, %function
\f:
	.endm
#endif

def_fn mymemset p2align=6
	dup	v0.16B, valw
	add	dstend, dstin, count

	cmp	count, 96
	b.hi	L(set_long)
	cmp	count, 16
	b.hs	L(set_medium)
	mov	val, v0.D[0]

	/* Set 0..15 bytes.  */
	tbz	count, 3, 1f
	str	val, [dstin]
	str	val, [dstend, -8]
	ret
	nop
1:	tbz	count, 2, 2f
	str	valw, [dstin]
	str	valw, [dstend, -4]
	ret
2:	cbz	count, 3f
	strb	valw, [dstin]
	tbz	count, 1, 3f
	strh	valw, [dstend, -2]
3:	ret

	/* Set 17..96 bytes.  */
L(set_medium):
	str	q0, [dstin]
	tbnz	count, 6, L(set96)
	str	q0, [dstend, -16]
	tbz	count, 5, 1f
	str	q0, [dstin, 16]
	str	q0, [dstend, -32]
1:	ret

	.p2align 4
	/* Set 64..96 bytes.  Write 64 bytes from the start and
	   32 bytes from the end.  */
L(set96):
	str	q0, [dstin, 16]
	stp	q0, q0, [dstin, 32]
	stp	q0, q0, [dstend, -32]
	ret

	.p2align 3
	nop
L(set_long):
	and	valw, valw, 255
	bic	dst, dstin, 15
	str	q0, [dstin]
	cmp	count, 256
	ccmp	valw, 0, 0, cs
	b.eq	L(try_zva)
L(no_zva):
	sub	count, dstend, dst	/* Count is 16 too large.  */
	add	dst, dst, 16
	sub	count, count, 64 + 16	/* Adjust count and bias for loop.  */
1:	stp	q0, q0, [dst], 64
	stp	q0, q0, [dst, -32]
L(tail64):
	subs	count, count, 64
	b.hi	1b
2:	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

	.p2align 3
L(try_zva):
	mrs	tmp1, dczid_el0
	tbnz	tmp1w, 4, L(no_zva)
	and	tmp1w, tmp1w, 15
	cmp	tmp1w, 4	/* ZVA size is 64 bytes.  */
	b.ne	 L(zva_128)

	/* Write the first and last 64 byte aligned block using stp rather
	   than using DC ZVA.  This is faster on some cores.
	 */
L(zva_64):
	str	q0, [dst, 16]
	stp	q0, q0, [dst, 32]
	bic	dst, dst, 63
	stp	q0, q0, [dst, 64]
	stp	q0, q0, [dst, 96]
	sub	count, dstend, dst	/* Count is now 128 too large.	*/
	sub	count, count, 128+64+64	/* Adjust count and bias for loop.  */
	add	dst, dst, 128
	nop
1:	dc	zva, dst
	add	dst, dst, 64
	subs	count, count, 64
	b.hi	1b
	stp	q0, q0, [dst, 0]
	stp	q0, q0, [dst, 32]
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

	.p2align 3
L(zva_128):
	cmp	tmp1w, 5	/* ZVA size is 128 bytes.  */
	b.ne	L(zva_other)

	str	q0, [dst, 16]
	stp	q0, q0, [dst, 32]
	stp	q0, q0, [dst, 64]
	stp	q0, q0, [dst, 96]
	bic	dst, dst, 127
	sub	count, dstend, dst	/* Count is now 128 too large.	*/
	sub	count, count, 128+128	/* Adjust count and bias for loop.  */
	add	dst, dst, 128
1:	dc	zva, dst
	add	dst, dst, 128
	subs	count, count, 128
	b.hi	1b
	stp	q0, q0, [dstend, -128]
	stp	q0, q0, [dstend, -96]
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

L(zva_other):
	mov	tmp2w, 4
	lsl	zva_lenw, tmp2w, tmp1w
	add	tmp1, zva_len, 64	/* Max alignment bytes written.	 */
	cmp	count, tmp1
	blo	L(no_zva)

	sub	tmp2, zva_len, 1
	add	tmp1, dst, zva_len
	add	dst, dst, 16
	subs	count, tmp1, dst	/* Actual alignment bytes to write.  */
	bic	tmp1, tmp1, tmp2	/* Aligned dc zva start address.  */
	beq	2f
1:	stp	q0, q0, [dst], 64
	stp	q0, q0, [dst, -32]
	subs	count, count, 64
	b.hi	1b
2:	mov	dst, tmp1
	sub	count, dstend, tmp1	/* Remaining bytes to write.  */
	subs	count, count, zva_len
	b.lo	4f
3:	dc	zva, dst
	add	dst, dst, zva_len
	subs	count, count, zva_len
	b.hs	3b
4:	add	count, count, zva_len
	b	L(tail64)

END(mymemset)


#else
#error unsupported architecture
#endif


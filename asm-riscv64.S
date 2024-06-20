/*
 * Copyright (c) 2023 Travis Geiselbrecht
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
.text

// A reasonably fast memset routine for 64bit RISC-V
//
// General algorithm is to use bytewise and then wordwise stores to
// align up to 64 bytes, then use 64 byte stores in the form of 8 8 byte
// stores until the end of the buffer, with trailing bytewise stores to
// finish the job.
//
// Tries to stick with registers to maximize compressed instruction usage
// and explicitly avoids using the stack.
.balign 32
.globl mymemset_asm
mymemset_asm:
    // make a copy of dest, leave the original value in a0
    mv      a3,a0

    // zero length, we're done
    beqz    a2,.Lmemset_exit

    // mask off everything outside of the bottom byte
    andi    a1,a1,0xff

    // if less than 8 bytes, just bytewise set
    li      a4,8
    blt     a2,a4,.Lmemset_bytewise

    // are we 8 byte misaligned?
    andi    a4,a3,7
    beqz    a4,.Lmemset_64byte

    // memset up to the 8 byte alignment
.balign 4
0:
    sb      a1,(a3)
    addi    a3,a3,1
    andi    a4,a3,7
    bnez    a4,0b

    // subtract the amount of bytes we just zeroed from the overall length
    sub     a4,a3,a0
    sub     a2,a2,a4

.Lmemset_64byte:
    // if the write is a zero, skip expanding it
    beqz    a1,1f

    // expand the char out into an entire register
    // TODO: see if multiplying by 0x1010101010101010 is faster
    slli    a5,a1,8
    add     a1,a5,a1
    slli    a5,a1,16
    add     a1,a5,a1
    slli    a5,a1,32
    add     a1,a5,a1

1:
    // compute the number of 64 byte sets
    srli    a4,a2,6
    beqz    a4,.Lmemset_8byte
    // compute the last address of a run of these sets
    slli    a4,a4,6
    add     a4,a3,a4

    // core loop, write 64 bytes at a time
    // use two base registers, 32 bytes apart, to keep the comparison at the end
    // of the loop far away from the addition.
    addi    a5,a3,32
.balign 8
0:
    sd      a1,(a3)
    sd      a1,8(a3)
    sd      a1,16(a3)
    sd      a1,24(a3)
    addi    a3,a3,64
    sd      a1,0(a5)
    sd      a1,8(a5)
    sd      a1,16(a5)
    sd      a1,24(a5)
    addi    a5,a5,64
    bne     a4,a3,0b

    // mask off the bottom 6 bits of a2 for any residual copies
    andi    a2,a2,63
    beqz    a2,.Lmemset_exit

.Lmemset_8byte:
    // compute the number of 8 byte sets
    srli    a4,a2,3
    beqz    a4,.Lmemset_bytewise

    // compute the last address of a run of 8 byte sets
    slli    a4,a4,3
    add     a4,a3,a4

    // write 8 bytes at a time
.balign 4
0:
    sd      a1,(a3)
    addi    a3,a3,8
    bne     a4,a3,0b

    // mask off the bottom 3 bits of a2 for any residual copies
    andi    a2,a2,7
    beqz    a2,.Lmemset_exit

.Lmemset_bytewise:
    // compute the max address (a2) and loop until the dest pointer (a3) reaches it
    add     a2,a3,a2
.balign 4
0:
    sb      a1,0(a3)
    addi    a3,a3,1
    bne     a2,a3,0b

.Lmemset_exit:
    // a0 should still hold the original dest
    ret

///////////////////////////////////////////////////////////////////////////////
// memcpy
///////////////////////////////////////////////////////////////////////////////

    // a0 = dest
    // a1 = src
    // a2 = size
.balign 32
.globl mymemcpy_asm
mymemcpy_asm:
    // Save return value.
    // make a copy of dest so we can restore it at exit
    mv      t6,a0

    // zero length, we're done
    beqz    a2,.Lmemcpy_exit

    // compare src and dest, if they're the same we're done
    beq     a0,a1,.Lmemcpy_exit

    // if length < 16 bytes, just revert to bytewise
    li      a3,16
    blt     a2,a3,.Lmemcpy_bytewise

    // is the dest misaligned?
    andi    a3,a0,7
    beqz    a3,.Lmemcpy_dest_aligned

    // copy bytes until dest is 8 byte aligned
0:
    lbu     a4,0(a1)
    addi    a0,a0,1
    addi    a1,a1,1
    andi    a3,a0,7
    sb      a4,-1(a0)
    bnez    a3,0b

    // subtract the amount of bytes we just zeroed from the overall length
    sub     a3,a0,t6
    sub     a2,a2,a3

.Lmemcpy_dest_aligned:
    // see if the source is 8 byte aligned, dest is already 8 byte aligned
    andi    a3,a1,7
    bnez    a3,.Lmemcpy_misaligned // give up for now if they're not aligned

.Lmemcpy_64byte:
    // compute the number of 64 byte copies
    srli    a3,a2,6
    beqz    a3,.Lmemcpy_8byte
    // compute the last source address of a run of these sets
    slli    a3,a3,6
    add     a3,a3,a1

    // copy 64 bytes at a time
.balign 4
0:
    ld      a4,0(a1)
    ld      a5,8(a1)
    ld      a6,16(a1)
    ld      a7,24(a1)
    ld      t0,32(a1)
    ld      t1,40(a1)
    ld      t2,48(a1)
    ld      t3,56(a1)
    addi    a1,a1,64
    sd      a4,0(a0)
    sd      a5,8(a0)
    sd      a6,16(a0)
    sd      a7,24(a0)
    sd      t0,32(a0)
    sd      t1,40(a0)
    sd      t2,48(a0)
    sd      t3,56(a0)
    addi    a0,a0,64
    bne     a1,a3,0b

    // mask off the bottom 6 bits of a2 for any residual copies
    andi    a2,a2,63
    beqz    a2,.Lmemcpy_exit

.Lmemcpy_8byte:
    // compute the number of 8 byte copies
    srli    a3,a2,3
    beqz    a3,.Lmemcpy_bytewise
    // compute the last source address of a run of these sets
#ifdef __riscv_zba
    sh3add  a3,a3,a1
#else
    slli    a3,a3,3
    add     a3,a3,a1
#endif

    // copy 8 bytes at a time, testing for terminal source address
.balign 4
0:
    ld      a4,0(a1)
    addi    a0,a0,8
    addi    a1,a1,8
    sd      a4,-8(a0)
    bne     a1,a3,0b

    // mask off the bottom 3 bits of a2 for any residual copies
    andi    a2,a2,7
    beqz    a2,.Lmemcpy_exit

.Lmemcpy_bytewise:
    // compute the terminal source address
    add     a3,a1,a2

    // copy one byte at a time, testing for terminal source address
.balign 4
0:
    lbu     a4,0(a1)
    addi    a0,a0,1
    addi    a1,a1,1
    sb      a4,-1(a0)
    bne     a1,a3,0b

.Lmemcpy_exit:
    // we saved the original dest in t6 at the start, restore it here
    mv      a0,t6
    ret

    // deal with misaligned source. State at this point:
    // source (a0) is misaligned by 1-7 bytes
    // destination (a1) is 8 byte aligned
    // length (a2) is at least 8 bytes
.Lmemcpy_misaligned:
    // compute the number of 8 byte copies we'll make below
    srli    a3,a2,3
    beqz    a3,.Lmemcpy_bytewise

    // compute the last source address (a3) of a run of these sets
#ifdef __riscv_zba
    sh3add  a3,a3,a1
#else
    slli    a3,a3,3
    add     a3,a3,a1
#endif

    // mask off the bottom 3 bits of length (a2) for any residual copies
    andi    a2,a2,7

    // compute how much the source is misaligned
    andi    a4,a1,7

    // use a quick delta jump table to get to one of the 7 alignment handlers
    lla     a5,.Lmemcpy_misaligned_table
#ifdef __riscv_zba
    sh2add  a6,a4,a5
#else
    slli    a4,a4,2
    add     a6,a5,a4
#endif
    lwu     a4,-4(a6) // -4 offset to account for the 0 based table
    add     a5,a5,a4
    jr      a5

.balign 4
.Lmemcpy_misaligned_table:
    .word   .Lmemcpy_misaligned_1 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_2 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_3 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_4 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_5 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_6 - .Lmemcpy_misaligned_table
    .word   .Lmemcpy_misaligned_7 - .Lmemcpy_misaligned_table

// Implement a loop to copy 8 bytes at a time with the 7 various unaligned
// situations that can arise.
.macro memcpy_implement_misalign n

// precompute some constants
.set INV_N, (8-\n)      // where N is 1-7, INV_N is the opposite of it 7-1
.set N_8, (\n*8)        // N * 8, bits
.set INV_N_8, (64-N_8)  // inverse of N * 8

.balign 4
memcpy_misaligned_\n:
.Lmemcpy_misaligned_\n:
    // prime the residual data (a5) between loops
    // Current algorithm uses optimized load instructions of the right size.
    // TODO: consider a 8 byte aligned load and shift. it may be invalid, since
    // it could read outside the source buffer in some cases.
.if \n == 7
    lbu     a5,0(a1)
.elseif \n == 6
    lhu     a5,0(a1)
.elseif \n == 5
    lhu     a6,1(a1)
    lbu     a5,0(a1)
    slli    a6,a6,8
    or      a5,a5,a6
.elseif \n == 4
    lwu     a5,0(a1)
.elseif \n == 3
    lwu     a6,1(a1)
    lbu     a5,0(a1)
    slli    a6,a6,8
    or      a5,a5,a6
.elseif \n == 2
    lwu     a6,2(a1)
    lhu     a5,0(a1)
    slli    a6,a6,16
    or      a5,a5,a6
.elseif \n == 1
    lhu     a6,1(a1)
    lwu     a7,3(a1)
    lbu     a5,0(a1)
    slli    a6,a6,8
    slli    a7,a7,24
    or      a5,a5,a6
    or      a5,a5,a7
.else
    unimp
.endif

.balign 8
0:
    // load 8 bytes at aligned source offset
    ld      a4,INV_N(a1)
    addi    a1,a1,8

    // shift out the extra source data to a temporary spot (a6),
    // or in the new residual data (a5),
    // save the temporary data (a6) to the residual slot (a5)
    srli    a6,a4,N_8
    slli    a4,a4,INV_N_8
    or      a4,a4,a5
    mv      a5,a6

    // store the destination data
    sd      a4,0(a0)
    addi    a0,a0,8

    // test for terminal source address and loop
    bne     a1,a3,0b

    // end if length (a2) is zero
    beqz    a2,.Lmemcpy_exit

    // continue with any residiual bytewise copies to finish it off
    j       .Lmemcpy_bytewise
.endm

memcpy_implement_misalign 1
memcpy_implement_misalign 2
memcpy_implement_misalign 3
memcpy_implement_misalign 4
memcpy_implement_misalign 5
memcpy_implement_misalign 6
memcpy_implement_misalign 7

// vim: ts=4:sw=4:expandtab:

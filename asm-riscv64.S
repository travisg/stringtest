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

    // compute the last dest address
    andi    a4,a3,-8
    addi    a4,a4,8

    // subtract the amount of bytes we're about to set from overall length
    sub     a5,a4,a3
    sub     a2,a2,a5

0:
    sb      a1,(a3)
    addi    a3,a3,1
    bne     a4,a3,0b

.Lmemset_64byte:
    // expand the char out into an entire register
    // TODO: see if multiplying by 0x1010101010101010 is faster
    // TODO: possibly add special case for 0
    slli    a5,a1,8
    add     a1,a5,a1
    slli    a5,a1,16
    add     a1,a5,a1
    slli    a5,a1,32
    add     a1,a5,a1

    // compute the number of 64 byte sets
    srli    a4,a2,6
    beqz    a4,.Lmemset_8byte
    // compute the last address of a run of these sets
    slli    a4,a4,6
    add     a4,a3,a4

0:
    sd      a1,(a3)
    sd      a1,8(a3)
    sd      a1,16(a3)
    sd      a1,24(a3)
    sd      a1,32(a3)
    sd      a1,40(a3)
    sd      a1,48(a3)
    sd      a1,56(a3)
    addi    a3,a3,64
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

    // copy 8 bytes at a time
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
0:
    sb      a1,0(a3)
    addi    a3,a3,1
    bne     a2,a3,0b

.Lmemset_exit:
    // a0 should still hold the original dest
    ret

    // a0 = dest
    // a1 = src
    // a2 = size
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

    // see if the source and dest are similarly 8 byte aligned
    xor     a3,a0,a1
    andi    a3,a3,7
    bnez    a3,.Lmemcpy_bytewise // give up for now if they're not aligned

    // is the dest misaligned?
    andi    a3,a0,7
    beqz    a3,.Lmemcpy_64byte

    // copy bytes up until dest is 8 byte aligned

    // compute the next 8 byte aligned address at dest
    andi    a3,a0,-8
    addi    a3,a3,8

    // subtract the amount of bytes we're about to set from overall length
    sub     a4,a3,a0
    sub     a2,a2,a4

    // bytewise copy until we hit this 8 byte aligned dest address
0:
    addi    a0,a0,1
    lbu     a4,0(a1)
    addi    a1,a1,1
    sb      a4,-1(a0)
    bne     a0,a3,0b

.Lmemcpy_64byte:
    // compute the number of 64 byte copies
    srli    a3,a2,6
    beqz    a3,.Lmemcpy_8byte
    // compute the last source address of a run of these sets
    slli    a3,a3,6
    add     a3,a3,a1

    // copy 64 bytes at a time
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
    slli    a3,a3,3
    add     a3,a3,a1

    // copy 8 bytes at a time, testing for terminal source address
0:
    ld      a4,0(a1)
    addi    a1,a1,8
    sd      a4,0(a0)
    addi    a0,a0,8
    bne     a1,a3,0b

    // mask off the bottom 3 bits of a2 for any residual copies
    andi    a2,a2,7
    beqz    a2,.Lmemcpy_exit

.Lmemcpy_bytewise:
    // compute the terminal source address
    add     a3,a1,a2

    // copy one byte at a time, testing for terminal source address
0:
    lbu     a4,0(a1)
    addi    a1,a1,1
    sb      a4,0(a0)
    addi    a0,a0,1
    bne     a1,a3,0b

.Lmemcpy_exit:
    mv      a0,t6
    ret

// vim: ts=4:sw=4:expandtab:

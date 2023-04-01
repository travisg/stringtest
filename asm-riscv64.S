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
    beq     a2,zero,.Lmemset_exit

    // mask off everything outside of the bottom byte
    andi    a1,a1,0xff

    // if less than 8 bytes, just bytewise set
    li      a4,8
    blt     a2,a4,.Lmemset_bytewise

    // are we 8 byte misaligned?
    andi    a4,a3,7
    beq     a4,zero,.Lmemset_64byte

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
    beq     a4,zero,.Lmemset_8byte
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
    beq     a2,zero,.Lmemset_exit

.Lmemset_8byte:
    // compute the number of 8 byte sets
    srli    a4,a2,3
    beq     a4,zero,.Lmemset_bytewise

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
    beq     a2,zero,.Lmemset_exit

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

.globl mymemcpy_asm
mymemcpy_asm:
    // Save return value.
    ret

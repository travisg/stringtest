/*
 * Copyright (c) 2023 Travis Geiselbrecht
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
.text

// Simple memset and memcpy routines that use rep stosb

.globl mymemset_asm
mymemset_asm:
    // Save return value.
    mov %rdi, %r11
    mov %sil, %al
    mov %rdx, %rcx
    rep stosb // while (rcx-- > 0) *rdi++ = al;
    mov %r11, %rax
    ret

.globl mymemcpy_asm
mymemcpy_asm:
    // Save return value.
    mov %rdi, %rax
    mov %rdx, %rcx
    rep movsb // while (rcx-- > 0) *rdi++ = *rsi++;
    ret

// vim: ts=4:sw=4:expandtab:

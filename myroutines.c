/*
 * Copyright (c) 2023 Travis Geiselbrecht
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <stddef.h>

// A place to work on and stick in fast C routines

// Currently unimplemented, these are reference slow implementations
void *mymemcpy_c(void *dst, const void *src, size_t len) {
    char *xd = (char *)dst;
    const char *xs = (const char *)src;

    for ( ; len > 0; len-- ) {
        *xd++ = *xs++;
    }

    return dst;
}

void *mymemset_c(void *dst, int c, size_t len) {
    char *xs = (char *) dst;

    for ( ; len > 0; len-- ) {
        *xs++ = c;
    }

    return dst;

}


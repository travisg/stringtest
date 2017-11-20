// Copyright 2016 The Fuchsia Authors
// Copyright (c) 2008-2014 Travis Geiselbrecht
//
// Use of this source code is governed by a MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *src;
static uint8_t *dst;

static uint8_t *src2;
static uint8_t *dst2;

// large buffer to blow out the L3 cache
static size_t MAX_BUFFER_SIZE = 16*1024*1024;

// if we're testing our own memcpy, use this
extern void *mymemcpy(void *dst, const void *src, size_t len);
extern void *mymemset(void *dst, int c, size_t len);

#ifdef __APPLE__
#include <mach/mach_time.h>

static uint64_t current_time()
{
    return mach_absolute_time();
}

#elif __linux__
#include <time.h>

static uint64_t current_time()
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);

    return t.tv_sec * 1000000000ULL + t.tv_nsec;
}

#else

#error need a way to get ns time

#endif

static inline size_t iterations(size_t buffer_size) {
    return (1024*1024*1024 / buffer_size); // enough iterations to have to copy/set 1GB
}

/* reference implementations of memmove/memcpy */
typedef long word;

#define lsize sizeof(word)
#define lmask (lsize - 1)

static void *c_memmove(void *dest, void const *src, size_t count)
{
    char *d = (char *)dest;
    const char *s = (const char *)src;
    int len;

    if (count == 0 || dest == src)
        return dest;

    if ((long)d < (long)s) {
        if (((long)d | (long)s) & lmask) {
            // src and/or dest do not align on word boundary
            if ((((long)d ^ (long)s) & lmask) || (count < lsize))
                len = count; // copy the rest of the buffer with the byte mover
            else
                len = lsize - ((long)d & lmask); // move the ptrs up to a word boundary

            count -= len;
            for (; len > 0; len--)
                *d++ = *s++;
        }
        for (len = count / lsize; len > 0; len--) {
            *(word *)d = *(word *)s;
            d += lsize;
            s += lsize;
        }
        for (len = count & lmask; len > 0; len--)
            *d++ = *s++;
    } else {
        d += count;
        s += count;
        if (((long)d | (long)s) & lmask) {
            // src and/or dest do not align on word boundary
            if ((((long)d ^ (long)s) & lmask) || (count <= lsize))
                len = count;
            else
                len = ((long)d & lmask);

            count -= len;
            for (; len > 0; len--)
                *--d = *--s;
        }
        for (len = count / lsize; len > 0; len--) {
            d -= lsize;
            s -= lsize;
            *(word *)d = *(word *)s;
        }
        for (len = count & lmask; len > 0; len--)
            *--d = *--s;
    }

    return dest;
}

static void *c_memset(void *s, int c, size_t count)
{
    char *xs = (char *) s;
    size_t len = (-(size_t)s) & lmask;
    word cc = c & 0xff;

    if ( count > len ) {
        count -= len;
        cc |= cc << 8;
        cc |= cc << 16;
        if (sizeof(word) == 8)
            cc |= (uint64_t)cc << 32; // should be optimized out on 32 bit machines

        // write to non-aligned memory byte-wise
        for ( ; len > 0; len-- )
            *xs++ = c;

        // write to aligned memory dword-wise
        for ( len = count / lsize; len > 0; len-- ) {
            *((word *)xs) = (word)cc;
            xs += lsize;
        }

        count &= lmask;
    }

    // write remaining bytes
    for ( ; count > 0; count-- )
        *xs++ = c;

    return s;
}

static const char *format_bps(size_t size, uint64_t time) {
    static char cbuf[64];

    uint64_t total = (uint64_t)size * iterations(size) * 1000000000 / time;
    if (total > 1000000000) { // GB
        total /= 1000000;
        snprintf(cbuf, sizeof(cbuf), "%12" PRIu64 " MBps", total);
    } else if (total > 1000000) { // MB
        total /= 1000;
        snprintf(cbuf, sizeof(cbuf), "%12" PRIu64 " KBps", total);
    } else {
        snprintf(cbuf, sizeof(cbuf), "%12" PRIu64 " Bps", total);
    }

    return cbuf;
}

static void *null_memcpy(void *dst, const void *src, size_t len)
{
    return dst;
}

__attribute__((noinline))
static uint64_t bench_memcpy_routine(void *memcpy_routine(void *, const void *, size_t), size_t srcalign, size_t dstalign, size_t buffer_size)
{
    int i;
    uint64_t t0;

    t0 = current_time();
    for (i=0; i < iterations(buffer_size); i++) {
        memcpy_routine(dst + dstalign, src + srcalign, buffer_size);
    }
    return current_time() - t0;
}

static void bench_memcpy(void)
{
    uint64_t null, c, libc, mine;
    size_t srcalign, dstalign;

    printf("memcpy speed test\n");

    size_t buffer_size = 4*1024;
    do {
        printf("buffer size %zu\n", buffer_size);
        for (srcalign = 0; srcalign <= 64; ) {
            for (dstalign = 0; dstalign <= 64; ) {
                c = bench_memcpy_routine(&c_memmove, srcalign, dstalign, buffer_size);
                libc = bench_memcpy_routine(&memcpy, srcalign, dstalign, buffer_size);
                mine = bench_memcpy_routine(&mymemcpy, srcalign, dstalign, buffer_size);

                //printf("null %llu c %llu libc %llu mine %llu\n", null, c, libc, mine);

                printf("srcalign %2zu, dstalign %2zu: ", srcalign, dstalign);
                printf("c %10" PRIu64 " %s; ", c, format_bps(buffer_size, c));
                printf("libc %10" PRIu64 " %s; ", libc, format_bps(buffer_size, libc));
                printf("asm %10" PRIu64 " %s", mine, format_bps(buffer_size, mine));
                printf("\n");

                if (dstalign < 8)
                    dstalign++;
                else
                    dstalign <<= 1;
            }
            if (srcalign < 8)
                srcalign++;
            else
                srcalign <<= 1;
        }
        buffer_size *= 4;
    } while (buffer_size <= MAX_BUFFER_SIZE);
}

static void fillbuf(void *ptr, size_t len, uint32_t seed)
{
    size_t i;

    for (i = 0; i < len; i++) {
        ((char *)ptr)[i] = seed;
        seed *= 0x1234567;
    }
}

static void validate_memcpy(void)
{
    size_t srcalign, dstalign, size;
    const size_t maxsize = 256;

    printf("testing memcpy for correctness\n");

    /*
     * do the simple tests to make sure that memcpy doesn't color outside
     * the lines for all alignment cases
     */
    for (srcalign = 0; srcalign <= 64; srcalign++) {
        printf("srcalign %2zu\n", srcalign);
        for (dstalign = 0; dstalign <= 64; dstalign++) {
            //printf("\tdstalign %zu\n", dstalign);
            for (size = 0; size < maxsize; size++) {

                //printf("srcalign %zu, dstalign %zu, size %zu\n", srcalign, dstalign, size);

                fillbuf(src, maxsize * 2, 567);
                fillbuf(src2, maxsize * 2, 567);
                fillbuf(dst, maxsize * 2, 123514);
                fillbuf(dst2, maxsize * 2, 123514);

                c_memmove(dst + dstalign, src + srcalign, size);
                mymemcpy(dst2 + dstalign, src2 + srcalign, size);

                int comp = memcmp(dst, dst2, maxsize * 2);
                if (comp != 0) {
                    printf("error! srcalign %zu, dstalign %zu, size %zu\n", srcalign, dstalign, size);
                }
            }
        }
    }
}

__attribute__((noinline))
static uint64_t bench_memset_routine(void *memset_routine(void *, int, size_t), size_t dstalign, size_t len)
{
    int i;
    uint64_t t0;

    t0 = current_time();
    for (i=0; i < iterations(len); i++) {
        memset_routine(dst + dstalign, 0, len);
    }
    return current_time() - t0;
}

static void bench_memset(void)
{
    uint64_t c, libc, mine;
    size_t dstalign;

    printf("memset speed test\n");

    size_t buffer_size = 4*1024;
    do {
        printf("buffer size %zu\n", buffer_size);
        for (dstalign = 0; dstalign < 64; dstalign++) {

            c = bench_memset_routine(&c_memset, dstalign, buffer_size);
            libc = bench_memset_routine(&memset, dstalign, buffer_size);
            mine = bench_memset_routine(&mymemset, dstalign, buffer_size);

            printf("dstalign %2zu: ", dstalign);
            printf("c memset %10" PRIu64 " %s; ", c, format_bps(buffer_size, c));
            printf("libc memset %10" PRIu64 " %s; ", libc, format_bps(buffer_size, libc));
            printf("asm memset %10" PRIu64 " %s; ", mine, format_bps(buffer_size, mine));
            printf("\n");
        }
        buffer_size *= 4;
    } while (buffer_size <= MAX_BUFFER_SIZE);
}

static void validate_memset(void)
{
    size_t dstalign, size;
    int c;
    const size_t maxsize = 256;

    printf("testing memset for correctness\n");

    for (dstalign = 0; dstalign < 64; dstalign++) {
        printf("align %zu\n", dstalign);
        for (size = 0; size < maxsize; size++) {
            for (c = -1; c < 257; c++) {

                fillbuf(dst, maxsize * 2, 123514);
                fillbuf(dst2, maxsize * 2, 123514);

                c_memset(dst + dstalign, c, size);
                mymemset(dst2 + dstalign, c, size);

                int comp = memcmp(dst, dst2, maxsize * 2);
                if (comp != 0) {
                    printf("error! align %zu, c 0x%hhx, size %zu\n",
                           dstalign, (unsigned char)c, size);
                }
            }
        }
    }
}

int main(int argc, char *argv[]) {
    int err = 0;
    err |= posix_memalign((void **)&src, 64, MAX_BUFFER_SIZE + 256);
    err |= posix_memalign((void **)&dst, 64, MAX_BUFFER_SIZE + 256);
    err |= posix_memalign((void **)&src2, 64, MAX_BUFFER_SIZE + 256);
    err |= posix_memalign((void **)&dst2, 64, MAX_BUFFER_SIZE + 256);
    if (err)
        return 1;

    validate_memcpy();
    validate_memset();

    bench_memcpy();
    bench_memset();

    return 0;
}

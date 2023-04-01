/*
 * Copyright (c) 2008-2014 Travis Geiselbrecht
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <malloc.h>
#include <inttypes.h>
#include <time.h>

static uint8_t *src;
static uint8_t *dst;

static uint8_t *src2;
static uint8_t *dst2;

#define BUFFER_SIZE (64*1024*1024)
#define TOTAL_TRANSFER_SIZE (1024*1024*1024) // target transfer size per benchmark
//#define ITERATIONS (1024*1024*1024 / BUFFER_SIZE) // enough iterations to have to copy/set 1GB of memory

#if 0
static inline void *mymemcpy(void *dest, const void *source, size_t len) { return memcpy(dest, source, len); }
static inline void *mymemset(void *dest, int c, size_t len) { return memset(dest, c, len); }
#else
// if we're testing our own memcpy, use this
extern void *mymemcpy(void *dst, const void *src, size_t len);
extern void *mymemset(void *dst, int c, size_t len);
#endif

// 64bit nanoseconds
typedef uint64_t my_time_t;

static my_time_t current_time() {
    struct timespec tv;

    clock_gettime(CLOCK_MONOTONIC, &tv);

    uint64_t res = tv.tv_nsec + tv.tv_sec * 1000000000;

    return res;
}

// print bytes/sec in a human readable form
static const char *bytes_per_sec(uint64_t bytes, my_time_t t) {
    static char strbuf[128];

    uint64_t temp = bytes * 1000000000ULL / t;

    if (temp > 1024*1024*1024) {
        snprintf(strbuf, sizeof(strbuf), "%.3f GB/sec", (double)temp / (1024*1024*1024));
    } else if (temp > 1024*1024) {
        snprintf(strbuf, sizeof(strbuf), "%.3f MB/sec", (double)temp / (1024*1024));
    } else {
        snprintf(strbuf, sizeof(strbuf), "%" PRIu64 " bytes/sec", temp);
    }
    return strbuf;
}

/* reference implementations of memmove/memcpy */
typedef long word;

#define lsize sizeof(word)
#define lmask (lsize - 1)

static void *c_memmove(void *dest, void const *source, size_t count) {
    char *d = (char *)dest;
    const char *s = (const char *)source;
    int len;

    if (count == 0 || dest == source)
        return dest;

    if ((long)d < (long)s) {
        if (((long)d | (long)s) & lmask) {
            // source and/or dest do not align on word boundary
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

static void *c_memset(void *s, int c, size_t count) {
#if 0
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
#else
    char *xs = (char *) s;

    for ( ; count > 0; count-- ) {
        *xs++ = c;
    }

    return s;
#endif
}

static void *null_memcpy(void *dest, const void *source, size_t len) {
    return dest;
}

__attribute__((noinline))
static my_time_t bench_memcpy_routine(void *memcpy_routine(void *, const void *, size_t), size_t srcalign, size_t dstalign, size_t iterations) {
    my_time_t t0;

    t0 = current_time();
    for (size_t i=0; i < iterations; i++) {
        memcpy_routine(dst + dstalign, src + srcalign, BUFFER_SIZE);
    }
    return current_time() - t0;
}

static void bench_memcpy(void) {
    my_time_t null, c, libc, mine;
    size_t srcalign, dstalign;

    printf("memcpy speed test\n");

    for (srcalign = 0; srcalign < 64; ) {
        for (dstalign = 0; dstalign < 64; ) {
            const size_t iterations = TOTAL_TRANSFER_SIZE / BUFFER_SIZE;

            null = bench_memcpy_routine(&null_memcpy, srcalign, dstalign, iterations);
            c = bench_memcpy_routine(&c_memmove, srcalign, dstalign, iterations);
            libc = bench_memcpy_routine(&memcpy, srcalign, dstalign, iterations);
            mine = bench_memcpy_routine(&mymemcpy, srcalign, dstalign, iterations);

            printf("srcalign %zu, dstalign %zu: ", srcalign, dstalign);
            //printf("   null memcpy %" PRIu64 " ns\n", null);
            printf("c memcpy %" PRIu64 " ns, %s; ", c, bytes_per_sec(BUFFER_SIZE * iterations, c));
            printf("libc memcpy %" PRIu64 "  ns, %s; ", libc, bytes_per_sec(BUFFER_SIZE * iterations, libc));
            printf("my memcpy %" PRIu64 " ns, %s; ", mine, bytes_per_sec(BUFFER_SIZE * iterations, mine));
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
}

static void fillbuf(void *ptr, size_t len, uint32_t seed) {
    size_t i;

    for (i = 0; i < len; i++) {
        ((char *)ptr)[i] = seed;
        seed *= 0x1234567;
    }
}

static void validate_memcpy(void) {
    size_t srcalign, dstalign, size;
    const size_t maxsrcalign = 64;
    const size_t maxdstalign = 64;
    const size_t maxsize = 256;

    printf("testing memcpy for correctness\n");

    /*
     * do the simple tests to make sure that memcpy doesn't color outside
     * the lines for all alignment cases
     */
    printf("srcalign 0..%zu, dstalign 0..%zu, size 0..%zu\n", maxsrcalign, maxdstalign, maxsize);
    for (srcalign = 0; srcalign < maxsrcalign; srcalign++) {
        //printf("srcalign %zu\n", srcalign);
        for (dstalign = 0; dstalign < maxdstalign; dstalign++) {
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

static my_time_t bench_memset_routine(void *memset_routine(void *, int, size_t), size_t dstalign, size_t len, size_t iterations) {
    my_time_t t0;

    t0 = current_time();
    for (size_t i=0; i < iterations; i++) {
        memset_routine(dst + dstalign, 0, len);
    }
    return current_time() - t0;
}

static void bench_memset(void) {
    my_time_t c, libc, mine;
    size_t dstalign;
    size_t size;
    const size_t maxalign = 64;

    printf("memset speed test\n");

    for (dstalign = 0; dstalign < maxalign; dstalign++) {
        for (size = 1; size <= BUFFER_SIZE; size <<=1) {
            const size_t iterations = TOTAL_TRANSFER_SIZE / size;

            c = bench_memset_routine(&c_memset, dstalign, size, iterations);
            libc = bench_memset_routine(&memset, dstalign, size, iterations);
            mine = bench_memset_routine(&mymemset, dstalign, size, iterations);

            printf("dstalign %zu size %zu: ", dstalign, size);
            printf("c memset %" PRIu64 " ns, %s; ", c, bytes_per_sec(size * iterations, c));
            printf("libc memset %" PRIu64 " ns, %s; ", libc, bytes_per_sec(size * iterations, libc));
            printf("my memset %" PRIu64 " ns, %s; ", mine, bytes_per_sec(size * iterations, mine));
            printf("\n");
        }
    }
}

static void validate_memset(void) {
    size_t dstalign, size;
    int c;
    const size_t maxalign = 64;
    const size_t maxsize = 256;

    printf("testing memset for correctness\n");

    printf("align 0..%zu, size 0...%zu\n", maxalign, maxsize);
    for (dstalign = 0; dstalign < maxalign; dstalign++) {
        //printf("align %zd, size 0...%zu\n", dstalign, maxsize);
        for (size = 0; size < maxsize; size++) {
            for (c = -1; c < 257; c++) {

                fillbuf(dst, maxsize * 2, 123514);
                fillbuf(dst2, maxsize * 2, 123514);

                c_memset(dst + dstalign, c, size);
                mymemset(dst2 + dstalign, c, size);

                int comp = memcmp(dst, dst2, maxsize * 2);
                if (comp != 0) {
                    printf("error! align %zu, c 0x%x, size %zu\n", dstalign, c, size);
                }
            }
        }
    }
}

int main() {
    src = memalign(64, BUFFER_SIZE + 256);
    dst = memalign(64, BUFFER_SIZE + 256);
    src2 = memalign(64, BUFFER_SIZE + 256);
    dst2 = memalign(64, BUFFER_SIZE + 256);

    printf("src %p, dst %p\n", src, dst);
    printf("src2 %p, dst2 %p\n", src2, dst2);

    if (!src || !dst || !src2 || !dst2) {
        printf("failed to allocate all the buffers\n");
        goto out;
    }

    //validate_memcpy();
    //validate_memset();
    //bench_memcpy();
    bench_memset();

out:
    free(src);
    free(dst);
    free(src2);
    free(dst2);

    return 0;
}

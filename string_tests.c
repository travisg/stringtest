/*
 * Copyright (c) 2008-2023 Travis Geiselbrecht
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <getopt.h>
#include <inttypes.h>
#include <malloc.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint8_t *src;
static uint8_t *dst;

static uint8_t *src2;
static uint8_t *dst2;

#define BUFFER_SIZE (64*1024*1024)
#define TOTAL_TRANSFER_SIZE (256*1024*1024) // target transfer size per benchmark
#define MAX_ITERATIONS_MEMCPY (100000) // when computing the number of benchmark iterations, dont run more than this
#define MAX_ITERATIONS_MEMSET (100000) // when computing the number of benchmark iterations, dont run more than this

#define __NO_INLINE __attribute__((noinline))

// if we're testing our own memcpy, use this
extern void *mymemcpy_c(void *dst, const void *src, size_t len);
extern void *mymemset_c(void *dst, int c, size_t len);
extern void *mymemcpy_asm(void *dst, const void *src, size_t len);
extern void *mymemset_asm(void *dst, int c, size_t len);
#define mymemcpy mymemcpy_asm
#define mymemset mymemset_asm

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

    if (t == 0) {
        t = 1;
    }

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
__NO_INLINE
static void *c_memcpy(void *dest, void const *source, size_t count) {
    char *xd = (char *)dest;
    const char *xs = (const char *)source;

    if (count == 0 || dest == source)
        return dest;

    for ( ; count > 0; count-- ) {
        *xd++ = *xs++;
    }

    return dest;
}

__NO_INLINE
static void *c_memset(void *s, int c, size_t count) {
    char *xs = (char *) s;

    for ( ; count > 0; count-- ) {
        *xs++ = c;
    }

    return s;
}

__NO_INLINE
static void *null_memcpy(void *dest, const void *source, size_t len) {
    return dest;
}

__NO_INLINE
static void *null_memset(void *dest, int c, size_t len) {
    return dest;
}

__NO_INLINE
static my_time_t bench_memcpy_routine(void *memcpy_routine(void *, const void *, size_t), size_t srcalign, size_t dstalign, size_t size, size_t iterations) {
    my_time_t t0;

    uint8_t * const d = dst + dstalign;
    uint8_t * const s = src + srcalign;

    t0 = current_time();
    for (size_t i=0; i < iterations; i++) {
        memcpy_routine(d, s, size);
    }
    return current_time() - t0;
}

__NO_INLINE
static void bench_memcpy(void) {
    my_time_t null, c, libc, mine;
    size_t srcalign, dstalign;

    printf("memcpy speed test\n");

    for (srcalign = 0; srcalign < 64; ) {
        for (dstalign = 0; dstalign < 64; ) {
            for (size_t size = 1; size <= BUFFER_SIZE; size <<=1) {
                size_t iterations = TOTAL_TRANSFER_SIZE / size;
                if (iterations > MAX_ITERATIONS_MEMCPY) {
                    iterations = MAX_ITERATIONS_MEMCPY;
                }

                null = bench_memcpy_routine(&null_memcpy, srcalign, dstalign, size, iterations);
                c = bench_memcpy_routine(&c_memcpy, srcalign, dstalign, size, iterations);
                libc = bench_memcpy_routine(&memcpy, srcalign, dstalign, size, iterations);
                mine = bench_memcpy_routine(&mymemcpy, srcalign, dstalign, size, iterations);

                printf("srcalign %zu, dstalign %zu, size %zu, iter %zu: ", srcalign, dstalign, size, iterations);
                printf("null (overhead) %" PRIu64 " ns; ", null);
                printf("c memcpy %" PRIu64 " ns, %s; ", c - null, bytes_per_sec(size * iterations, c - null));
                printf("libc memcpy %" PRIu64 "  ns, %s; ", libc - null, bytes_per_sec(size * iterations, libc - null));
                printf("my memcpy %" PRIu64 " ns, %s; ", mine - null, bytes_per_sec(size * iterations, mine - null));
                printf("\n");
            }

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

__NO_INLINE
static void validate_memcpy(void) {
    size_t srcalign, dstalign, size;
    const size_t maxsrcalign = 64;
    const size_t maxdstalign = 64;
    const size_t maxsize = 256;
    size_t err_count = 0;
    const size_t max_err = 16;

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

                // fill the source and destination buffers with different random patterns
                fillbuf(src, maxsize * 2, 567);
                fillbuf(src2, maxsize * 2, 567);
                fillbuf(dst, maxsize * 2, 123514);
                fillbuf(dst2, maxsize * 2, 123514);

                // run the reference memcpy and memcpy under test on two separate source and dest buffers.
                memcpy(dst + dstalign, src + srcalign, size);
                void *res2 = mymemcpy(dst2 + dstalign, src2 + srcalign, size);

                // compare the results
                int comp = memcmp(dst, dst2, maxsize * 2);
                if (comp != 0) {
                    printf("error! srcalign %zu, dstalign %zu, size %zu\n", srcalign, dstalign, size);

                    for (size_t i = 0; i < size * 2; i++) {
                        printf("%zu: %#hhx %#hhx %c\n", i, dst[i], dst2[i], (dst[i] != dst2[i]) ? '*' : ' ');
                    }

                    err_count++;
                    if (err_count > max_err) {
                        printf("aborting after %zu errors\n", max_err);
                        return;
                    }
                }
                if (res2 != dst2 + dstalign) {
                    printf("error: return is not destination! srcalign %zu, dstalign %zu, size %zu\n", srcalign, dstalign, size);
                }
            }
        }
    }
}

__NO_INLINE
static my_time_t bench_memset_routine(void *memset_routine(void *, int, size_t), size_t dstalign, size_t len, size_t iterations) {
    my_time_t t0;

    uint8_t * const d = dst + dstalign;

    t0 = current_time();
    for (size_t i=0; i < iterations; i++) {
        memset_routine(d, 0, len);
    }
    return current_time() - t0;
}

__NO_INLINE
static void bench_memset(void) {
    my_time_t null, c, libc, mine;
    size_t dstalign;
    size_t size;
    const size_t maxalign = 64;

    printf("memset speed test\n");

    for (dstalign = 0; dstalign < maxalign;) {
        for (size = 1; size <= BUFFER_SIZE; size <<=1) {
            size_t iterations = TOTAL_TRANSFER_SIZE / size;
            if (iterations > MAX_ITERATIONS_MEMSET) {
                iterations = MAX_ITERATIONS_MEMSET;
            }

            /* compute the overhead of the benchmark routine by calling a null function. Take
             * the smallest of 3 runs.
             */
            null = UINT64_MAX;
            for (int i = 0; i < 3; i++) {
                my_time_t n = bench_memset_routine(&null_memset, dstalign, size, iterations);
                //printf("%" PRIu64 " %zu\n", n, iterations);
                if (n < null) {
                    null = n;
                }
            }
            c = bench_memset_routine(&c_memset, dstalign, size, iterations);
            libc = bench_memset_routine(&memset, dstalign, size, iterations);
            mine = bench_memset_routine(&mymemset, dstalign, size, iterations);

            printf("dstalign %zu size %zu (iter %zu): ", dstalign, size, iterations);
            printf("null (overhead) %" PRIu64 " ns; ", null);
            printf("c memset %" PRIu64 " ns, %s; ", c - null, bytes_per_sec(size * iterations, c - null));
            printf("libc memset %" PRIu64 " ns, %s; ", libc - null, bytes_per_sec(size * iterations, libc - null));
            printf("my memset %" PRIu64 " ns, %s; ", mine - null, bytes_per_sec(size * iterations, mine - null));
            printf("\n");
        }
        if (dstalign < 8)
            dstalign++;
        else
            dstalign <<= 1;
    }
}

__NO_INLINE
static void validate_memset(void) {
    size_t dstalign, size;
    int c;
    const size_t maxalign = 64;
    const size_t maxsize = 256;
    size_t err_count = 0;
    const size_t max_err = 16;

    printf("testing memset for correctness\n");

    printf("align 0..%zu, size 0...%zu\n", maxalign, maxsize);
    for (dstalign = 0; dstalign < maxalign; dstalign++) {
        //printf("\talign %zd, size 0...%zu\n", dstalign, maxsize);
        for (size = 0; size < maxsize; size++) {
            //printf("\t\talign %zd, size %zu\n", dstalign, size);
            for (c = -1; c < 257; c++) {
                //printf("\t\t\talign %zd, size %zu, c %d\n", dstalign, size, c);

                fillbuf(dst, maxsize * 2, 123514);
                fillbuf(dst2, maxsize * 2, 123514);

                memset(dst + dstalign, c, size);
                mymemset(dst2 + dstalign, c, size);

                int comp = memcmp(dst, dst2, maxsize * 2);
                if (comp != 0) {
                    printf("error! align %zu, c 0x%x, size %zu\n", dstalign, c, size);

                    for (size_t i = 0; i < size; i++) {
                        printf("%zu: %#hhx %#hhx\n", i, dst[i], dst2[i]);
                    }

                    err_count++;
                    if (err_count > max_err) {
                        printf("aborting after %zu errors\n", max_err);
                        return;
                    }
                }
            }
        }
    }
}

static void usage(char **argv) {
    fprintf(stderr, "usage: %s [-h] [-b/--bench] [-v/--validate] [-c/--memcpy] [-s/--memset]\n", argv[0]);
    fprintf(stderr, "\tAt least one of --bench or --validate must be specified ");
    fprintf(stderr, "as well as at least one of --memcpy or --memset.\n");

    exit(1);
}

int main(int argc, char **argv) {
    // choices of things to do
    bool do_bench = false;
    bool do_validate = false;
    bool do_memcpy = false;
    bool do_memset = false;

    // read in any overriding configuration from the command line
    for (;;) {
        int c;
        int option_index = 0;

        static struct option long_options[] = {
            {"bench", 0, 0, 'b'},
            {"memcpy", 0, 0, 'c'},
            {"help", 0, 0, 'h'},
            {"memset", 0, 0, 's'},
            {"validate", 0, 0, 'v'},
            {0, 0, 0, 0},
        };

        c = getopt_long(argc, argv, "bchsv", long_options, &option_index);
        if (c == -1)
            break;

        switch (c) {
            case 'b':
                do_bench = true;
                break;
            case 'c':
                do_memcpy = true;
                break;
            case 's':
                do_memset = true;
                break;
            case 'v':
                do_validate = true;
                break;
            case 'h':
            default:
                usage(argv);
                break;
        }
    }

    if (!do_bench && !do_validate) {
        fprintf(stderr, "neither bench nor validate options were specified\n");
        usage(argv);
    }
    if (!do_memset && !do_memcpy) {
        fprintf(stderr, "neither memcpy nor memset options were specified\n");
        usage(argv);
    }

    src = memalign(64, BUFFER_SIZE + 256);
    dst = memalign(64, BUFFER_SIZE + 256);
    src2 = memalign(64, BUFFER_SIZE + 256);
    dst2 = memalign(64, BUFFER_SIZE + 256);
    if (!src || !dst || !src2 || !dst2) {
        printf("failed to allocate all the buffers\n");
        goto out;
    }

    // touch all of the buffers to pre-fault them in
    memset(src, 0, BUFFER_SIZE + 256);
    memset(dst, 0, BUFFER_SIZE + 256);
    memset(src2, 0, BUFFER_SIZE + 256);
    memset(dst2, 0, BUFFER_SIZE + 256);

    // run various permutations of validations and benchmarks
    if (do_validate) {
        if (do_memset) {
            validate_memset();
        }
        if (do_memcpy) {
            validate_memcpy();
        }
    }
    if (do_bench) {
        if (do_memset) {
            bench_memset();
        }
        if (do_memcpy) {
            bench_memcpy();
        }
    }

out:
    free(src);
    free(dst);
    free(src2);
    free(dst2);

    return 0;
}

// vim: ts=4:sw=4:expandtab:

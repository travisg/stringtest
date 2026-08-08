# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A test harness to validate and benchmark memset/memcpy implementations for
various architectures (currently x86-64 and RISC-V 64). The build
auto-detects the host architecture (`uname -m`), so cross-arch work is done
by building/running natively on the target machine.

## Commands

- `make` — build into `build-string_tests-$(ARCH)/`. Also produces a
  disassembly listing at `build-string_tests-$(ARCH)/string_tests.lst`
  (useful for inspecting generated/hand-written asm).
- `make test` — build and run the correctness validation
  (`string_tests -v -c -s`).
- `make spotless` — remove all `build-*` directories (`make clean` only
  removes objects for the current arch).

The binary requires at least one mode flag and one routine flag:
`-b`/`--bench` and/or `-v`/`--validate`, plus `-c`/`--memcpy` and/or
`-s`/`--memset`. Example: `build-string_tests-x86_64/string_tests -b -s`
benchmarks memset only. There is no separate test framework; validation is
the test suite.

## Architecture

Three source files, linked statically:

- `string_tests.c` — the harness. Validation runs the routine under test
  and libc's version side by side on separate buffers across all src/dst
  alignments (0..64) and sizes (0..512), comparing full buffers to catch
  out-of-bounds writes. Benchmarks compare four implementations (a null
  routine for overhead baseline, a bytewise C loop, libc, and "mine") and
  subtract the null-routine time from reported numbers.
- `myroutines.c` — scratch space for candidate C implementations
  (`mymemcpy_c`, `mymemset_c`).
- `asm-$(ARCH).S` — hand-written asm implementations (`mymemset_asm`,
  `mymemcpy_asm`, and on RISC-V `*_asm_vector` variants gated by
  `#if __riscv_vector`). Adding a new architecture requires an
  `asm-<arch>.S` providing these symbols, since the makefile always links
  `asm-$(ARCH).o`.

Validation runs against every implementation in the `impls` table in
`string_tests.c` (C, asm, and — when built with vector support — the
vector variants), and validation failures set a nonzero exit code, which
is what makes `make test` meaningful in CI. Benchmarks test a single
implementation as "mine", selected by the `#define mymemcpy` /
`#define mymemset` lines near the top of `string_tests.c`.

RISC-V `-march`/`-mtune` flags are set in the makefile and tuned for
specific boards (SiFive U74 / VisionFive 2 active; a SpacemiT vector
variant is commented out). Enabling the vector routines requires a `v` in
`-march`. `-fno-builtin` is required so the compiler doesn't replace the
reference C loops with libc calls.

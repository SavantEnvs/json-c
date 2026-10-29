#!/usr/bin/env bash
# Builds the sanitized json-c static lib, the four OSS-Fuzz libFuzzer harnesses (+ -standalone
# reproducers), and the upstream ctest suite with normal flags (run by mayhem/test.sh).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESSES="json_array_fuzzer json_object_fuzzer json_pointer_fuzzer tokener_parse_ex_fuzzer"

# 1) Sanitized + SanCov-instrumented static library (build/ is gitignored upstream).
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
cmake -S . -B build/fuzz -G Ninja \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$FUZZ_CFLAGS" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DDISABLE_WERROR=ON
cmake --build build/fuzz -j"$MAYHEM_JOBS"
LIB="$SRC/build/fuzz/libjson-c.a"
INCS="-I$SRC/build/fuzz -I$SRC"

# 2) Harnesses: libFuzzer binary + standalone reproducer. The in-tree OSS-Fuzz harnesses are used as-is.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
for h in $HARNESSES; do
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 $INCS $LIB_FUZZING_ENGINE \
        "$SRC/fuzz/$h.cc" /tmp/lsan_off.o "$LIB" -o "/mayhem/$h"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 $INCS \
        "$SRC/fuzz/$h.cc" /tmp/standalone_main.o /tmp/lsan_off.o "$LIB" -o "/mayhem/$h-standalone"
done

# 3) Upstream test suite with NORMAL flags (independent build dir, also under gitignored build/).
cmake -S . -B build/tests -G Ninja \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
    -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
    -DBUILD_APPS=ON -DBUILD_TESTING=ON -DDISABLE_WERROR=ON
cmake --build build/tests -j"$MAYHEM_JOBS"

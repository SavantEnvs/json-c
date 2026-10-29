#!/usr/bin/env bash
#
# mayhem/test.sh — RUN json-c's own ctest suite (built by mayhem/build.sh in build/tests). PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BUILD_DIR="$SRC/build/tests"
[ -f "$BUILD_DIR/CTestTestfile.cmake" ] || { echo "test build missing: $BUILD_DIR (mayhem/build.sh should have produced it)" >&2; emit_ctrf cmake-ctest 0 1 0; exit 1; }

# Each upstream test diffs the program's output against a committed *.expected file (or asserts values).
out=$(cd "$BUILD_DIR" && ctest --output-on-failure -j"$MAYHEM_JOBS" 2>&1)
rc=$?
echo "$out"

line=$(printf '%s\n' "$out" | grep -E 'tests passed, [0-9]+ tests failed out of [0-9]+' | tail -1)
if [ -z "$line" ]; then
  echo "could not parse ctest summary" >&2
  emit_ctrf cmake-ctest 0 1 0
  exit 1
fi
failed=$(printf '%s\n' "$line" | sed -E 's/.*, ([0-9]+) tests failed out of.*/\1/')
total=$(printf '%s\n' "$line" | sed -E 's/.*out of ([0-9]+).*/\1/')
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
passed=$(( total - failed ))
[ "$passed" -ge 0 ] || passed=0
emit_ctrf cmake-ctest "$passed" "$failed" 0

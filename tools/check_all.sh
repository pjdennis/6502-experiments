#!/bin/bash
# Run every regression check the repo has. The reorganization must keep all of
# these green (docs/REORGANIZATION_PLAN.md, rule R1). CI runs the same steps.
#
#   tools/check_all.sh [firmware|asm1|asm2|emulator]...   (default: all)
#
# Needs on PATH: vasm6502_oldstyle, gcc, g++, make, python3, hexdump.
# The emulator suite also uses 64tass, java + $PROG8C (default /tmp/prog8c.jar)
# and Python playwright; those tests SKIP when the tool is missing.
# The slow opt-in suites (Harte, P1_WENDY_SELFHOST, MERGE_SORT_FULL_N) are not run.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Upload scripts and asm1's Makefile call ./vasm6502_oldstyle and ../vasm6502_oldstyle
# (both gitignored); point them at the one on PATH if they are missing.
VASM="$(command -v vasm6502_oldstyle)" || { echo "vasm6502_oldstyle not on PATH"; exit 1; }
[ -e vasm6502_oldstyle ] || ln -s "$VASM" vasm6502_oldstyle
[ -e ../vasm6502_oldstyle ] || ln -s "$VASM" ../vasm6502_oldstyle 2>/dev/null || true

failed=()

firmware() {
  python3 -m unittest discover -s tools/tests &&
    python3 tools/firmware_manifest.py check
}

asm1() {
  # asmtestgen.sh always exits 0 and, without hexdump, "passes" by diffing two
  # empty dumps -- so require hexdump and check the printed verdicts instead.
  command -v hexdump >/dev/null || { echo "hexdump not on PATH"; return 1; }
  local log
  log="$(cd assembler && ./asmtestgen.sh </dev/null 2>&1)"
  echo "$log" | tail -3
  echo "$log" | grep -qx 'OK' && echo "$log" | grep -qx 'Assembled'
}

asm2() {
  (cd assembler2 && ./verify.sh)
}

emulator() {
  make -C assembler2 test
}

suites=("$@")
[ ${#suites[@]} -eq 0 ] && suites=(firmware asm1 asm2 emulator)

for s in "${suites[@]}"; do
  echo "=== $s ==="
  if "$s"; then echo "=== $s: PASS ==="; else echo "=== $s: FAIL ==="; failed+=("$s"); fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "ALL PASSED: ${suites[*]}"

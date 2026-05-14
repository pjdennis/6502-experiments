#!/bin/sh
# End-to-end goldens for wendy2_merge_sort.s.
#
# Uses --lcd-trace to assert on intermediate display states (not just
# the final frame), since the merge sort moves through visually distinct
# phases (init -> fill -> sort -> verify -> result) and the bugs we
# care about are typically per-phase.
#
# Skip pattern matches the other wendy2c shell tests.

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
EMU="$REPO_ROOT/assembler2/emulator/emulator.out"
OUT="${OUT_DIR:-/tmp/wendy2c-merge-sort}"
VASM=vasm6502_oldstyle

mkdir -p "$OUT"

if ! command -v "$VASM" >/dev/null 2>&1; then
    echo "merge_sort_goldens: SKIP ($VASM not on PATH)"
    exit 0
fi

if [ ! -x "$EMU" ]; then
    echo "merge_sort_goldens: FAIL ($EMU not built; run 'make' first)"
    exit 1
fi

run_vasm() {
    out=$1
    src=$2
    shift 2
    log="$OUT/$(basename "$src").vasm.log"
    if ! "$VASM" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc \
            "$@" -o "$out" "$src" >"$log" 2>&1; then
        echo "merge_sort_goldens: vasm failed assembling $src (log: $log)"
        cat "$log"
        exit 1
    fi
}

# Boot ROM is shared with the other wendy2c tests.
echo "merge_sort_goldens: building boot ROM"
run_vasm "$OUT/boot.bin" "$REPO_ROOT/upload_and_run_eeprom_wendy2c.s"

# Assert that every PATTERN appears in TRACE, in order. PATTERN is a
# fixed-string substring (grep -F).
assert_trace_contains_in_order() {
    trace=$1
    shift
    last_line=0
    for pat in "$@"; do
        # Find the first occurrence at or after last_line+1.
        line=$(awk -v pat="$pat" -v start="$((last_line + 1))" '
            NR < start { next }
            index($0, pat) > 0 { print NR; exit }
        ' "$trace")
        if [ -z "$line" ]; then
            echo "merge_sort_goldens: FAIL trace missing pattern '$pat' after line $last_line"
            echo "  trace was:"
            sed 's/^/    /' "$trace"
            exit 1
        fi
        last_line=$line
    done
}

# ---- skeleton-phase test ----
# At this stage the program just shows a startup banner and stops.
# The trace must contain a frame with both 'Merge Sort' (line 1) and
# the 'N=64' marker (line 2) -- we assert in order so layout matters.
echo "merge_sort_goldens: case skeleton"
run_vasm "$OUT/skeleton.bin" "$REPO_ROOT/wendy2_merge_sort.s" \
    -DN_ELEMENTS=64
python3 "$REPO_ROOT/assembler2/emulator/wendy2_upload.py" \
    "$OUT/skeleton.bin" -o "$OUT/skeleton.framed" >"$OUT/skeleton.upload.log"

TRACE="$OUT/skeleton.lcd-trace"
rm -f "$TRACE"
"$EMU" "$OUT/boot.bin" \
    --machine wendy2c \
    --serial-input "$OUT/skeleton.framed" \
    --lcd-trace "$TRACE" \
    --cycle-cap 10000000 \
    >"$OUT/skeleton.stdout" 2>"$OUT/skeleton.stderr" || true

assert_trace_contains_in_order "$TRACE" \
    "|Merge Sort      |" \
    "|N=64 Ready      |"
echo "  PASS skeleton (banner + N=64)"

echo "merge_sort_goldens: all PASS"

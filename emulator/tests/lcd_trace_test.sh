#!/bin/sh
# End-to-end test for the --lcd-trace emulator option.
#
# Uses hello_ram_4000_wendy2c.s as a payload (already exercised by
# wendy2c_goldens). That program prints "Hi! I'm Wendy 2." on line 1
# and then loops updating a 16-bit hex counter on line 2, so the LCD
# changes many times -- a good stress test for the trace mechanism.
#
# Skip pattern matches the other wendy2c shell tests.

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
EMU="$REPO_ROOT/assembler2/emulator/emulator.out"
OUT="${OUT_DIR:-/tmp/wendy2c-lcd-trace}"
VASM=vasm6502_oldstyle

mkdir -p "$OUT"

if ! command -v "$VASM" >/dev/null 2>&1; then
    echo "lcd_trace_test: SKIP ($VASM not on PATH)"
    exit 0
fi

if [ ! -x "$EMU" ]; then
    echo "lcd_trace_test: FAIL ($EMU not built; run 'make' first)"
    exit 1
fi

run_vasm() {
    out=$1
    src=$2
    log="$OUT/$(basename "$src").vasm.log"
    if ! "$VASM" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc \
            -o "$out" "$src" >"$log" 2>&1; then
        echo "lcd_trace_test: vasm failed assembling $src (log: $log)"
        cat "$log"
        exit 1
    fi
}

echo "lcd_trace_test: building boot ROM + hello payload"
run_vasm "$OUT/boot.bin"  "$REPO_ROOT/upload_and_run_eeprom_wendy2c.s"
run_vasm "$OUT/hello.bin" "$REPO_ROOT/hello_ram_4000_wendy2c.s"
python3 "$REPO_ROOT/assembler2/emulator/wendy2_upload.py" \
    "$OUT/hello.bin" -o "$OUT/hello.framed" >"$OUT/hello.upload.log"

TRACE="$OUT/hello.lcd-trace"
rm -f "$TRACE"

"$EMU" "$OUT/boot.bin" \
    --machine wendy2c \
    --serial-input "$OUT/hello.framed" \
    --lcd-trace "$TRACE" \
    --cycle-cap 5000000 \
    >"$OUT/hello.stdout" 2>"$OUT/hello.stderr" || true

if [ ! -s "$TRACE" ]; then
    echo "lcd_trace_test: FAIL trace file empty or missing ($TRACE)"
    echo "  stderr was:"
    sed 's/^/    /' "$OUT/hello.stderr"
    exit 1
fi

# Expect at least one "Hi! I'm Wendy 2." frame.
if ! grep -q "Hi! I'm Wendy 2." "$TRACE"; then
    echo "lcd_trace_test: FAIL trace missing 'Hi! I'm Wendy 2.'"
    echo "  trace head:"
    sed 's/^/    /' "$TRACE" | head -40
    exit 1
fi

# The hello loop updates line 2 on every iteration, so we expect many
# distinct frames -- header-line count is a quick proxy.
frames=$(grep -c '^--- ' "$TRACE" || true)
if [ "$frames" -lt 2 ]; then
    echo "lcd_trace_test: FAIL expected multiple frames, got $frames"
    sed 's/^/    /' "$TRACE" | head -40
    exit 1
fi

# Each frame must have exactly two row lines (16x2 LCD).
rows=$(grep -c '^|' "$TRACE" || true)
expected=$((frames * 2))
if [ "$rows" -ne "$expected" ]; then
    echo "lcd_trace_test: FAIL row-count mismatch: $rows rows, expected $expected (= $frames frames * 2)"
    exit 1
fi

# Negative test: --lcd-trace without --machine wendy2c must fail.
"$EMU" /dev/null --lcd-trace /tmp/never >"$OUT/neg.stdout" 2>"$OUT/neg.stderr" && {
    echo "lcd_trace_test: FAIL emulator accepted --lcd-trace without --machine wendy2c"
    exit 1
}
if ! grep -q "lcd-trace.*wendy2c" "$OUT/neg.stderr"; then
    echo "lcd_trace_test: FAIL expected diagnostic about wendy2c requirement"
    sed 's/^/    /' "$OUT/neg.stderr"
    exit 1
fi

echo "lcd_trace_test: PASS ($frames frames, $rows rows)"

#!/bin/sh
# wendy2c emulator end-to-end demo.
#
# Builds the wendy2c boot ROM (upload_and_run_eeprom_wendy2c.s) and a
# small "Hi! I'm Wendy 2." payload (hello_ram_4000_wendy2c.s) using
# vasm, frames the payload with the same length+payload+BSD-checksum
# layout as transfer_115200_wendy.py, then launches the emulator with
# the boot ROM in the EEPROM and the framed bytes preloaded into the
# serial-USB chip's queue.
#
# The CPU runs the real wendy2c boot code, which negotiates the
# serial protocol with our SERIAL_USB chip, copies the payload into
# RAM at $4000, jumps to it, and then prints to the LCD.
#
# Usage:
#   demo_wendy2c.sh [--live]
#
#   --live  Launch the emulator's live ANSI render of the LCD, LED,
#           button, and VIA pin state. Runs uncapped; q/ESC/Ctrl-C in
#           the live panel quits. Without this flag the emulator runs
#           briefly under a cycle cap and prints the final LCD frame.
#
# Env overrides:
#   DEMO_PAYLOAD     path to a wendy2c .s file (default hello_ram_4000)
#   DEMO_CYCLE_CAP   non-live: emulator --cycle-cap (default 3000000)
#                    live:     no cap by default; this overrides if set
#
# Requires:
#   - vasm6502_oldstyle on PATH
#   - python3 on PATH
#   - the emulator built (cd assembler2 && make)
#   - run from the repo root

set -e

LIVE=0
while [ $# -gt 0 ]; do
    case $1 in
        --live) LIVE=1; shift ;;
        -h|--help)
            awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
            exit 0 ;;
        *)
            echo "error: unknown option '$1' (try --help)" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASM2="$REPO_ROOT/assembler2"
OUT_DIR="${OUT_DIR:-/tmp/wendy2c-demo}"
mkdir -p "$OUT_DIR"

# Default payload is the existing "Hi! I'm Wendy 2." program; override
# via DEMO_PAYLOAD env to point at any other wendy2c .s file that
# assembles to load at $4000.
PAYLOAD_SRC="${DEMO_PAYLOAD:-$REPO_ROOT/hello_ram_4000_wendy2c.s}"

VASM=vasm6502_oldstyle
command -v "$VASM" >/dev/null 2>&1 || {
    echo "error: $VASM not on PATH; install from http://sun.hasenbraten.de/vasm/" >&2
    exit 1
}

# Run vasm and fail fast on error. The previous version piped vasm output
# to `tail -5`, which masked vasm's exit status (only `tail`'s status was
# visible to `set -e`), so an option vasm did not recognise -- e.g. older
# vasm releases lacking -ignore-mult-inc -- silently produced no output
# and the emulator then failed with "could not load ROM image".
run_vasm() {
    out=$1
    src=$2
    log="$OUT_DIR/$(basename "$src").vasm.log"
    if ! "$VASM" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc \
            -o "$out" "$src" >"$log" 2>&1; then
        echo "error: vasm failed assembling $src (full log: $log):" >&2
        cat "$log" >&2
        exit 1
    fi
    tail -5 "$log"
}

cd "$REPO_ROOT"

echo ">> assembling boot ROM (upload_and_run_eeprom_wendy2c.s)"
run_vasm "$OUT_DIR/wendy2c_boot.bin" upload_and_run_eeprom_wendy2c.s

echo ">> assembling payload ($PAYLOAD_SRC)"
run_vasm "$OUT_DIR/payload.bin" "$PAYLOAD_SRC"

echo ">> framing payload"
python3 "$ASM2/emulator/wendy2_upload.py" \
    "$OUT_DIR/payload.bin" -o "$OUT_DIR/payload.framed"

cd "$ASM2"

if [ "$LIVE" -eq 1 ]; then
    echo ">> launching live render (q / ESC / Ctrl-C to quit)"
    # In live mode the emulator defaults to no cycle cap, just like the
    # nmos-default --console / --terminal modes. DEMO_CYCLE_CAP can
    # override if you want a recording of fixed length.
    if [ -n "${DEMO_CYCLE_CAP:-}" ]; then
        exec ./emulator/emulator.out \
            "$OUT_DIR/wendy2c_boot.bin" \
            --machine wendy2c \
            --serial-input "$OUT_DIR/payload.framed" \
            --live \
            --cycle-cap "$DEMO_CYCLE_CAP"
    else
        exec ./emulator/emulator.out \
            "$OUT_DIR/wendy2c_boot.bin" \
            --machine wendy2c \
            --serial-input "$OUT_DIR/payload.framed" \
            --live
    fi
fi

echo ">> running emulator"
echo "   (the boot ROM displays its 'Ready' screen briefly, then upload"
echo "    starts; on completion the payload writes to the LCD which we"
echo "    print on exit. Ctrl-C to stop early.)"
echo
# Cap is in oscillator ticks (~2 per CPU cycle). ~1.5M is the minimum for
# the payload's LCD frame to appear after the upload; 3M leaves headroom
# while still exiting in well under a second. Override via DEMO_CYCLE_CAP.
exec ./emulator/emulator.out \
    "$OUT_DIR/wendy2c_boot.bin" \
    --machine wendy2c \
    --serial-input "$OUT_DIR/payload.framed" \
    --cycle-cap "${DEMO_CYCLE_CAP:-3000000}"

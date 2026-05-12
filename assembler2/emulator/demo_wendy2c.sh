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
# Requires:
#   - vasm6502_oldstyle on PATH
#   - python3 on PATH
#   - the emulator built (cd assembler2 && make)
#   - run from the repo root

set -e

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

echo ">> running emulator"
echo "   (the boot ROM displays its 'Ready' screen briefly, then upload"
echo "    starts; on completion the payload writes to the LCD which we"
echo "    print on exit. Ctrl-C to stop early.)"
echo
cd "$ASM2"
exec ./emulator/emulator.out \
    "$OUT_DIR/wendy2c_boot.bin" \
    --machine wendy2c \
    --serial-input "$OUT_DIR/payload.framed"

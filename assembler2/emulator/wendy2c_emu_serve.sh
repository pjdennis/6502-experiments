#!/bin/sh
# Run the wendy2c emulator with the upload-and-run boot ROM and an
# open --serial-link socket, ready to receive a payload from
# compile_and_upload_wendy2c_emu.sh (or wendy2c_emu_upload.py).
#
# This is the emulator's equivalent of plugging in real wendy2c
# hardware: the boot ROM sits in its "waiting for upload" state and
# the LCD shows the version/baud banner. In another terminal, run
# compile_and_upload_wendy2c_emu.sh foo.s to assemble and stream a
# payload across; the boot ROM receives it, verifies the BSD
# checksum, and jumps to $4000 to run it.
#
# Usage:
#   wendy2c_emu_serve.sh [--live | --web [--web-port N] [--web-bind ADDR]]
#                        [--audio] [--wav PATH]
#                        [--sock PATH] [--cycle-cap N]
#
#   --live          Interactive ANSI render of the LCD, LED, button,
#                   and VIA pins (default). q/ESC/Ctrl-C quits.
#   --web           Embedded HTTP+WS browser UI on http://127.0.0.1:8080/
#                   (override port with --web-port, bind with --web-bind).
#                   Mutually exclusive with --live.
#   --web-port N    TCP port for --web (default 8080; 0 picks ephemeral).
#   --web-bind ADDR IPv4 bind for --web (default 127.0.0.1).
#   --audio         Play the PB7 piezo line through the host audio
#                   device (Linux/WSL/PulseAudio/PipeWire/ALSA, macOS
#                   CoreAudio, Windows WASAPI).
#   --wav PATH      Record the piezo line to a WAV file.
#   --sock PATH     Unix socket for the serial link
#                   (default /tmp/wendy2c-link.sock).
#   --cycle-cap N   Optional emulator cycle cap (OSC ticks). Default
#                   is unlimited in --live / --web -- the user quits
#                   interactively. Useful for scripted recordings.
#
# Requires:
#   - vasm6502_oldstyle on PATH
#   - the emulator built (cd assembler2 && make)
#   - run from any directory; paths are resolved relative to this script

set -e

LIVE=1
WEB=0
WEB_PORT=8080
WEB_BIND=""
AUDIO=0
WAV=""
SOCK="/tmp/wendy2c-link.sock"
CYCLE_CAP=""

while [ $# -gt 0 ]; do
    case $1 in
        --live)  LIVE=1; WEB=0; shift ;;
        --web)   WEB=1; LIVE=0; shift ;;
        --web-port)
            if [ $# -lt 2 ]; then
                echo "error: --web-port requires a value" >&2; exit 1
            fi
            WEB_PORT=$2; WEB=1; LIVE=0; shift 2 ;;
        --web-bind)
            if [ $# -lt 2 ]; then
                echo "error: --web-bind requires a value" >&2; exit 1
            fi
            WEB_BIND=$2; WEB=1; LIVE=0; shift 2 ;;
        --audio) AUDIO=1; shift ;;
        --wav)
            if [ $# -lt 2 ]; then
                echo "error: --wav requires a path" >&2; exit 1
            fi
            WAV=$2; shift 2 ;;
        --sock)
            if [ $# -lt 2 ]; then
                echo "error: --sock requires a path" >&2; exit 1
            fi
            SOCK=$2; shift 2 ;;
        --cycle-cap)
            if [ $# -lt 2 ]; then
                echo "error: --cycle-cap requires a value" >&2; exit 1
            fi
            CYCLE_CAP=$2; shift 2 ;;
        -h|--help)
            awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
            exit 0 ;;
        *)
            echo "error: unknown option '$1' (try --help)" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASM2="$REPO_ROOT/assembler2"
EMU="$ASM2/emulator/emulator.out"
OUT_DIR="${OUT_DIR:-/tmp/wendy2c-emu-serve}"
mkdir -p "$OUT_DIR"

VASM=vasm6502_oldstyle
command -v "$VASM" >/dev/null 2>&1 || {
    echo "error: $VASM not on PATH; install from http://sun.hasenbraten.de/vasm/" >&2
    exit 1
}

if [ ! -x "$EMU" ]; then
    echo "error: emulator not built at $EMU; run 'cd $ASM2 && make'" >&2
    exit 1
fi

# Assemble the boot ROM if it's missing or older than its source.
BOOT_BIN="$OUT_DIR/wendy2c_boot.bin"
BOOT_SRC="$REPO_ROOT/upload_and_run_eeprom_wendy2c.s"
if [ ! -f "$BOOT_BIN" ] || [ "$BOOT_SRC" -nt "$BOOT_BIN" ] || \
        [ "$REPO_ROOT/upload_and_run.inc" -nt "$BOOT_BIN" ]; then
    echo ">> assembling boot ROM ($BOOT_SRC)"
    log="$OUT_DIR/boot.vasm.log"
    if ! (cd "$REPO_ROOT" && "$VASM" -wdc02 -wfail -Fbin -dotdir \
            -ignore-mult-inc -esc -o "$BOOT_BIN" \
            upload_and_run_eeprom_wendy2c.s) >"$log" 2>&1; then
        echo "error: boot ROM assembly failed (full log: $log):" >&2
        cat "$log" >&2
        exit 1
    fi
fi

# Clear any stale socket -- the emulator unlinks on start too, but
# doing it here makes the "is the server up?" check on the client
# side unambiguous.
rm -f "$SOCK"

set -- "$BOOT_BIN" --machine wendy2c --serial-link "$SOCK"
[ "$AUDIO" -eq 1 ] && set -- "$@" --audio
[ -n "$WAV" ] && set -- "$@" --wav "$WAV"
[ -n "$CYCLE_CAP" ] && set -- "$@" --cycle-cap "$CYCLE_CAP"

if [ "$WEB" -eq 1 ]; then
    echo ">> launching emulator (--web on port $WEB_PORT)"
    echo "   serial-link socket: $SOCK"
    echo "   upload from another terminal:"
    echo "     $ASM2/emulator/compile_and_upload_wendy2c_emu.sh foo.s --sock $SOCK"
    set -- "$@" --web --web-port "$WEB_PORT"
    [ -n "$WEB_BIND" ] && set -- "$@" --web-bind "$WEB_BIND"
elif [ "$LIVE" -eq 1 ]; then
    echo ">> launching emulator (--live)"
    echo "   serial-link socket: $SOCK"
    echo "   upload from another terminal:"
    echo "     $ASM2/emulator/compile_and_upload_wendy2c_emu.sh foo.s --sock $SOCK"
    set -- "$@" --live
fi

exec "$EMU" "$@"

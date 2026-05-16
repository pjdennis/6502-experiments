#!/bin/sh
# Launch the wendy2c emulator in web mode with the 5x10 LCD demo
# (lcd_5x10_demo_wendy2c.s) uploaded as the RAM payload. Convenience
# wrapper around assembler2/emulator/demo_wendy2c.sh -- by default
# starts the embedded HTTP+WebSocket server on http://127.0.0.1:8080/
# so you can open the page in a browser and watch the 10-row glyphs +
# walking underline cursor.
#
# Selects the 16x1-5x10 LCD panel layout by default so the web UI
# draws a single-row LCD with tall (5x10) cells and a 1-pixel blank
# row separating each glyph from the underline cursor -- matching a
# typical real-world 16x1 5x10 character display. Override with
# --lcd-panel 16x2 to fall back to the default 5x8 module render.
#
# Usage:
#   ./lcd_5x10_demo.sh                      # web mode, port 8080
#   ./lcd_5x10_demo.sh --web-port 9000      # different port
#   ./lcd_5x10_demo.sh --live               # terminal ANSI render instead
#
# Any flag passed to this script is forwarded to demo_wendy2c.sh
# verbatim.

set -e

cd "$(dirname "$0")"

DEMO_PAYLOAD="lcd_5x10_demo_wendy2c.s"
export DEMO_PAYLOAD

# Default to --web unless the caller asked for something else explicitly.
mode_set=0
panel_set=0
for arg in "$@"; do
    case "$arg" in
        --live|--web|--web-port|--web-bind) mode_set=1 ;;
        --lcd-panel) panel_set=1 ;;
    esac
done

if [ "$mode_set" -eq 0 ]; then
    set -- --web "$@"
fi
if [ "$panel_set" -eq 0 ]; then
    set -- "$@" --lcd-panel 16x1-5x10
fi

exec ./assembler2/emulator/demo_wendy2c.sh "$@"

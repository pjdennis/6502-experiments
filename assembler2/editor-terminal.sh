#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/emulator.out" "$SCRIPT_DIR/editor/out/editor_terminal.out" --load 0400 --terminal --baud 9600 --mhz 2 "$@"

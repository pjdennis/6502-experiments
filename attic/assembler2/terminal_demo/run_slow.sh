#!/bin/bash
set -e
cd "$(dirname "$0")/.."
mkdir -p terminal_demo/out
./emulator/emulator.out 23/out/asm.out terminal_demo/demo.asm terminal_demo/out/demo.out &&
./emulator/emulator.out terminal_demo/out/demo.out --load 0400 --terminal --baud 50 --mhz 2

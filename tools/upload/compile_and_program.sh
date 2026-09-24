#!/bin/sh
# Usage: compile_and_program.sh <program.s>   (writes a.out in the current directory)
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/../../firmware/vasm" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc $1 && minipro -p AT28C256 -w a.out || echo -e '\x1B[1;31mFailed!\x1B[0m\a'

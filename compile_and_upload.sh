#!/bin/sh

./vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir $1.s -o $1.out && ./upload_file.sh .$1.out && cksum -o 1 $1.out | sed -n 's/\(^[0-9]*\) .*/obase=16; \1/p' | bc

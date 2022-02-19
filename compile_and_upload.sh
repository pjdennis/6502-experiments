#!/bin/sh

./vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc $1 && python3 transfer.py a.out && cksum -o 1 a.out | sed -n 's/\(^[0-9]*\) .*/obase=16; \1/p' | bc && python3 -c "import os; print(hex(os.path.getsize('a.out')))"

#!/bin/sh

./vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc $1 && python3 transfer_with_length_2.py a.out

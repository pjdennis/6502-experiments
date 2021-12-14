#!/bin/sh

./vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc $1 && python3 transfer_19200.py --noreset a.out

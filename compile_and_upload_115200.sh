#!/bin/sh

./vasm6502_oldstyle -quiet -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc $1 && python3 transfer.py --port=/dev/cu.SLAB_USBtoUART --baudrate=115200 a.out

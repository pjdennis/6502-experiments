#!/bin/sh

./vasm6502_oldstyle -quiet -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc $1 && python3 transfer.py --noreset --port=/dev/cu.usbserial-1420 --baudrate=115200 a.out

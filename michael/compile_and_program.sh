#!/bin/sh

../vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc $1 && minipro -p AT28C256 -w a.out || echo -e '\x1B[1;31mFailed!\x1B[0m\a'

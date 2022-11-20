#!/bin/zsh

gcc -o emulator.out emulator.c &&
  ../vasm6502_oldstyle -quiet -wfail -Fbin -dotdir -esc -o asm4v.out asm4v.asm &&
  ./emulator.out asm4v.out 2000 asm4b.asm asm4b.out &&
  ./emulator.out asm4b.out 2000 asm4b.asm asm4b2.out &&
  diff <(hexdump -C asm4b.out) <(hexdump -C asm4b2.out) &&
  hexdump -C asm4b2.out &&
  echo "OK"

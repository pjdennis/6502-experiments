#!/bin/bash

shopt -s extglob

rm -f !(emulator|sidebyside|asm0c|asm00).out &&
  make --quiet &&
  ./emulator.out asm00.out 2000 asm01.asm asm01.out &&
  ./emulator.out asm01.out 2000 asm02.asm asm02.out &&
  ./emulator.out asm02.out 2000 asm03.asm asm03.out &&
  ./emulator.out asm03.out 2000 asm04.asm asm04.out &&
  ./emulator.out asm04.out 2000 asm05.asm asm05.out &&
  ./emulator.out asm05.out 2000 asm06.asm asm06.out &&
  ./emulator.out asm06.out 2000 instgen07.asm instgen07.out &&
  ./emulator.out instgen07.out 2000 /dev/null inst07.asm.out &&
  cat inst07.asm.out asm07.asm > asm07c.asm.out &&
  ./emulator.out asm06.out 2000 asm07c.asm.out asm07c.out &&
  cat inst07.asm.out asm08.asm > asm08c.asm.out &&
  ./emulator.out asm07c.out 2000 asm08c.asm.out asm08c.out &&
  cat inst07.asm.out asm09.asm > asm09c.asm.out &&
  ./emulator.out asm08c.out 2000 asm09c.asm.out asm09c.out &&
  cat inst07.asm.out asm10.asm > asm10c.asm.out &&
  ./emulator.out asm09c.out 2000 asm10c.asm.out asm10c.out &&
  ./emulator.out asm10c.out 2000 instgen11.asm instgen11.out &&
  ./emulator.out instgen11.out 2000 /dev/null inst11.asm.out &&
  ./emulator.out asm10c.out 2000 asm11.asm asm11.out &&
  ./emulator.out asm11.out 2000 asm12.asm asm12.out &&
  ./emulator.out asm12.out 2000 /dev/null /dev/null instgen13.asm instgen13.out &&
  ./emulator.out instgen13.out 2000 /dev/null inst13.asm.out &&
  ./emulator.out asm12.out 2000 /dev/null /dev/null asm13.asm asm13.out &&
  ./emulator.out asm13.out 2000 /dev/null /dev/null instgen14.asm instgen14.out &&
  ./emulator.out instgen14.out 2000 /dev/null inst14.asm.out &&
  ./emulator.out asm13.out 2000 /dev/null /dev/null asm14.asm asm14.out &&
  ./emulator.out asm14.out 2000 /dev/null /dev/null instgen15.asm instgen15.out &&
  ./emulator.out instgen15.out 2000 /dev/null inst15.asm.out &&
  ./emulator.out asm14.out 2000 /dev/null /dev/null asm15.asm asm15.out &&
  ./emulator.out asm15.out 2000 /dev/null /dev/null asm15.asm asm15_2.out &&
  diff <(hexdump -C asm15.out) <(hexdump -C asm15_2.out) &&
  hexdump -C asm15_2.out | ./sidebyside.out

if [ $? -eq 0 ]; then
  echo "OK"
  ./emulator.out asm15_2.out 2000 /dev/null /dev/null test.asm test.out &&
  hexdump -C test.out &&
  echo "Assembled"
  if [ $? -eq 0 ]; then
    ./emulator.out test.out 1000 /dev/null - arg1 "arg 2"
  else
    echo "Did not assemble"
  fi
else
  echo "!!!Failed!!!"
fi

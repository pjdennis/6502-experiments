#!/bin/bash

make --quiet &&
  ./emulator.out asm4v.out 2000 asm4b.asm asm4b.out &&
  ./emulator.out asm4b.out 2000 asm4b2.asm asm4b2.out &&
  ./emulator.out asm4b2.out 2000 asm4b3.asm asm4b3.out &&
  ./emulator.out asm4b3.out 2000 asm4b4.asm asm4b4.out &&
  ./emulator.out asm4b4.out 2000 asm4b5.asm asm4b5.out &&
  ./emulator.out asm4b5.out 2000 instgen.asm instgen.out &&
  ./emulator.out instgen.out 2000 /dev/null inst.asm.out &&
  cat inst.asm.out asm4b6.asm > asm4b6c.asm.out &&
  ./emulator.out asm4b5.out 2000 asm4b6c.asm.out asm4b6c.out &&
  cat inst.asm.out asm4b7.asm > asm4b7c.asm.out &&
  ./emulator.out asm4b6c.out 2000 asm4b7c.asm.out asm4b7c.out &&
  cat inst.asm.out asm4b8.asm > asm4b8c.asm.out &&
  ./emulator.out asm4b7c.out 2000 asm4b8c.asm.out asm4b8c.out &&
  ./emulator.out asm4b8c.out 2000 asm4b8c.asm.out asm4b8c_2.out &&
  diff <(hexdump -C asm4b8c.out) <(hexdump -C asm4b8c_2.out) &&
  hexdump -C asm4b8c_2.out | ./sidebyside.out

if [ $? -eq 0 ]; then
  echo "OK"
  ./emulator.out asm4b7c.out 2000 test.asm test.asm.out &&
  hexdump -C test.asm.out &&
  echo "Assembled" || echo "Did not assemble"
else
  echo "!!!Failed!!!"
fi

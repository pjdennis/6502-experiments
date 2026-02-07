#!/bin/bash

set -e
shopt -s extglob

mkdir -p out
rm -f out/*.out out/*.asm.out
rm -rf {00..99}/out
make --quiet
echo "--- Version 00 ---"
(cd 00 && mkdir -p out && ../asm0c.out asm00.asm out/asm00.out)
echo "--- Version 01 ---"
(cd 01 && mkdir -p out && ../emulator.out ../00/out/asm00.out 2000 asm01.asm out/asm01.out)
echo "--- Version 02 ---"
(cd 02 && mkdir -p out && ../emulator.out ../01/out/asm01.out 2000 asm02.asm out/asm02.out)
echo "--- Version 03 ---"
(cd 03 && mkdir -p out && ../emulator.out ../02/out/asm02.out 2000 asm03.asm out/asm03.out)
echo "--- Version 04 ---"
(cd 04 && mkdir -p out && ../emulator.out ../03/out/asm03.out 2000 asm04.asm out/asm04.out)
echo "--- Version 05 ---"
(cd 05 && mkdir -p out && ../emulator.out ../04/out/asm04.out 2000 asm05.asm out/asm05.out)
echo "--- Version 06 ---"
(cd 06 && mkdir -p out && ../emulator.out ../05/out/asm05.out 2000 asm06.asm out/asm06.out)
echo "--- Version 07 ---"
(cd 07 && mkdir -p out &&
  ../emulator.out ../06/out/asm06.out 2000 instgen07.asm out/instgen07.out &&
  ../emulator.out out/instgen07.out 2000 /dev/null out/inst07.asm.out &&
  cat out/inst07.asm.out asm07.asm > out/asm07c.asm.out &&
  ../emulator.out ../06/out/asm06.out 2000 out/asm07c.asm.out out/asm07c.out)
echo "--- Version 08 ---"
(cd 08 && mkdir -p out &&
  ../emulator.out ../06/out/asm06.out 2000 instgen08.asm out/instgen08.out &&
  ../emulator.out out/instgen08.out 2000 /dev/null out/inst08.asm.out &&
  cat out/inst08.asm.out asm08.asm > out/asm08c.asm.out &&
  ../emulator.out ../07/out/asm07c.out 2000 out/asm08c.asm.out out/asm08c.out)
echo "--- Version 09 ---"
(cd 09 && mkdir -p out &&
  ../emulator.out ../06/out/asm06.out 2000 instgen09.asm out/instgen09.out &&
  ../emulator.out out/instgen09.out 2000 /dev/null out/inst09.asm.out &&
  cat out/inst09.asm.out asm09.asm > out/asm09c.asm.out &&
  ../emulator.out ../08/out/asm08c.out 2000 out/asm09c.asm.out out/asm09c.out)
echo "--- Version 10 ---"
(cd 10 && mkdir -p out &&
  ../emulator.out ../06/out/asm06.out 2000 instgen10.asm out/instgen10.out &&
  ../emulator.out out/instgen10.out 2000 /dev/null out/inst10.asm.out &&
  cat out/inst10.asm.out asm10.asm > out/asm10c.asm.out &&
  ../emulator.out ../09/out/asm09c.out 2000 out/asm10c.asm.out out/asm10c.out)
echo "--- Version 11 ---"
(cd 11 && mkdir -p out &&
  ../emulator.out ../10/out/asm10c.out 2000 instgen11.asm out/instgen11.out &&
  ../emulator.out out/instgen11.out 2000 /dev/null out/inst11.asm.out &&
  ../emulator.out ../10/out/asm10c.out 2000 asm11.asm out/asm11.out)
echo "--- Version 12 ---"
(cd 12 && mkdir -p out &&
  ../emulator.out ../11/out/asm11.out 2000 instgen12.asm out/instgen12.out &&
  ../emulator.out out/instgen12.out 2000 /dev/null out/inst12.asm.out &&
  ../emulator.out ../11/out/asm11.out 2000 asm12.asm out/asm12.out)
echo "--- Version 13 ---"
(cd 13 && mkdir -p out &&
  ../emulator.out ../12/out/asm12.out 2000 /dev/null /dev/null instgen13.asm out/instgen13.out &&
  ../emulator.out out/instgen13.out 2000 /dev/null out/inst13.asm.out &&
  ../emulator.out ../12/out/asm12.out 2000 /dev/null /dev/null asm13.asm out/asm13.out)
echo "--- Version 14 ---"
(cd 14 && mkdir -p out &&
  ../emulator.out ../13/out/asm13.out 2000 /dev/null /dev/null instgen14.asm out/instgen14.out &&
  ../emulator.out out/instgen14.out 2000 /dev/null out/inst14.asm.out &&
  ../emulator.out ../13/out/asm13.out 2000 /dev/null /dev/null asm14.asm out/asm14.out)
echo "--- Version 15 ---"
(cd 15 && mkdir -p out &&
  ../emulator.out ../14/out/asm14.out 2000 /dev/null /dev/null instgen15.asm out/instgen15.out &&
  ../emulator.out out/instgen15.out 2000 /dev/null out/inst15.asm.out &&
  ../emulator.out ../14/out/asm14.out 2000 /dev/null /dev/null asm15.asm out/asm15.out)
echo "--- Version 16 ---"
(cd 16 && mkdir -p out &&
  ../emulator.out ../15/out/asm15.out 2000 /dev/null /dev/null instgen16.asm out/instgen16.out &&
  ../emulator.out out/instgen16.out 2000 /dev/null out/inst16.asm.out &&
  ../emulator.out ../15/out/asm15.out 2000 /dev/null /dev/null asm16.asm out/asm16.out)
echo "--- Test asm16 ---"
./emulator.out 16/out/asm16.out 2000 /dev/null /dev/null test16.asm out/test16.out
echo "--- Version 17 ---"
(cd 17 && mkdir -p out &&
  ../emulator.out ../16/out/asm16.out 2000 /dev/null /dev/null instgen17.asm out/instgen17.out &&
  ../emulator.out out/instgen17.out 2000 /dev/null out/inst17.asm.out &&
  ../emulator.out ../16/out/asm16.out 2000 /dev/null /dev/null asm17.asm out/asm17.out)
diff <(hexdump -C 16/out/asm16.out) <(hexdump -C 17/out/asm17.out)
echo "--- Version 18 ---"
(cd 18 && mkdir -p out &&
  ../emulator.out ../17/out/asm17.out 2000 /dev/null /dev/null instgen18.asm out/instgen18.out &&
  ../emulator.out out/instgen18.out 2000 /dev/null out/inst18.asm.out &&
  ../emulator.out ../17/out/asm17.out 2000 /dev/null /dev/null asm18.asm out/asm18.out)
diff 16/out/inst16.asm.out 18/out/inst18.asm.out
echo "--- Version 19 ---"
(cd 19 && mkdir -p out &&
  ../emulator.out ../18/out/asm18.out 2000 /dev/null /dev/null instgen19.asm out/instgen19.out &&
  ../emulator.out out/instgen19.out 2000 /dev/null out/inst19.asm.out &&
  ../emulator.out ../18/out/asm18.out 2000 /dev/null /dev/null asm19.asm out/asm19.out)
echo "--- Version 20 ---"
(cd 20 && mkdir -p out &&
  ../emulator.out ../19/out/asm19.out 2000 /dev/null /dev/null instgen20.asm out/instgen20.out &&
  ../emulator.out out/instgen20.out 2000 /dev/null out/inst20.asm.out &&
  ../emulator.out ../19/out/asm19.out 2000 /dev/null /dev/null asm20.asm out/asm20.out)
echo "--- Version 21 ---"
(cd 21 && mkdir -p out &&
  ../emulator.out ../20/out/asm20.out 2000 /dev/null /dev/null instgen21.asm out/instgen21.out &&
  ../emulator.out out/instgen21.out 2000 /dev/null out/inst21.asm.out &&
  ../emulator.out ../20/out/asm20.out 2000 /dev/null /dev/null asm21.asm out/asm21.out &&
  ../emulator.out ../20/out/asm20.out 2000 /dev/null /dev/null asm21.asm out/asm21_debug.out define:enable_debug)
echo "--- File stack test ---"
./emulator.out 21/out/asm21_debug.out 2000 /dev/null /dev/null tests/file_stack_test22.asm out/file_stack_test22.out
echo "--- Version 22 ---"
(cd 22 && mkdir -p out &&
  ../emulator.out ../21/out/asm21_debug.out 2000 /dev/null /dev/null instgen22.asm out/instgen22.out &&
  ../emulator.out out/instgen22.out 2000 /dev/null out/inst22.asm.out &&
  ../emulator.out ../21/out/asm21_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22.out &&
  ../emulator.out ../21/out/asm21_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22_debug.out define:enable_debug)
echo "--- Self-assembly test ---"
# Self-assembly test (without debug - smaller)
(cd 22 && ../emulator.out out/asm22.out 2000 /dev/null /dev/null asm22.asm out/asm22_2.out)
diff <(hexdump -C 22/out/asm22.out) <(hexdump -C 22/out/asm22_2.out)
# Self-assembly test (with debug)
(cd 22 && ../emulator.out out/asm22_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22_debug_2.out define:enable_debug)
diff <(hexdump -C 22/out/asm22_debug.out) <(hexdump -C 22/out/asm22_debug_2.out)

echo "Build chain completed OK"

# Show actual code size difference
# File covers $2000-$FFFF, vectors at end. Scan backwards from just before vectors.
echo "Code size comparison:"
SIZE1=$(perl -e 'open(F,"<","22/out/asm22.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
SIZE2=$(perl -e 'open(F,"<","22/out/asm22_debug.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
echo "  asm22.out (no debug):   $SIZE1 bytes"
echo "  asm22_debug.out:        $SIZE2 bytes"
echo "  Difference:             $((SIZE2 - SIZE1)) bytes"

echo "--- Test asm22 ---"
./emulator.out 22/out/asm22_debug.out 2000 /dev/null /dev/null test19.asm out/test19.out
# hexdump -C out/test19.out
echo "Assembled test program"
./emulator.out out/test19.out 1000 /dev/null - arg1 "arg 2"

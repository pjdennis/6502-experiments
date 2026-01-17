#!/bin/bash

set -e
shopt -s extglob

mkdir -p out dump
rm -f out/*.out out/*.asm.out
make --quiet
./asm0c.out asm00.asm out/asm00.out
./emulator.out out/asm00.out 2000 asm01.asm out/asm01.out
./emulator.out out/asm01.out 2000 asm02.asm out/asm02.out
./emulator.out out/asm02.out 2000 asm03.asm out/asm03.out
./emulator.out out/asm03.out 2000 asm04.asm out/asm04.out
./emulator.out out/asm04.out 2000 asm05.asm out/asm05.out
./emulator.out out/asm05.out 2000 asm06.asm out/asm06.out
./emulator.out out/asm06.out 2000 instgen07.asm out/instgen07.out
./emulator.out out/instgen07.out 2000 /dev/null out/inst07.asm.out
cat out/inst07.asm.out asm07.asm > out/asm07c.asm.out
./emulator.out out/asm06.out 2000 out/asm07c.asm.out out/asm07c.out
cat out/inst07.asm.out asm08.asm > out/asm08c.asm.out
./emulator.out out/asm07c.out 2000 out/asm08c.asm.out out/asm08c.out
cat out/inst07.asm.out asm09.asm > out/asm09c.asm.out
./emulator.out out/asm08c.out 2000 out/asm09c.asm.out out/asm09c.out
cat out/inst07.asm.out asm10.asm > out/asm10c.asm.out
./emulator.out out/asm09c.out 2000 out/asm10c.asm.out out/asm10c.out
./emulator.out out/asm10c.out 2000 instgen11.asm out/instgen11.out
./emulator.out out/instgen11.out 2000 /dev/null out/inst11.asm.out
./emulator.out out/asm10c.out 2000 asm11.asm out/asm11.out
./emulator.out out/asm11.out 2000 asm12.asm out/asm12.out
./emulator.out out/asm12.out 2000 /dev/null /dev/null instgen13.asm out/instgen13.out
./emulator.out out/instgen13.out 2000 /dev/null out/inst13.asm.out
./emulator.out out/asm12.out 2000 /dev/null /dev/null asm13.asm out/asm13.out
./emulator.out out/asm13.out 2000 /dev/null /dev/null instgen14.asm out/instgen14.out
./emulator.out out/instgen14.out 2000 /dev/null out/inst14.asm.out
./emulator.out out/asm13.out 2000 /dev/null /dev/null asm14.asm out/asm14.out
./emulator.out out/asm14.out 2000 /dev/null /dev/null instgen15.asm out/instgen15.out
./emulator.out out/instgen15.out 2000 /dev/null out/inst15.asm.out
./emulator.out out/asm14.out 2000 /dev/null /dev/null asm15.asm out/asm15.out
./emulator.out out/asm15.out 2000 /dev/null /dev/null instgen16.asm out/instgen16.out
./emulator.out out/instgen16.out 2000 /dev/null out/inst16.asm.out
./emulator.out out/asm15.out 2000 /dev/null /dev/null asm16.asm out/asm16.out
./emulator.out out/asm16.out 2000 /dev/null /dev/null test16.asm out/test16.out
./emulator.out out/asm16.out 2000 /dev/null /dev/null asm17.asm out/asm17.out
diff <(hexdump -C out/asm16.out) <(hexdump -C out/asm17.out)
./emulator.out out/asm17.out 2000 /dev/null /dev/null instgen18.asm out/instgen18.out
./emulator.out out/instgen18.out 2000 /dev/null out/inst18.asm.out
diff out/inst16.asm.out out/inst18.asm.out
./emulator.out out/asm17.out 2000 /dev/null /dev/null asm18.asm out/asm18.out
./emulator.out out/asm18.out 2000 /dev/null /dev/null instgen19.asm out/instgen19.out
./emulator.out out/instgen19.out 2000 /dev/null out/inst19.asm.out
./emulator.out out/asm18.out 2000 /dev/null /dev/null asm19.asm out/asm19.out
./emulator.out out/asm19.out 2000 /dev/null /dev/null instgen20.asm out/instgen20.out
./emulator.out out/instgen20.out 2000 /dev/null out/inst20.asm.out
./emulator.out out/asm19.out 2000 /dev/null /dev/null asm20.asm out/asm20.out
./emulator.out out/asm20.out 2000 /dev/null /dev/null instgen21.asm out/instgen21.out
./emulator.out out/instgen21.out 2000 /dev/null out/inst21.asm.out
./emulator.out out/asm20.out 2000 /dev/null /dev/null asm21.asm out/asm21.out
./emulator.out out/asm20.out 2000 /dev/null /dev/null asm21.asm out/asm21_debug.out define:enable_debug
./emulator.out out/asm21_debug.out 2000 /dev/null /dev/null tests/file_stack_test22.asm out/file_stack_test22.out
./emulator.out out/asm21_debug.out 2000 /dev/null /dev/null instgen22.asm out/instgen22.out
./emulator.out out/instgen22.out 2000 /dev/null out/inst22.asm.out
./emulator.out out/asm21_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22.out
./emulator.out out/asm21_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22_debug.out define:enable_debug
# Self-assembly test (without debug - smaller)
./emulator.out out/asm22.out 2000 /dev/null /dev/null asm22.asm out/asm22_2.out
diff <(hexdump -C out/asm22.out) <(hexdump -C out/asm22_2.out)
# Self-assembly test (with debug)
./emulator.out out/asm22_debug.out 2000 /dev/null /dev/null asm22.asm out/asm22_debug_2.out define:enable_debug
diff <(hexdump -C out/asm22_debug.out) <(hexdump -C out/asm22_debug_2.out)

echo "Build chain completed OK"

# Show actual code size difference
# File covers $2000-$FFFF, vectors at end. Scan backwards from just before vectors.
echo "Code size comparison:"
SIZE1=$(perl -e 'open(F,"<","out/asm22.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
SIZE2=$(perl -e 'open(F,"<","out/asm22_debug.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
echo "  asm22.out (no debug):   $SIZE1 bytes"
echo "  asm22_debug.out:        $SIZE2 bytes"
echo "  Difference:             $((SIZE2 - SIZE1)) bytes"

./emulator.out out/asm22_debug.out 2000 /dev/null /dev/null test19.asm out/test19.out
# hexdump -C out/test19.out
echo "Assembled test program"
./emulator.out out/test19.out 1000 /dev/null - arg1 "arg 2"

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
./emulator.out out/asm17.out 2000 /dev/null /dev/null asm17.asm out/asm17_2.out
diff <(hexdump -C out/asm17.out) <(hexdump -C out/asm17_2.out)
./emulator.out out/asm17.out 2000 /dev/null /dev/null instgen18.asm out/instgen18.out
./emulator.out out/instgen18.out 2000 /dev/null out/inst18.asm.out
diff out/inst16.asm.out out/inst18.asm.out
./emulator.out out/asm17.out 2000 /dev/null /dev/null asm18.asm out/asm18.out
./emulator.out out/asm18.out 2000 /dev/null /dev/null asm18.asm out/asm18_2.out
diff <(hexdump -C out/asm18.out) <(hexdump -C out/asm18_2.out)
# hexdump -C out/asm18_2.out | ./sidebyside.out

echo "OK"
./emulator.out out/asm18_2.out 2000 /dev/null /dev/null test17.asm out/test.out
# hexdump -C out/test.out
echo "Assembled"
./emulator.out out/test.out 1000 /dev/null - arg1 "arg 2"

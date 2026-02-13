#!/bin/bash

set -e
shopt -s extglob

# Run tests for a version if test directory exists
run_version_tests() {
    local ver=$1
    if [ -d "${ver}/tests" ]; then
        echo "--- Test asm${ver} ---"
        ./run_tests.py --version "$ver" -q "${ver}/tests/asm_tests.txt"
    fi
}

mkdir -p out
rm -f out/*.out out/*.asm.out
rm -rf {00..99}/out
make --quiet
echo "--- Version 00 ---"
(cd 00 && out/asm_c.out asm.asm out/asm.out)
echo "--- Version 01 ---"
(cd 01 && mkdir -p out && ../emulator.out ../00/out/asm.out --load 2000 --input asm.asm --output out/asm.out)
echo "--- Version 02 ---"
(cd 02 && mkdir -p out && ../emulator.out ../01/out/asm.out --load 2000 --input asm.asm --output out/asm.out)
echo "--- Version 03 ---"
(cd 03 && mkdir -p out && ../emulator.out ../02/out/asm.out --load 2000 --input asm.asm --output out/asm.out)
run_version_tests 03
echo "--- Version 05 ---"
(cd 05 && mkdir -p out && ../emulator.out ../03/out/asm.out --load 2000 --input asm.asm --output out/asm.out)
echo "--- Version 06 ---"
(cd 06 && mkdir -p out && ../emulator.out ../05/out/asm.out --load 2000 --input asm.asm --output out/asm.out)
echo "--- Version 07 ---"
(cd 07 && mkdir -p out &&
  ../emulator.out ../06/out/asm.out --load 2000 --input instgen.asm --output out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  cat out/inst.asm.out asm.asm > out/asmc.asm.out &&
  ../emulator.out ../06/out/asm.out --load 2000 --input out/asmc.asm.out --output out/asmc.out)
echo "--- Version 08 ---"
(cd 08 && mkdir -p out &&
  ../emulator.out ../07/out/asmc.out --load 2000 --input instgen.asm --output out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  cat out/inst.asm.out asm.asm > out/asmc.asm.out &&
  ../emulator.out ../07/out/asmc.out --load 2000 --input out/asmc.asm.out --output out/asmc.out)
run_version_tests 08
echo "--- Version 10 ---"
(cd 10 && mkdir -p out &&
  ../emulator.out ../08/out/asmc.out --load 2000 --input instgen.asm --output out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  cat out/inst.asm.out asm.asm > out/asmc.asm.out &&
  ../emulator.out ../08/out/asmc.out --load 2000 --input out/asmc.asm.out --output out/asmc.out)
run_version_tests 10
echo "--- Version 12 ---"
(cd 12 && mkdir -p out &&
  ../emulator.out ../10/out/asmc.out --input instgen.asm --output out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../10/out/asmc.out --input asm.asm --output out/asm.out)
run_version_tests 12
echo "--- Version 14 ---"
(cd 14 && mkdir -p out &&
  ../emulator.out ../12/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../12/out/asm.out asm.asm out/asm.out)
run_version_tests 14
echo "--- Version 16 ---"
(cd 16 && mkdir -p out &&
  ../emulator.out ../14/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../14/out/asm.out asm.asm out/asm.out)
run_version_tests 16
echo "--- Test asm16 ---"
./emulator.out 16/out/asm.out test16.asm out/test16.out
echo "--- Version 17 ---"
(cd 17 && mkdir -p out &&
  ../emulator.out ../16/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../16/out/asm.out asm.asm out/asm.out)
run_version_tests 17
diff <(hexdump -C 16/out/asm.out) <(hexdump -C 17/out/asm.out)
echo "--- Version 19 ---"
(cd 19 && mkdir -p out &&
  ../emulator.out ../17/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../17/out/asm.out asm.asm out/asm.out)
run_version_tests 19
echo "--- Version 20 ---"
(cd 20 && mkdir -p out &&
  ../emulator.out ../19/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../19/out/asm.out asm.asm out/asm.out)
run_version_tests 20
echo "--- Version 21 ---"
(cd 21 && mkdir -p out &&
  ../emulator.out ../20/out/asm.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../20/out/asm.out asm.asm out/asm.out &&
  ../emulator.out ../20/out/asm.out asm.asm out/asm_debug.out define:enable_debug)
run_version_tests 21
echo "--- Version 22 ---"
(cd 22 && mkdir -p out &&
  ../emulator.out ../21/out/asm_debug.out tests/file_stack_test.asm out/file_stack_test.out &&
  ../emulator.out ../21/out/asm_debug.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../21/out/asm_debug.out asm.asm out/asm.out &&
  ../emulator.out ../21/out/asm_debug.out asm.asm out/asm_debug.out define:enable_debug)
echo "--- Version 23 ---"
(cd 23 && mkdir -p out &&
  ../emulator.out ../22/out/asm_debug.out tests/file_stack/file_stack_test.asm out/file_stack_test.out &&
  ../emulator.out ../22/out/asm_debug.out instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out --load 2000 --output out/inst.asm.out &&
  ../emulator.out ../22/out/asm_debug.out asm.asm out/asm.out &&
  ../emulator.out ../22/out/asm_debug.out asm.asm out/asm_debug.out define:enable_debug)
echo "--- Self-assembly test ---"
# Self-assembly test (without debug - smaller)
(cd 23 && ../emulator.out out/asm.out asm.asm out/asm_2.out)
diff <(hexdump -C 23/out/asm.out) <(hexdump -C 23/out/asm_2.out)
# Self-assembly test (with debug)
(cd 23 && ../emulator.out out/asm_debug.out asm.asm out/asm_debug_2.out define:enable_debug)
diff <(hexdump -C 23/out/asm_debug.out) <(hexdump -C 23/out/asm_debug_2.out)

echo "Build chain completed OK"

# Show actual code size difference
# File covers $2000-$FFFF, vectors at end. Scan backwards from just before vectors.
echo "Code size comparison:"
SIZE1=$(perl -e 'open(F,"<","23/out/asm.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
SIZE2=$(perl -e 'open(F,"<","23/out/asm_debug.out");binmode(F);read(F,$d,0xE000);for($i=0xDFFB;$i>=0;$i--){last if ord(substr($d,$i,1))!=0}print $i+1')
echo "  asm.out (no debug):     $SIZE1 bytes"
echo "  asm_debug.out:          $SIZE2 bytes"
echo "  Difference:             $((SIZE2 - SIZE1)) bytes"

echo "--- Test asm23 ---"
./emulator.out 23/out/asm_debug.out test19.asm out/test19.out
# hexdump -C out/test19.out
echo "Assembled test program"
./emulator.out out/test19.out --load 1000 --output - arg1 "arg 2"

#!/bin/bash
trap exit SIGINT

while true
do
    clear && ./asmtestgen.sh && ./run_tests.py
    echo "Waiting for file change..."
    fswatch -1 --event Updated --latency 0.1 \
        asmtestgen.sh emulator.c sidebyside.cpp 00/asm.c \
        00/asm.asm 01/asm.asm 02/asm.asm 03/asm.asm 04/asm.asm 05/asm.asm 06/asm.asm \
        07/asm.asm 07/instgen.asm 08/asm.asm 08/instgen.asm 09/asm.asm 09/instgen.asm 10/asm.asm 10/instgen.asm \
        11/asm.asm 11/instgen.asm 11/environment.asm 11/common.asm \
        12/asm.asm 12/instgen.asm 12/environment.asm 12/common.asm \
        13/asm.asm 13/instgen.asm 13/environment.asm 13/common.asm 13/to_decimal.asm 13/hash_table.asm 13/file_stack.asm \
        14/asm.asm 14/instgen.asm 14/environment.asm 14/common.asm 14/hash_table.asm 14/file_stack.asm 14/to_decimal.asm \
        15/asm.asm 15/instgen.asm 15/environment.asm 15/common.asm 15/hash_table.asm 15/file_stack.asm 15/to_decimal.asm \
        16/asm.asm 16/instgen.asm 16/environment.asm 16/common.asm 16/hash_table.asm 16/file_stack.asm 16/to_decimal.asm test16.asm \
        17/asm.asm 17/instgen.asm 17/environment.asm 17/common.asm 17/hash_table.asm 17/file_stack.asm 17/to_decimal.asm \
        18/asm.asm 18/instgen.asm 18/environment.asm 18/common.asm 18/hash_table.asm 18/file_stack.asm 18/to_decimal.asm 18/errors.asm 18/fwdref.asm \
        19/asm.asm 19/instgen.asm 19/environment.asm 19/common.asm 19/hash_table.asm 19/file_stack.asm 19/to_decimal.asm 19/errors.asm 19/fwdref.asm \
        20/asm.asm 20/instgen.asm 20/environment.asm 20/common.asm 20/hash_table.asm 20/file_stack.asm 20/to_decimal.asm 20/errors.asm 20/fwdref.asm \
        21/asm.asm 21/instgen.asm 21/environment.asm 21/common.asm 21/hash_table.asm 21/file_stack.asm 21/to_decimal.asm 21/errors.asm 21/fwdref.asm 21/label_scope.asm \
        22/asm.asm 22/instgen.asm 22/environment.asm 22/common.asm 22/hash_table.asm 22/file_stack.asm 22/to_decimal.asm 22/errors.asm 22/fwdref.asm 22/label_scope.asm 22/macros.asm \
        test19.asm test_inc19.asm \
	run_tests.py 22/tests/file_stack_test22.asm 22/tests/file_stack_tests22.txt 22/tests/asm22_tests.txt
        > /dev/null

    sleep 0.1
done

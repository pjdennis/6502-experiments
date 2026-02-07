#!/bin/bash
trap exit SIGINT

while true
do
    clear && ./asmtestgen.sh && tests/run_tests.py
    echo "Waiting for file change..."
    fswatch -1 --event Updated --latency 0.1 \
        asmtestgen.sh emulator.c sidebyside.cpp asm0c.c \
        00/asm00.asm 01/asm01.asm 02/asm02.asm 03/asm03.asm 04/asm04.asm 05/asm05.asm 06/asm06.asm \
        07/asm07.asm 07/instgen07.asm 08/asm08.asm 08/instgen08.asm 09/asm09.asm 09/instgen09.asm 10/asm10.asm 10/instgen10.asm \
        11/asm11.asm 11/instgen11.asm 11/environment11.asm 11/common11.asm \
        12/asm12.asm 12/instgen12.asm 12/environment12.asm 12/common12.asm \
        13/asm13.asm 13/instgen13.asm 13/environment13.asm 13/common13.asm 13/to_decimal13.asm 13/hash_table13.asm 13/file_stack13.asm \
        14/asm14.asm 14/instgen14.asm 14/environment14.asm 14/common14.asm 14/hash_table14.asm 14/file_stack14.asm 14/to_decimal14.asm \
        15/asm15.asm 15/instgen15.asm 15/environment15.asm 15/common15.asm 15/hash_table15.asm 15/file_stack15.asm 15/to_decimal15.asm \
        16/asm16.asm 16/instgen16.asm 16/environment16.asm 16/common16.asm 16/hash_table16.asm 16/file_stack16.asm 16/to_decimal16.asm test16.asm \
        17/asm17.asm 17/instgen17.asm 17/environment17.asm 17/common15.asm 17/hash_table15.asm 17/common17.asm 17/hash_table17.asm 17/file_stack17.asm 17/to_decimal17.asm \
        18/asm18.asm 18/instgen18.asm 18/environment18.asm 18/common18.asm 18/hash_table18.asm 18/file_stack18.asm 18/to_decimal18.asm 18/errors18.asm 18/fwdref18.asm \
        19/asm19.asm 19/instgen19.asm 19/environment19.asm 19/common19.asm 19/hash_table19.asm 19/file_stack19.asm 19/to_decimal19.asm 19/errors19.asm 19/fwdref19.asm \
        20/asm20.asm 20/instgen20.asm 20/environment20.asm 20/common20.asm 20/hash_table20.asm 20/file_stack20.asm 20/to_decimal20.asm 20/errors20.asm 20/fwdref20.asm \
        21/asm21.asm 21/instgen21.asm 21/environment21.asm 21/common21.asm 21/hash_table21.asm 21/file_stack21.asm 21/to_decimal21.asm 21/errors21.asm 21/fwdref21.asm 21/label_scope21.asm \
        22/asm22.asm 22/instgen22.asm 22/environment22.asm 22/common22.asm 22/hash_table22.asm 22/file_stack22.asm 22/to_decimal22.asm 22/errors22.asm 22/fwdref22.asm 22/label_scope22.asm 22/macros22.asm \
        test19.asm test_inc19.asm \
	tests/run_tests.py tests/file_stack_test22.asm tests/file_stack_tests22.txt tests/asm22_tests.txt
        > /dev/null

    sleep 0.1
done

#!/bin/bash
trap exit SIGINT

while true
do
#    clear && ./asmtestgen.sh && tests/run_file_stack_tests.pl && tests/run_tests.sh
    clear && ./asmtestgen.sh && tests/run_tests.sh
    echo "Waiting for file change..."
    fswatch -1 --event Updated --latency 0.1 \
        asmtestgen.sh emulator.c sidebyside.cpp asm0c.c \
        asm00.asm asm01.asm asm02.asm asm03.asm asm04.asm asm05.asm asm06.asm \
        asm07.asm asm08.asm asm09.asm asm10.asm asm11.asm asm12.asm \
        instgen07.asm instgen11.asm environment11.asm common11.asm \
        asm13.asm instgen13.asm common13.asm to_decimal13.asm hash_table13.asm file_stack13.asm \
        asm14.asm instgen14.asm common14.asm hash_table14.asm \
        asm15.asm instgen15.asm common15.asm hash_table15.asm file_stack15.asm to_decimal15.asm \
        asm16.asm instgen16.asm test16.asm \
        asm17.asm common17.asm hash_table17.asm file_stack17.asm to_decimal17.asm \
        asm18.asm instgen18.asm common18.asm hash_table18.asm file_stack18.asm to_decimal18.asm errors18.asm fwdref18.asm \
        asm19.asm instgen19.asm common19.asm hash_table19.asm file_stack19.asm to_decimal19.asm errors19.asm fwdref19.asm \
        asm20.asm instgen20.asm common20.asm hash_table20.asm file_stack20.asm to_decimal20.asm errors20.asm fwdref20.asm \
        asm21.asm instgen21.asm common21.asm hash_table21.asm file_stack21.asm to_decimal21.asm errors21.asm fwdref21.asm label_scope21.asm \
        asm22.asm instgen22.asm common22.asm hash_table22.asm file_stack22.asm to_decimal22.asm errors22.asm fwdref22.asm label_scope22.asm macros22.asm \
        test19.asm test_inc19.asm \
	tests/run_tests.sh tests/asm22_tests.txt \
        tests/run_file_stack_tests.pl tests/file_stack_test22.asm tests/file_stack_tests22.txt
        > /dev/null

    sleep 0.1
done

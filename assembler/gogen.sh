#!/bin/bash
trap exit SIGINT

while true
do
    clear && ./asmtestgen.sh
    echo "Waiting for file change..."
    fswatch -1 --event Updated --latency 0.1 emulator.c sidebyside.cpp asm4v.asm asm4b.asm asm4b2.asm asm4b3.asm asm4b4.asm asm4b5.asm asm4b6.asm asm4b7.asm instgen.asm instgen7.asm asmtestgen.sh test.asm > /dev/null
done

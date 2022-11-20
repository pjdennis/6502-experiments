#!/bin/zsh
clear && ./asmtest4b.sh
echo "Waiting for file change..."

while fswatch -1 emulator.c asm4v.asm asm4b.asm asm4b2.asm asm4b3.asm asmtest4b.sh > /dev/null
do
    clear && ./asmtest4b.sh
    echo "Waiting for file change..."
done

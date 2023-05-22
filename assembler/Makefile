all: emulator.out sidebyside.out asm4v.out

emulator.out: emulator.c
	gcc -o emulator.out emulator.c

sidebyside.out: sidebyside.cpp
	g++ -o sidebyside.out sidebyside.cpp

asm4v.out: asm4v.asm
	../vasm6502_oldstyle -quiet -wfail -Fbin -dotdir -esc -o asm4v.out asm4v.asm


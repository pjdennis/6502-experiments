all: emulator.out sidebyside.out asm4v.out asm0c.out asm0.out

clean:
	rm -f *.out
	rm -f *.bin

emulator.out: emulator.c
	gcc -O2 -march=native -flto -DNDEBUG -o emulator.out emulator.c

asm0c.out: asm0c.c
	gcc -O2 -o asm0c.out asm0c.c

asm0.out: asm0.asm asm0c.out
	./asm0c.out asm0.asm asm0.out

sidebyside.out: sidebyside.cpp
	g++ -O2 -march=native -flto -DNDEBUG -o sidebyside.out sidebyside.cpp

asm4v.out: asm4v.asm
	../vasm6502_oldstyle -quiet -wfail -Fbin -dotdir -esc -o asm4v.out asm4v.asm


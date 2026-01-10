all: emulator.out sidebyside.out asm0c.out asm00.out

clean:
	rm -f *.out
	rm -f *.bin

emulator.out: emulator.c
	gcc -O2 -march=native -flto -DNDEBUG -o emulator.out emulator.c

asm0c.out: asm0c.c
	gcc -O2 -o asm0c.out asm0c.c

asm00.out: asm00.asm asm0c.out
	./asm0c.out asm00.asm asm00.out

sidebyside.out: sidebyside.cpp
	g++ -O2 -march=native -flto -DNDEBUG -o sidebyside.out sidebyside.cpp


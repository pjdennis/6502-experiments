all: emulator.out sidebyside.out asm0c.out

clean:
	rm -f emulator.out
	rm -f asm0c.out
	rm -f sidebyside.out
	rm -f out/*.out
	rm -f dump/*.bin

emulator.out: emulator.c
	@mkdir -p out
	gcc -O2 -march=native -flto -DNDEBUG -o out/emulator.out emulator.c

asm0c.out: asm0c.c
	@mkdir -p out
	gcc -O2 -o out/asm0c.out asm0c.c

sidebyside.out: sidebyside.cpp
	@mkdir -p out
	g++ -O2 -march=native -flto -DNDEBUG -o out/sidebyside.out sidebyside.cpp

all: out/emulator.out out/sidebyside.out out/asm0c.out out/asm00.out

clean:
	rm -f out/*.out out/*.asm.out
	rm -f dump/*.bin

out/emulator.out: emulator.c
	@mkdir -p out
	gcc -O2 -march=native -flto -DNDEBUG -o out/emulator.out emulator.c

out/asm0c.out: asm0c.c
	@mkdir -p out
	gcc -O2 -o out/asm0c.out asm0c.c

out/asm00.out: asm00.asm out/asm0c.out
	@mkdir -p out
	out/asm0c.out asm00.asm out/asm00.out

out/sidebyside.out: sidebyside.cpp
	@mkdir -p out
	g++ -O2 -march=native -flto -DNDEBUG -o out/sidebyside.out sidebyside.cpp

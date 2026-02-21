all: emulator.out 00/out/asm_c.out

clean:
	rm -f emulator.out
	find . -type d -name "out" -exec rm -rf {} +
	find . -type f -name "*.tmp" -delete

emulator.out: emulator.c
	@mkdir -p out
	gcc -O2 -march=native -flto -DNDEBUG -o emulator.out emulator.c

00/out/asm_c.out: 00/asm.c
	@mkdir -p 00/out
	gcc -O2 -o 00/out/asm_c.out 00/asm.c

# C unit tests
C_TESTS = tests/test_smoke

test: $(C_TESTS)
	@for t in $(C_TESTS); do ./$$t || exit 1; done

tests/test_smoke: tests/test_smoke.c tests/greatest.h
	gcc -o $@ $<

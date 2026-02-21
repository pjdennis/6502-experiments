all: emulator.out 00/out/asm_c.out

clean:
	rm -f emulator.out
	find . -type d -name "out" -exec rm -rf {} +
	find . -type f -name "*.tmp" -delete

EMU_SRCS = emulator.c file_io.c console.c cpu_core.c stubs.c
EMU_HDRS = file_io.h console.h cpu_core.h stubs.h

emulator.out: $(EMU_SRCS) $(EMU_HDRS)
	@mkdir -p out
	gcc -O2 -march=native -flto -DNDEBUG -o emulator.out $(EMU_SRCS)

00/out/asm_c.out: 00/asm.c
	@mkdir -p 00/out
	gcc -O2 -o 00/out/asm_c.out 00/asm.c

# C unit tests
C_TESTS = tests/test_smoke tests/test_file_io tests/test_console

test: $(C_TESTS)
	@for t in $(C_TESTS); do ./$$t || exit 1; done

tests/test_smoke: tests/test_smoke.c tests/greatest.h
	gcc -o $@ $<

tests/test_file_io: tests/test_file_io.c file_io.c file_io.h tests/greatest.h
	gcc -o $@ tests/test_file_io.c file_io.c

tests/test_console: tests/test_console.c console.c console.h tests/greatest.h
	gcc -o $@ tests/test_console.c console.c

all: emulator/emulator.out 00/out/asm_c.out

clean:
	rm -f emulator/emulator.out
	find . -type d -name "out" -exec rm -rf {} +
	find . -type f -name "*.tmp" -delete

EMU_SRCS = emulator/emulator.c emulator/file_io.c emulator/console.c emulator/cpu_core.c emulator/stubs.c emulator/trace.c emulator/cli.c emulator/emu_run.c emulator/bus.c
EMU_HDRS = emulator/file_io.h emulator/console.h emulator/cpu_core.h emulator/stubs.h emulator/trace.h emulator/cli.h emulator/emu_run.h emulator/bus.h

emulator/emulator.out: $(EMU_SRCS) $(EMU_HDRS)
	gcc -O2 -march=native -flto -DNDEBUG -o emulator/emulator.out $(EMU_SRCS)

00/out/asm_c.out: 00/asm.c
	@mkdir -p 00/out
	gcc -O2 -o 00/out/asm_c.out 00/asm.c

# C unit tests
C_TESTS = emulator/tests/out/test_smoke.out emulator/tests/out/test_file_io.out emulator/tests/out/test_console.out emulator/tests/out/test_trace.out emulator/tests/out/test_cli.out emulator/tests/out/test_emu_run.out emulator/tests/out/test_bus.out

test: $(C_TESTS)
	@for t in $(C_TESTS); do ./$$t || exit 1; done

emulator/tests/out/test_smoke.out: emulator/tests/test_smoke.c emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -o $@ $<

emulator/tests/out/test_file_io.out: emulator/tests/test_file_io.c emulator/file_io.c emulator/file_io.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -o $@ emulator/tests/test_file_io.c emulator/file_io.c

emulator/tests/out/test_console.out: emulator/tests/test_console.c emulator/console.c emulator/console.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -o $@ emulator/tests/test_console.c emulator/console.c

emulator/tests/out/test_trace.out: emulator/tests/test_trace.c emulator/trace.c emulator/trace.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_trace.c emulator/trace.c

emulator/tests/out/test_cli.out: emulator/tests/test_cli.c emulator/cli.c emulator/cli.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_cli.c emulator/cli.c

emulator/tests/out/test_emu_run.out: emulator/tests/test_emu_run.c emulator/emu_run.c emulator/emu_run.h emulator/cli.c emulator/cli.h emulator/trace.c emulator/trace.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_emu_run.c emulator/emu_run.c emulator/cli.c emulator/trace.c

emulator/tests/out/test_bus.out: emulator/tests/test_bus.c emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_bus.c emulator/bus.c

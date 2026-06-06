all: emulator/emulator.out 00/out/asm_c.out

clean:
	rm -f emulator/emulator.out
	find . -type d -name "out" -exec rm -rf {} +
	find . -type f -name "*.tmp" -delete

EMU_SRCS = emulator/emulator.c emulator/file_io.c emulator/console.c emulator/cpu_core.c emulator/stubs.c emulator/trace.c emulator/cli.c emulator/emu_run.c emulator/bus.c emulator/emu_wendy2c.c emulator/tty_alt_screen.c emulator/audio.c emulator/wendy2c_web.c emulator/web_json.c emulator/serial_link.c emulator/chips/osc.c emulator/chips/clock_22v10.c emulator/chips/rom_28c256.c emulator/chips/ram_628128.c emulator/chips/via_6522.c emulator/chips/lcd_hd44780.c emulator/chips/serial_usb.c emulator/chips/led_buttons.c emulator/chips/cpu_65c02.c emulator/chips/syscall_ports.c
EMU_HDRS = emulator/file_io.h emulator/console.h emulator/cpu_core.h emulator/stubs.h emulator/trace.h emulator/cli.h emulator/emu_run.h emulator/bus.h emulator/emu_wendy2c.h emulator/tty_alt_screen.h emulator/audio.h emulator/wendy2c_web.h emulator/web_json.h emulator/serial_link.h emulator/chips/osc.h emulator/chips/clock_22v10.h emulator/chips/clock_22v10_pld_generated.h emulator/chips/rom_28c256.h emulator/chips/ram_628128.h emulator/chips/via_6522.h emulator/chips/lcd_hd44780.h emulator/chips/serial_usb.h emulator/chips/led_buttons.h emulator/chips/cpu_65c02.h

# Path to the .pld source whose equations define the wendy2c memory
# map. clock_22v10_pld_generated.h is rebuilt by pld_to_c.py whenever
# either the .pld or the generator script changes.
WENDY2C_PLD = ../22V10-wendy2c.pld

emulator/chips/clock_22v10_pld_generated.h: $(WENDY2C_PLD) emulator/pld_to_c.py
	emulator/pld_to_c.py $(WENDY2C_PLD) -o $@

# miniaudio (vendored, used by emulator/audio.c) needs math, pthreads,
# and dynamic loading for runtime backend probing (ALSA/PulseAudio on
# Linux). macOS picks CoreAudio frameworks; Windows links built-in libs
# automatically.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  AUDIO_LDLIBS = -lm -lpthread -framework CoreFoundation -framework CoreAudio -framework AudioUnit
else ifeq ($(UNAME_S),Linux)
  AUDIO_LDLIBS = -lm -lpthread -ldl
else
  AUDIO_LDLIBS = -lm -lpthread
endif

emulator/emulator.out: $(EMU_SRCS) $(EMU_HDRS) emulator/vendor/miniaudio.h
	gcc -O2 -march=native -flto -DNDEBUG -o emulator/emulator.out $(EMU_SRCS) $(AUDIO_LDLIBS)

00/out/asm_c.out: 00/asm.c
	@mkdir -p 00/out
	gcc -O2 -o 00/out/asm_c.out 00/asm.c

# C unit tests
C_TESTS = emulator/tests/out/test_smoke.out emulator/tests/out/test_file_io.out emulator/tests/out/test_console.out emulator/tests/out/test_trace.out emulator/tests/out/test_cli.out emulator/tests/out/test_emu_run.out emulator/tests/out/test_bus.out emulator/tests/out/test_cpu_variant.out emulator/tests/out/test_cpu_65c02_fixes.out emulator/tests/out/test_cpu_65c02_group_a.out emulator/tests/out/test_cpu_65c02_group_b.out emulator/tests/out/test_cpu_65c02_bit_ops.out emulator/tests/out/test_cpu_65c02_wai_stp.out emulator/tests/out/test_cpu_bus_tap.out emulator/tests/out/test_dormann.out emulator/tests/out/test_machine_dispatch.out emulator/tests/out/test_chip_osc.out emulator/tests/out/test_chip_clock.out emulator/tests/out/test_chip_rom.out emulator/tests/out/test_chip_ram.out emulator/tests/out/test_chip_cpu_65c02.out emulator/tests/out/test_chip_via.out emulator/tests/out/test_pld_literal.out emulator/tests/out/test_pld_config_map.out emulator/tests/out/test_serial_link.out emulator/tests/out/test_chip_lcd.out emulator/tests/out/test_hd44780_font.out emulator/tests/out/test_chip_serial_usb.out emulator/tests/out/test_chip_led_buttons.out emulator/tests/out/test_audio.out emulator/tests/out/test_web_json.out emulator/tests/out/test_web_smoke.out

test: $(C_TESTS) wendy2c-goldens wendy2c-lcd-trace wendy2c-merge-sort wendy2c-serial-link wendy2c-live-sigint wendy2c-web wendy2c-lcd5x10 prog8-test tinyp8-test p1-test
	@for t in $(C_TESTS); do ./$$t || exit 1; done

# Prog8 host compiler (Phase 1 walking skeleton) test suite. Includes
# lexer / parser / sema / codegen unit tests, .s snapshot tests, and an
# end-to-end golden that compiles the demo .p8, runs it through vasm
# and the emulator, and asserts on the resulting LCD frame. SKIPs the
# end-to-end golden if vasm6502_oldstyle or the emulator binary are
# missing.
prog8-test: emulator/emulator.out
	@cd prog8 && python3 -m unittest discover -s tests -v

# wendy2: the custom external prog8 target with upper-window memory banking.
# Compiles the demos with upstream prog8c (-target wendy2.properties), runs
# them on the wendy2c emulator via the boot-ROM upload path, and diffs the
# LCD frame against goldens. Skips cleanly if prog8c.jar / 64tass /
# vasm6502_oldstyle / the emulator are missing. See
# prog8/WENDY2_BANKING_TARGET_PLAN.md.
wendy2-test: emulator/emulator.out
	@cd prog8/upstream && python3 tests/test_wendy2.py && python3 tests/test_wendy2_disk.py && python3 tests/test_wendy2_monitor.py

# tinyp8: the 6502-native compiler proof-of-concept. Two tests:
#   * test_e2e        -- the hand-written tinyp8.s compiles each .tp8
#                        and the resulting binary's stdout matches a
#                        golden. Proves: on-target compilation works.
#   * test_self_host  -- additionally, tinyp8.p8 (the SAME compiler
#                        rewritten in Prog8 and compiled by our host
#                        p8c) produces byte-identical output for the
#                        same inputs. Proves: a useful compiler can be
#                        written in our language and compiled by us.
# SKIPs cleanly if vasm6502_oldstyle or the emulator binary are
# missing.
tinyp8-test: emulator/emulator.out
	@cd prog8 && python3 -m unittest tinyp8.tests.test_e2e tinyp8.tests.test_self_host tinyp8.tests.test_v2 -v

# p1: the Prog8 parser port (Phase 6, step 5). M1 is the on-target lexer
# (p1/lexer.p8): built with host p8c + vasm, run on the emulator over a
# corpus, its token-stream dump diffed byte-for-byte against the Python
# oracle (p8c --dump-tokens). SKIPs cleanly if vasm or the emulator are
# missing.
p1-test: emulator/emulator.out
	@cd prog8 && python3 -m unittest p1.tests.test_lexer p1.tests.test_expr p1.tests.test_stmt p1.tests.test_p1 -v

# End-to-end wendy2c golden-LCD tests. Requires vasm6502_oldstyle on
# PATH; the script SKIPs (exits 0) if vasm is missing. Depends on the
# emulator binary -- chained behind it to ensure it's built fresh.
wendy2c-goldens: emulator/emulator.out
	@emulator/tests/wendy2c_goldens.sh

# End-to-end test for --lcd-trace: builds hello_ram_4000_wendy2c.s,
# runs the emulator with trace enabled, asserts the trace file contains
# a sequence of LCD frames. Same vasm-skip pattern as the goldens.
wendy2c-lcd-trace: emulator/emulator.out
	@emulator/tests/lcd_trace_test.sh

# End-to-end goldens for the wendy2 merge-sort demo. Uses --lcd-trace
# to assert on intermediate LCD frames (init -> fill -> sort -> verify
# -> final), not just the closing frame. Same vasm-skip pattern.
wendy2c-merge-sort: emulator/emulator.out
	@emulator/tests/merge_sort_goldens.sh

# End-to-end test of the host-driven --serial-link transport: a Python
# client uploads a framed payload bit-by-bit over the Unix socket, the
# boot ROM receives it, and we check the final LCD frame. Same
# vasm-skip pattern as the goldens.
wendy2c-serial-link: emulator/emulator.out
	@emulator/tests/wendy2c_serial_link_test.sh

# Python PTY test: confirms --live restores the terminal cleanly when
# Ctrl-C arrives mid-render. Same vasm-skip pattern as the goldens.
wendy2c-live-sigint: emulator/emulator.out
	@python3 emulator/tests/live_sigint_test.py

# Playwright test: drives the --web HTTP+WS server with headless
# Chromium, verifies the LCD canvas renders CGRAM custom characters
# pixel-by-pixel, that state + audio frames flow over the WS, and that
# button clicks round-trip. SKIPs if vasm or playwright are missing.
wendy2c-web: emulator/emulator.out
	@python3 emulator/tests/web_playwright_test.py

# Playwright test focused on HD44780 5x10 mode: loads the 5x10 demo
# payload, verifies the snapshot reports f5x10=1, and that the LCD
# canvas grew to the 11-row-per-cell size. SKIPs same as wendy2c-web.
wendy2c-lcd5x10: emulator/emulator.out
	@python3 emulator/tests/lcd_5x10_playwright_test.py

.PHONY: wendy2c-goldens wendy2c-lcd-trace wendy2c-merge-sort wendy2c-live-sigint wendy2c-web wendy2c-lcd5x10 prog8-test wendy2-test tinyp8-test p1-test

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

emulator/tests/out/test_cpu_variant.out: emulator/tests/test_cpu_variant.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_variant.c emulator/cpu_core.c

emulator/tests/out/test_cpu_65c02_fixes.out: emulator/tests/test_cpu_65c02_fixes.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_65c02_fixes.c emulator/cpu_core.c

emulator/tests/out/test_cpu_65c02_group_a.out: emulator/tests/test_cpu_65c02_group_a.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_65c02_group_a.c emulator/cpu_core.c

emulator/tests/out/test_cpu_65c02_group_b.out: emulator/tests/test_cpu_65c02_group_b.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_65c02_group_b.c emulator/cpu_core.c

emulator/tests/out/test_cpu_65c02_bit_ops.out: emulator/tests/test_cpu_65c02_bit_ops.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_65c02_bit_ops.c emulator/cpu_core.c

emulator/tests/out/test_cpu_65c02_wai_stp.out: emulator/tests/test_cpu_65c02_wai_stp.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_65c02_wai_stp.c emulator/cpu_core.c

emulator/tests/out/test_cpu_bus_tap.out: emulator/tests/test_cpu_bus_tap.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_cpu_bus_tap.c emulator/cpu_core.c

emulator/tests/out/test_dormann.out: emulator/tests/test_dormann.c emulator/cpu_core.c emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_dormann.c emulator/cpu_core.c

emulator/tests/out/test_machine_dispatch.out: emulator/tests/test_machine_dispatch.c emulator/cli.c emulator/cli.h emulator/cpu_core.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_machine_dispatch.c emulator/cli.c

emulator/tests/out/test_chip_osc.out: emulator/tests/test_chip_osc.c emulator/chips/osc.c emulator/chips/osc.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_osc.c emulator/chips/osc.c emulator/bus.c

emulator/tests/out/test_chip_clock.out: emulator/tests/test_chip_clock.c emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_clock.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_chip_rom.out: emulator/tests/test_chip_rom.c emulator/chips/rom_28c256.c emulator/chips/rom_28c256.h emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_rom.c emulator/chips/rom_28c256.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_chip_ram.out: emulator/tests/test_chip_ram.c emulator/chips/ram_628128.c emulator/chips/ram_628128.h emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_ram.c emulator/chips/ram_628128.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_chip_cpu_65c02.out: emulator/tests/test_chip_cpu_65c02.c emulator/chips/cpu_65c02.c emulator/chips/syscall_ports.c emulator/chips/cpu_65c02.h emulator/emu_wendy2c.c emulator/emu_wendy2c.h emulator/cli.c emulator/cli.h emulator/cpu_core.c emulator/cpu_core.h emulator/bus.c emulator/bus.h emulator/tty_alt_screen.c emulator/tty_alt_screen.h emulator/wendy2c_web.c emulator/wendy2c_web.h emulator/web_json.c emulator/web_json.h emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/chips/rom_28c256.c emulator/chips/rom_28c256.h emulator/chips/ram_628128.c emulator/chips/ram_628128.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/chips/lcd_hd44780.c emulator/chips/lcd_hd44780.h emulator/chips/serial_usb.c emulator/chips/serial_usb.h emulator/chips/led_buttons.c emulator/chips/led_buttons.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_chip_cpu_65c02.c emulator/chips/cpu_65c02.c emulator/chips/syscall_ports.c emulator/emu_wendy2c.c emulator/cli.c emulator/cpu_core.c emulator/bus.c emulator/tty_alt_screen.c emulator/wendy2c_web.c emulator/web_json.c emulator/chips/clock_22v10.c emulator/chips/rom_28c256.c emulator/chips/ram_628128.c emulator/chips/via_6522.c emulator/chips/lcd_hd44780.c emulator/chips/serial_usb.c emulator/chips/led_buttons.c

emulator/tests/out/test_chip_serial_usb.out: emulator/tests/test_chip_serial_usb.c emulator/chips/serial_usb.c emulator/chips/serial_usb.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_serial_usb.c emulator/chips/serial_usb.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_chip_via.out: emulator/tests/test_chip_via.c emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_via.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_pld_config_map.out: emulator/tests/test_pld_config_map.c emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/chips/clock_22v10_pld_generated.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_pld_config_map.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_pld_literal.out: emulator/tests/test_pld_literal.c emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_pld_literal.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_serial_link.out: emulator/tests/test_serial_link.c emulator/serial_link.c emulator/serial_link.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_serial_link.c emulator/serial_link.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_chip_lcd.out: emulator/tests/test_chip_lcd.c emulator/chips/lcd_hd44780.c emulator/chips/lcd_hd44780.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_lcd.c emulator/chips/lcd_hd44780.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_hd44780_font.out: emulator/tests/test_hd44780_font.c emulator/chips/hd44780_a00_font.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_hd44780_font.c

emulator/tests/out/test_chip_led_buttons.out: emulator/tests/test_chip_led_buttons.c emulator/chips/led_buttons.c emulator/chips/led_buttons.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_led_buttons.c emulator/chips/led_buttons.c emulator/chips/via_6522.c emulator/bus.c

# audio.c pulls in miniaudio (vendored); needs system audio libs even
# in the test, since miniaudio_init resolves backends at runtime.
emulator/tests/out/test_audio.out: emulator/tests/test_audio.c emulator/audio.c emulator/audio.h emulator/vendor/miniaudio.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_audio.c emulator/audio.c $(AUDIO_LDLIBS)

emulator/tests/out/test_web_json.out: emulator/tests/test_web_json.c emulator/web_json.c emulator/web_json.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_web_json.c emulator/web_json.c

emulator/tests/out/test_web_smoke.out: emulator/tests/test_web_smoke.c emulator/wendy2c_web.c emulator/wendy2c_web.h emulator/web_json.c emulator/web_json.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_web_smoke.c emulator/wendy2c_web.c emulator/web_json.c

# Rebuild every C_TESTS binary with AddressSanitizer + UndefinedBehaviorSanitizer
# + LeakSanitizer and run them. Output binaries land in emulator/tests/out/san/
# so the regular optimized .out files stay intact. Asan flags slow the binaries
# by ~2x but catch leaks, use-after-free, double-free, OOB, signed-overflow
# and other UB. The shell script (run_sanitizers.sh) carries the source list
# rather than the Makefile -- the list mirrors C_TESTS by name + sources.
sanitizers: emulator/emulator.out
	@emulator/tests/run_sanitizers.sh

.PHONY: sanitizers

# Tom Harte ProcessorTests harness (phase 3h). Opt-in: requires
# `emulator/tests/harte/fetch.sh` to populate `emulator/tests/harte/data/`
# first. When data is missing, harte_runner.out prints a warning and
# exits 0 so this target is safe to wire into CI without the fetch.
harte: emulator/tests/out/harte_runner.out
	@./emulator/tests/out/harte_runner.out

emulator/tests/out/harte_runner.out: emulator/tests/harte_runner.c emulator/cpu_core.c emulator/cpu_core.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/harte_runner.c emulator/cpu_core.c

.PHONY: harte

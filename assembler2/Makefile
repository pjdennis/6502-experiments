all: emulator/emulator.out 00/out/asm_c.out

clean:
	rm -f emulator/emulator.out
	find . -type d -name "out" -exec rm -rf {} +
	find . -type f -name "*.tmp" -delete

EMU_SRCS = emulator/emulator.c emulator/file_io.c emulator/console.c emulator/cpu_core.c emulator/stubs.c emulator/trace.c emulator/cli.c emulator/emu_run.c emulator/bus.c emulator/emu_wendy2c.c emulator/tty_alt_screen.c emulator/audio.c emulator/wendy2c_web.c emulator/web_json.c emulator/serial_link.c emulator/chips/osc.c emulator/chips/clock_22v10.c emulator/chips/rom_28c256.c emulator/chips/ram_628128.c emulator/chips/via_6522.c emulator/chips/lcd_hd44780.c emulator/chips/serial_usb.c emulator/chips/led_buttons.c emulator/chips/cpu_65c02.c
EMU_HDRS = emulator/file_io.h emulator/console.h emulator/cpu_core.h emulator/stubs.h emulator/trace.h emulator/cli.h emulator/emu_run.h emulator/bus.h emulator/emu_wendy2c.h emulator/tty_alt_screen.h emulator/audio.h emulator/wendy2c_web.h emulator/web_json.h emulator/serial_link.h emulator/chips/osc.h emulator/chips/clock_22v10.h emulator/chips/rom_28c256.h emulator/chips/ram_628128.h emulator/chips/via_6522.h emulator/chips/lcd_hd44780.h emulator/chips/serial_usb.h emulator/chips/led_buttons.h emulator/chips/cpu_65c02.h

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
C_TESTS = emulator/tests/out/test_smoke.out emulator/tests/out/test_file_io.out emulator/tests/out/test_console.out emulator/tests/out/test_trace.out emulator/tests/out/test_cli.out emulator/tests/out/test_emu_run.out emulator/tests/out/test_bus.out emulator/tests/out/test_cpu_variant.out emulator/tests/out/test_cpu_65c02_fixes.out emulator/tests/out/test_cpu_65c02_group_a.out emulator/tests/out/test_cpu_65c02_group_b.out emulator/tests/out/test_cpu_65c02_bit_ops.out emulator/tests/out/test_cpu_65c02_wai_stp.out emulator/tests/out/test_cpu_bus_tap.out emulator/tests/out/test_dormann.out emulator/tests/out/test_machine_dispatch.out emulator/tests/out/test_chip_osc.out emulator/tests/out/test_chip_clock.out emulator/tests/out/test_chip_rom.out emulator/tests/out/test_chip_ram.out emulator/tests/out/test_chip_cpu_65c02.out emulator/tests/out/test_chip_via.out emulator/tests/out/test_pld_literal.out emulator/tests/out/test_serial_link.out emulator/tests/out/test_chip_lcd.out emulator/tests/out/test_chip_serial_usb.out emulator/tests/out/test_chip_led_buttons.out emulator/tests/out/test_audio.out emulator/tests/out/test_web_json.out emulator/tests/out/test_web_smoke.out

test: $(C_TESTS) wendy2c-goldens wendy2c-serial-link wendy2c-live-sigint wendy2c-web
	@for t in $(C_TESTS); do ./$$t || exit 1; done

# End-to-end wendy2c golden-LCD tests. Requires vasm6502_oldstyle on
# PATH; the script SKIPs (exits 0) if vasm is missing. Depends on the
# emulator binary -- chained behind it to ensure it's built fresh.
wendy2c-goldens: emulator/emulator.out
	@emulator/tests/wendy2c_goldens.sh

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

.PHONY: wendy2c-goldens wendy2c-live-sigint wendy2c-web

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

emulator/tests/out/test_chip_cpu_65c02.out: emulator/tests/test_chip_cpu_65c02.c emulator/chips/cpu_65c02.c emulator/chips/cpu_65c02.h emulator/emu_wendy2c.c emulator/emu_wendy2c.h emulator/cli.c emulator/cli.h emulator/cpu_core.c emulator/cpu_core.h emulator/bus.c emulator/bus.h emulator/tty_alt_screen.c emulator/tty_alt_screen.h emulator/wendy2c_web.c emulator/wendy2c_web.h emulator/web_json.c emulator/web_json.h emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/chips/rom_28c256.c emulator/chips/rom_28c256.h emulator/chips/ram_628128.c emulator/chips/ram_628128.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/chips/lcd_hd44780.c emulator/chips/lcd_hd44780.h emulator/chips/serial_usb.c emulator/chips/serial_usb.h emulator/chips/led_buttons.c emulator/chips/led_buttons.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -Wno-unused-function -o $@ emulator/tests/test_chip_cpu_65c02.c emulator/chips/cpu_65c02.c emulator/emu_wendy2c.c emulator/cli.c emulator/cpu_core.c emulator/bus.c emulator/tty_alt_screen.c emulator/wendy2c_web.c emulator/web_json.c emulator/chips/clock_22v10.c emulator/chips/rom_28c256.c emulator/chips/ram_628128.c emulator/chips/via_6522.c emulator/chips/lcd_hd44780.c emulator/chips/serial_usb.c emulator/chips/led_buttons.c

emulator/tests/out/test_chip_serial_usb.out: emulator/tests/test_chip_serial_usb.c emulator/chips/serial_usb.c emulator/chips/serial_usb.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_serial_usb.c emulator/chips/serial_usb.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_chip_via.out: emulator/tests/test_chip_via.c emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_via.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_pld_literal.out: emulator/tests/test_pld_literal.c emulator/chips/clock_22v10.c emulator/chips/clock_22v10.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_pld_literal.c emulator/chips/clock_22v10.c emulator/bus.c

emulator/tests/out/test_serial_link.out: emulator/tests/test_serial_link.c emulator/serial_link.c emulator/serial_link.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_serial_link.c emulator/serial_link.c emulator/chips/via_6522.c emulator/bus.c

emulator/tests/out/test_chip_lcd.out: emulator/tests/test_chip_lcd.c emulator/chips/lcd_hd44780.c emulator/chips/lcd_hd44780.h emulator/chips/via_6522.c emulator/chips/via_6522.h emulator/bus.c emulator/bus.h emulator/tests/greatest.h
	@mkdir -p emulator/tests/out
	gcc -Wall -Werror -o $@ emulator/tests/test_chip_lcd.c emulator/chips/lcd_hd44780.c emulator/chips/via_6522.c emulator/bus.c

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

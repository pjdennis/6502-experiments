#include "emu_wendy2c.h"

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <sys/select.h>

#include "bus.h"
#include "cpu_core.h"
#include "emu_run.h"
#include "tty_alt_screen.h"
#include "chips/clock_22v10.h"
#include "chips/rom_28c256.h"
#include "chips/ram_628128.h"
#include "chips/via_6522.h"
#include "chips/lcd_hd44780.h"
#include "chips/serial_usb.h"
#include "chips/led_buttons.h"
#include "chips/cpu_65c02.h"

extern volatile sig_atomic_t sigint_requested;

/* Module-scope bus pointer used by the cpu_external_read/write hooks
 * the CPU dispatch reaches into. There's at most one wendy2c run
 * active per process. */
static struct bus *active_bus = NULL;

static uint8_t wendy2c_cpu_read(uint16_t addr) {
    if (!active_bus) return 0xFF;
    /* Reflect the address on the bus and refresh chip-select lines so
     * ROM/RAM/VIA see the right CS for THIS access. (CKS/CK are not
     * touched -- those advance on bus_step, not on per-access reads.) */
    active_bus->addr = addr;
    active_bus->rwb = 1;
    clock_22v10_refresh_combinational(active_bus);
    uint8_t data = 0xFF;
    bus_read(active_bus, addr, &data);
    return data;
}

static void wendy2c_cpu_write(uint16_t addr, uint8_t data) {
    if (!active_bus) return;
    active_bus->addr = addr;
    active_bus->rwb = 0;
    clock_22v10_refresh_combinational(active_bus);
    bus_write(active_bus, addr, data);
}

/* ---- live-mode renderer ---- */

/* PORTA / PORTB pin labels for the wendy2c. Reflects the post-GD-disable
 * wiring in base_config_wendy2c.inc + multitasking_test_wendy2c.s:
 * the graphic display is no longer wired up, freeing PA1/PA2 as the
 * CONTROL_BUTTON input and CONTROL_LED output, respectively. */
static const char *PORTA_LABELS[8] = {
    /* PA0 */ "RS",   /* LCD RS */
    /* PA1 */ "BTN",  /* CONTROL_BUTTON input */
    /* PA2 */ "LED",  /* CONTROL_LED output */
    /* PA3 */ "RW",   /* LCD RW */
    /* PA4 */ "D4",   /* LCD D4 */
    /* PA5 */ "D5",   /* LCD D5 */
    /* PA6 */ "D6",   /* LCD D6 */
    /* PA7 */ "D7",   /* LCD D7 */
};
static const char *PORTB_LABELS[8] = {
    /* PB0 */ "B0",   /* BANK bit 0 */
    /* PB1 */ "B1",
    /* PB2 */ "B2",
    /* PB3 */ "B3",
    /* PB4 */ "B4",
    /* PB5 */ "E",    /* LCD enable */
    /* PB6 */ "LED",  /* phase 11 */
    /* PB7 */ "T1",   /* T1 squarewave */
};

static void live_emit(const char *s) {
    size_t n = strlen(s);
    if (write(1, s, n) < 0) { /* best-effort */ }
}

static void live_render(const struct bus *b,
                        const struct lcd_hd44780_state *lcd,
                        const struct via_6522_state *via,
                        const struct led_buttons_state *ledbtn,
                        int cap_hit) {
    char buf[2048];
    char lcdbuf[LCD_DDRAM_SIZE + 8];
    int cols = lcd->cols;
    (void)lcd_hd44780_render((struct lcd_hd44780_state *)lcd, lcdbuf);

    uint8_t porta = via_6522_porta_pins(via);
    uint8_t portb = via_6522_portb_pins(via);
    int led  = led_buttons_led(ledbtn);
    int led2 = led_buttons_control_led(ledbtn);
    int btn  = led_buttons_button(ledbtn);

    /* Cursor home, default colors. */
    int n = 0;
    n += snprintf(buf + n, sizeof(buf) - n, "\x1b[H\x1b[0m");
    n += snprintf(buf + n, sizeof(buf) - n,
        "\x1b[1mwendy2c live\x1b[0m  --  q/ESC/Ctrl-C quit, SPACE press button\x1b[K\r\n\r\n");

    /* LCD frame in a box. */
    n += snprintf(buf + n, sizeof(buf) - n, "  LCD:\x1b[K\r\n");
    n += snprintf(buf + n, sizeof(buf) - n, "  +");
    for (int i = 0; i < cols; i++) n += snprintf(buf + n, sizeof(buf) - n, "-");
    n += snprintf(buf + n, sizeof(buf) - n, "+\x1b[K\r\n");
    for (int r = 0; r < lcd->rows; r++) {
        n += snprintf(buf + n, sizeof(buf) - n, "  |%.*s|\x1b[K\r\n",
                      cols, lcdbuf + r * cols);
    }
    n += snprintf(buf + n, sizeof(buf) - n, "  +");
    for (int i = 0; i < cols; i++) n += snprintf(buf + n, sizeof(buf) - n, "-");
    n += snprintf(buf + n, sizeof(buf) - n, "+\x1b[K\r\n\r\n");

    /* LED + button indicators. The on-LEDs get a brighter color.
     *   morse LED on PB6 (toggled by the morse demo task)
     *   control LED on PA2 (toggled by the led_control task on each
     *     button press; see prg_led_control.inc)
     *   button on PA1 (SPACE toggles its level) */
    n += snprintf(buf + n, sizeof(buf) - n,
        "  LED PB6: %s%s\x1b[0m   LED PA2: %s%s\x1b[0m   BTN PA1: %s%s\x1b[0m   (SPACE)\x1b[K\r\n\r\n",
        led  ? "\x1b[1;33m" : "\x1b[2m", led  ? "[*]" : "[ ]",
        led2 ? "\x1b[1;33m" : "\x1b[2m", led2 ? "[*]" : "[ ]",
        btn  ? "\x1b[1;32m" : "\x1b[2m", btn  ? "[*]" : "[ ]");

    /* PORTA pins, MSB on the left. Each bit and each label gets a
     * 4-char column (longest label is 3 chars + 1 space of leading
     * pad) so the rows line up vertically. */
    n += snprintf(buf + n, sizeof(buf) - n, "  PORTA bits: ");
    for (int i = 7; i >= 0; i--) {
        n += snprintf(buf + n, sizeof(buf) - n, "   %s%d\x1b[0m",
                      (porta & (1u << i)) ? "\x1b[1m" : "\x1b[2m",
                      (porta >> i) & 1);
    }
    n += snprintf(buf + n, sizeof(buf) - n, "    DDRA=$%02X\x1b[K\r\n", via->ddra);
    n += snprintf(buf + n, sizeof(buf) - n, "              ");
    for (int i = 7; i >= 0; i--) {
        n += snprintf(buf + n, sizeof(buf) - n, "%4s", PORTA_LABELS[i]);
    }
    n += snprintf(buf + n, sizeof(buf) - n, "\x1b[K\r\n\r\n");

    n += snprintf(buf + n, sizeof(buf) - n, "  PORTB bits: ");
    for (int i = 7; i >= 0; i--) {
        n += snprintf(buf + n, sizeof(buf) - n, "   %s%d\x1b[0m",
                      (portb & (1u << i)) ? "\x1b[1m" : "\x1b[2m",
                      (portb >> i) & 1);
    }
    n += snprintf(buf + n, sizeof(buf) - n, "    DDRB=$%02X\x1b[K\r\n", via->ddrb);
    n += snprintf(buf + n, sizeof(buf) - n, "              ");
    for (int i = 7; i >= 0; i--) {
        n += snprintf(buf + n, sizeof(buf) - n, "%4s", PORTB_LABELS[i]);
    }
    n += snprintf(buf + n, sizeof(buf) - n, "\x1b[K\r\n\r\n");

    /* Status line: osc, cpu, pc, IRQ, halt reason. */
    n += snprintf(buf + n, sizeof(buf) - n,
        "  osc:%llu  cpu:%llu  pc:$%04X  irq:%d  %s\x1b[K\r\n",
        (unsigned long long)b->osc_ticks,
        (unsigned long long)clockticks6502,
        pc, b->irq,
        cpu_stp_pending() ? "[STP]" : (cap_hit ? "[CAP]" : ""));

    /* Clear from cursor to end of screen so a shrinking frame
     * doesn't leave garbage below. */
    n += snprintf(buf + n, sizeof(buf) - n, "\x1b[J");

    (void)n;
    live_emit(buf);
}

/* Returns 1 if user hit a quit key, 0 otherwise. Reads at most a few
 * bytes; SPACE toggles the button via led_buttons_press(). */
static int live_poll_input(struct led_buttons_state *ledbtn) {
    fd_set fds;
    struct timeval tv = {0, 0};
    FD_ZERO(&fds);
    FD_SET(0, &fds);
    if (select(1, &fds, NULL, NULL, &tv) <= 0) return 0;

    unsigned char buf[16];
    ssize_t n = read(0, buf, sizeof(buf));
    for (ssize_t i = 0; i < n; i++) {
        unsigned char c = buf[i];
        if (c == 'q' || c == 'Q' || c == 0x03 /* Ctrl-C */ || c == 0x1B /* ESC */) {
            return 1;
        } else if (c == ' ') {
            led_buttons_press(ledbtn, !ledbtn->button_pressed);
        }
    }
    return 0;
}

/* Wall-clock pace helper: given a fixed-rate reference (t0, osc0,
 * osc_per_us), sleep enough that emulated osc ticks track wall time.
 * Caller has just stepped a batch; this checks whether the emulator
 * is ahead-of-wall and sleeps if so. Returns the current wall-time
 * delta in nanoseconds (caller may use it for render scheduling). */
static long wendy2c_pace(const struct timespec *t0,
                         uint64_t osc0, uint64_t osc_now,
                         double osc_per_us) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long wall_ns = (long)(now.tv_sec - t0->tv_sec) * 1000000000L
                  + (now.tv_nsec - t0->tv_nsec);
    if (osc_per_us <= 0.0) return wall_ns;
    double emu_us = (double)(osc_now - osc0) / osc_per_us;
    long emu_ns = (long)(emu_us * 1000.0);
    long ahead_ns = emu_ns - wall_ns;
    if (ahead_ns > 200000L /* 0.2 ms */) {
        struct timespec ts = { ahead_ns / 1000000000L, ahead_ns % 1000000000L };
        nanosleep(&ts, NULL);
        clock_gettime(CLOCK_MONOTONIC, &now);
        wall_ns = (long)(now.tv_sec - t0->tv_sec) * 1000000000L
                 + (now.tv_nsec - t0->tv_nsec);
    }
    return wall_ns;
}

static int emu_run_wendy2c_live(struct bus *b,
                                struct lcd_hd44780_state *lcd,
                                struct via_6522_state *via,
                                struct led_buttons_state *ledbtn,
                                uint64_t cap,
                                double osc_per_us) {
    /* Install BEFORE entering the alt screen so that a Ctrl-C arriving
     * any time after the termios switch flows through sigint_requested
     * (caught by the loop below) instead of taking the default action,
     * which would kill the process with the cursor hidden and the alt
     * screen still active. The atexit registration covers exit paths
     * that don't go through the loop's quit checks. */
    install_tty_cleanup_handlers();
    tty_alt_screen_enter();
    /* Hide cursor; clear screen once so the home-and-overwrite render
     * pattern starts on a clean slate. */
    live_emit("\x1b[?25l\x1b[2J");

    /* Pacing rate: --mhz N sets the OSC clock (the 22V10 halves it
     * for the CPU). Default to 20 osc/us (~10 MHz CPU) when --mhz is
     * unset so the LED-blink and morse demos look right; the real
     * board's CLOCK_FREQ_KHZ is 9720, so this is roughly 2x real. */
    if (osc_per_us <= 0.0) osc_per_us = 20.0;
    const long FRAME_NS = 30 * 1000 * 1000; /* ~33 fps */

    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    uint64_t osc0 = b->osc_ticks;
    long last_render_ns = 0;

    int quit = 0, cap_hit = 0;
    /* Initial render so the user sees the panel immediately. */
    live_render(b, lcd, via, ledbtn, 0);

    while (!quit && !sigint_requested) {
        /* Step a batch of osc ticks. Batch size tuned so the inner
         * loop has minimal overhead between renders. */
        const int BATCH = 2000;
        for (int i = 0; i < BATCH; i++) {
            if (b->osc_ticks >= cap) { cap_hit = 1; break; }
            bus_step(b);
            if (cpu_stp_pending()) break;
        }
        if (cpu_stp_pending() || cap_hit) break;

        long wall_ns = wendy2c_pace(&t0, osc0, b->osc_ticks, osc_per_us);

        if (wall_ns - last_render_ns >= FRAME_NS) {
            live_render(b, lcd, via, ledbtn, 0);
            last_render_ns = wall_ns;
        }

        if (live_poll_input(ledbtn)) quit = 1;
    }

    /* Final render captures the last frame before tearing down the
     * alt screen. */
    live_render(b, lcd, via, ledbtn, cap_hit);
    /* Brief pause so the user sees the final state before we restore
     * the original terminal contents. */
    if (cpu_stp_pending() || cap_hit) {
        struct timespec ts = { 0, 250 * 1000 * 1000 };
        nanosleep(&ts, NULL);
    }

    live_emit("\x1b[?25h"); /* show cursor */
    tty_alt_screen_leave();
    return cap_hit ? 0 : 0; /* cap is normal exit for live mode */
}

int emu_run_wendy2c(const struct emu_opts *opts) {
    cpu_variant = opts->cpu_variant_opt;

    static struct clock_22v10_state clk_state;
    static struct rom_28c256_state  rom_state;
    static struct ram_628128_state  ram_state;
    static struct via_6522_state    via_state;
    static struct lcd_hd44780_state lcd_state;
    static struct serial_usb_state  ser_state;
    static struct led_buttons_state ledbtn_state;
    static struct cpu_65c02_state   cpu_state;
    struct chip clk_chip, rom_chip, ram_chip, via_chip, lcd_chip, ser_chip, ledbtn_chip, cpu_chip;

    clock_22v10_init(&clk_chip, &clk_state);
    rom_28c256_init(&rom_chip, &rom_state);
    ram_628128_init(&ram_chip, &ram_state);
    via_6522_init  (&via_chip, &via_state);
    lcd_hd44780_init(&lcd_chip, &lcd_state, &via_state);
    serial_usb_init(&ser_chip, &ser_state, &via_state);
    led_buttons_init(&ledbtn_chip, &ledbtn_state, &via_state);
    cpu_65c02_init (&cpu_chip, &cpu_state);

    /* Load ROM image. Falls back to code_filename if --rom is omitted. */
    const char *rom_path = opts->rom_filename ? opts->rom_filename
                                              : opts->code_filename;
    if (rom_path) {
        if (rom_28c256_load(&rom_state, rom_path) != 0) {
            fprintf(stderr, "wendy2c: could not load ROM image: %s\n", rom_path);
            return 1;
        }
    } else {
        fprintf(stderr, "wendy2c: no ROM image (use --rom PATH or positional argv)\n");
        return 1;
    }

    struct bus b;
    bus_init(&b);
    /* The clock must be the FIRST chip so wendy2c_cpu_read/write can
     * tick it before bus_read/bus_write fans out to ROM/RAM. */
    bus_add_chip(&b, &clk_chip);
    bus_add_chip(&b, &rom_chip);
    bus_add_chip(&b, &ram_chip);
    bus_add_chip(&b, &via_chip);
    bus_add_chip(&b, &lcd_chip);
    bus_add_chip(&b, &ser_chip);
    bus_add_chip(&b, &ledbtn_chip);
    bus_add_chip(&b, &cpu_chip);

    /* Pre-load any --serial-input bytes into the SERIAL_USB queue. */
    if (opts->serial_input_filename) {
        FILE *sf = fopen(opts->serial_input_filename, "rb");
        if (!sf) {
            fprintf(stderr, "wendy2c: could not open --serial-input %s\n",
                    opts->serial_input_filename);
            return 1;
        }
        int byte;
        while ((byte = fgetc(sf)) != EOF) {
            if (serial_usb_queue_byte(&ser_state, (uint8_t)byte) < 0) break;
        }
        fclose(sf);
    }

    active_bus = &b;
    cpu_external_read  = wendy2c_cpu_read;
    cpu_external_write = wendy2c_cpu_write;

    /* Pulse RES so the CPU latches its reset vector through the bus
     * (i.e. through the ROM at $FFFC/$FFFD). */
    b.res = 1;
    for (int i = 0; i < 8; i++) bus_step(&b);
    b.res = 0;

    /* Run until STP halts the CPU or we hit the cycle cap. The cap also
     * limits run-away tests; the wendy2c sample programs that use STP
     * (e.g. wendy2c_eeprom_show.s) terminate well within the default.
     *
     * Under --live the cap defaults to "unlimited" -- the user quits
     * interactively (q/ESC/Ctrl-C) -- mirroring how --console and
     * --terminal modes in emu_run.c bypass the cap entirely. An
     * explicit --cycle-cap still takes effect (useful for scripted
     * recordings). */
    uint64_t cap = opts->cycle_cap;
    if (opts->live && !opts->cycle_cap_set) cap = UINT64_MAX;

    /* --mhz N pins the OSC (crystal) frequency. The 22V10 PLD halves
     * it for the CPU clock, so a --mhz 9.72 run matches the real
     * wendy2c board's CLOCK_FREQ_KHZ = 9720. 0 means "no throttle":
     * non-live runs uncapped; --live falls back to a default pace
     * inside emu_run_wendy2c_live. */
    double osc_per_us = opts->target_mhz > 0.0 ? opts->target_mhz : 0.0;

    if (opts->live) {
        emu_run_wendy2c_live(&b, &lcd_state, &via_state, &ledbtn_state, cap, osc_per_us);
    } else if (osc_per_us > 0.0) {
        /* Throttled non-live: step in batches and sleep when ahead-
         * of-wall so wall time tracks emulated osc time. */
        struct timespec t0;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        uint64_t osc0 = b.osc_ticks;
        while (b.osc_ticks < cap) {
            const int BATCH = 50000;
            int stp = 0;
            for (int i = 0; i < BATCH && b.osc_ticks < cap; i++) {
                bus_step(&b);
                if (cpu_stp_pending()) { stp = 1; break; }
            }
            if (stp) break;
            (void)wendy2c_pace(&t0, osc0, b.osc_ticks, osc_per_us);
        }
    } else {
        while (b.osc_ticks < cap) {
            bus_step(&b);
            if (cpu_stp_pending()) break;
        }
    }

    int halted_on_stp = cpu_stp_pending();
    fprintf(stderr,
        "wendy2c: exit  osc_ticks=%llu  cpu_cycles=%llu  pc=$%04X  %s\n",
        (unsigned long long)b.osc_ticks,
        (unsigned long long)clockticks6502,
        pc,
        halted_on_stp ? "(STP)" : "(cycle cap)");

    /* Print final LCD frame so the user sees what landed. */
    char lcd_buf[LCD_DDRAM_SIZE + 8];
    (void)lcd_hd44780_render(&lcd_state, lcd_buf);
    int cols = lcd_state.cols;
    fprintf(stderr, "wendy2c: lcd:\n");
    for (int r = 0; r < lcd_state.rows; r++) {
        fprintf(stderr, "  |%.*s|\n", cols, lcd_buf + r * cols);
    }

    /* Tear down the external hooks before returning so other code (e.g.
     * the test harness or a subsequent run) doesn't dangle on a dead
     * bus pointer. */
    cpu_external_read  = NULL;
    cpu_external_write = NULL;
    active_bus = NULL;

    /* Cycle-cap reached on a long-running program (e.g. one without
     * STP) is not necessarily a failure -- the LCD frame above shows
     * what landed. Reserve non-zero exit for clear setup errors. */
    (void)halted_on_stp;
    return 0;
}

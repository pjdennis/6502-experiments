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

/* PORTA / PORTB pin labels for the wendy2c. Several pins are
 * multiplexed between LCD and graphic-display; the labels chosen here
 * reflect the most common interpretation in the existing wendy2c
 * sample programs (base_config_wendy2c.inc). */
static const char *PORTA_LABELS[8] = {
    /* PA0 */ "RS",   /* DISPLAY RS / GD_CLK */
    /* PA1 */ "GDR",  /* GD_RSTB */
    /* PA2 */ "GDC",  /* GD_CSB */
    /* PA3 */ "RW",   /* DISPLAY RW / GD_DC */
    /* PA4 */ "D4",   /* LCD D4 / GD_MOSI */
    /* PA5 */ "BTN",  /* control button / GD_MISO (placeholder; see led_buttons.h) */
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
    int led = led_buttons_led(ledbtn);
    int btn = led_buttons_button(ledbtn);

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

    /* LED + button indicators. The on-LED gets a brighter color. */
    n += snprintf(buf + n, sizeof(buf) - n,
        "  LED PB6: %s%s\x1b[0m    BTN PA5: %s%s\x1b[0m   (SPACE)\x1b[K\r\n\r\n",
        led ? "\x1b[1;33m" : "\x1b[2m", led ? "[*]" : "[ ]",
        btn ? "\x1b[1;32m" : "\x1b[2m", btn ? "[*]" : "[ ]");

    /* PORTA pins, MSB on the left. */
    n += snprintf(buf + n, sizeof(buf) - n, "  PORTA bits: ");
    for (int i = 7; i >= 0; i--) {
        n += snprintf(buf + n, sizeof(buf) - n, " %s%d\x1b[0m",
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
        n += snprintf(buf + n, sizeof(buf) - n, " %s%d\x1b[0m",
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

static int emu_run_wendy2c_live(struct bus *b,
                                struct lcd_hd44780_state *lcd,
                                struct via_6522_state *via,
                                struct led_buttons_state *ledbtn,
                                uint64_t cap) {
    tty_alt_screen_enter();
    /* Hide cursor; clear screen once so the home-and-overwrite render
     * pattern starts on a clean slate. */
    live_emit("\x1b[?25l\x1b[2J");

    /* Pace at ~10 MHz CPU = ~20 MHz oscillator so the LED-blink and
     * morse demos look right. The wendy2c board's real CLOCK_FREQ_KHZ
     * is 9720 (from base_config_wendy2c.inc); we round up to a clean
     * 20 osc/us. */
    const double OSC_PER_US = 20.0;
    const long FRAME_NS = 30 * 1000 * 1000; /* ~33 fps */

    struct timespec t0, now;
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

        /* Pace: how much wall-time should have passed for the osc
         * ticks we've burned through? Sleep the difference if we ran
         * ahead. */
        clock_gettime(CLOCK_MONOTONIC, &now);
        long wall_ns = (long)(now.tv_sec - t0.tv_sec) * 1000000000L
                      + (now.tv_nsec - t0.tv_nsec);
        double emu_us = (double)(b->osc_ticks - osc0) / OSC_PER_US;
        long emu_ns = (long)(emu_us * 1000.0);
        long ahead_ns = emu_ns - wall_ns;
        if (ahead_ns > 200000L /* 0.2 ms */) {
            struct timespec ts = { ahead_ns / 1000000000L, ahead_ns % 1000000000L };
            nanosleep(&ts, NULL);
            clock_gettime(CLOCK_MONOTONIC, &now);
            wall_ns = (long)(now.tv_sec - t0.tv_sec) * 1000000000L
                     + (now.tv_nsec - t0.tv_nsec);
        }

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
     * (e.g. wendy2c_eeprom_show.s) terminate well within the default. */
    const uint64_t cap = opts->cycle_cap;
    if (opts->live) {
        emu_run_wendy2c_live(&b, &lcd_state, &via_state, &ledbtn_state, cap);
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

/* Phase 8: cpu_65c02 chip + emu_run_wendy2c smoke test.
 * Builds a synthetic 32 KiB ROM, calls emu_run_wendy2c, and verifies
 * the CPU executed the program and halted on STP. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include <signal.h>

#include "greatest.h"
#include "../audio.h"
#include "../cli.h"
#include "../emu_wendy2c.h"
#include "../cpu_core.h"

/* The host's read6502/write6502 are required by cpu_core.c at link
 * time but never actually called during a wendy2c run (the CPU goes
 * through cpu_external_read/cpu_external_write instead). */
uint8_t read6502(uint16_t addr) { (void)addr; return 0xFF; }
void    write6502(uint16_t addr, uint8_t v) { (void)addr; (void)v; }

/* emu_wendy2c.c references this global (defined in emulator.c) for
 * the --live render loop. The smoke test never exercises live mode
 * but still needs the symbol at link time. */
volatile sig_atomic_t sigint_requested = 0;

/* Same deal for install_tty_cleanup_handlers (defined in emulator.c)
 * and audio_init/audio_step/audio_close (defined in audio.c). The
 * live runner / --wav / --audio paths call these; the tests in this
 * file never go down those paths, but the linker still wants the
 * symbols. Stubs keep the test lean (no miniaudio drag-in, no
 * terminal-mode wiring). */
void install_tty_cleanup_handlers(void) { /* no-op for tests */ }
int  audio_init(struct audio_state *a, int sample_rate,
                const char *wav_path, int enable_live, double osc_per_us) {
    (void)sample_rate; (void)wav_path; (void)enable_live; (void)osc_per_us;
    if (a) memset(a, 0, sizeof(*a));   /* enabled=0 -> audio_step no-op */
    return 0;
}
void audio_step(struct audio_state *a, uint64_t osc, uint8_t pins) {
    (void)a; (void)osc; (void)pins;
}
void audio_close(struct audio_state *a) { (void)a; }
void audio_set_tap(struct audio_state *a,
                   void (*cb)(void *user, int16_t sample), void *user) {
    (void)a; (void)cb; (void)user;
}

/* Same for the wendy2c_web symbols (defined in wendy2c_web.c). The
 * test never hits the --web path, but the linker still resolves
 * references in emu_run_wendy2c. Use forward-declared opaque types so
 * we don't have to include wendy2c_web.h here. */
struct wendy2c_web_server;
struct wendy2c_web_event;
struct wendy2c_web_snapshot;
struct wendy2c_web_server *wendy2c_web_start(int port, const char *web_root) {
    (void)port; (void)web_root; return NULL;
}
void wendy2c_web_stop(struct wendy2c_web_server *srv) { (void)srv; }
int  wendy2c_web_poll(struct wendy2c_web_server *srv,
                      struct wendy2c_web_event *out_event) {
    (void)srv; (void)out_event; return 0;
}
void wendy2c_web_broadcast(struct wendy2c_web_server *srv,
                           const struct wendy2c_web_snapshot *snap) {
    (void)srv; (void)snap;
}
void wendy2c_web_send_audio_rate(struct wendy2c_web_server *srv, int sample_rate) {
    (void)srv; (void)sample_rate;
}
void wendy2c_web_audio_tap(void *user, int16_t sample) {
    (void)user; (void)sample;
}
void wendy2c_web_flush_audio(struct wendy2c_web_server *srv) { (void)srv; }

static const char *write_synthetic_rom(const uint8_t *prog, size_t prog_len) {
    /* Fresh template per call -- mkstemp mutates it, so a static buffer
     * would make any second call in the same test process fail. */
    static char path[32];
    strcpy(path, "/tmp/wendy2c_test_XXXXXX");
    int fd = mkstemp(path);
    if (fd < 0) return NULL;
    uint8_t rom[0x8000];
    memset(rom, 0xFF, sizeof(rom));
    if (prog_len > sizeof(rom) - 4) prog_len = sizeof(rom) - 4;
    memcpy(rom, prog, prog_len);
    /* Reset vector $FFFC/$FFFD -> $8000 (start of ROM). */
    rom[0x7FFC] = 0x00;
    rom[0x7FFD] = 0x80;
    rom[0x7FFE] = 0x00;
    rom[0x7FFF] = 0x80;
    if (write(fd, rom, sizeof(rom)) != sizeof(rom)) { close(fd); return NULL; }
    close(fd);
    return path;
}

TEST wai_wakes_on_masked_t2_irq(void) {
    /* Regression for the multitasking_test_wendy2c.s scheduler hang:
     * the IRQ handler executes WAI with I set (we are inside the
     * handler), expecting WAI to wake on the next T2 IRQ so the CPU
     * can run again. WAI must wake on any asserted IRQ/NMI regardless
     * of the I mask; only the dispatch is gated by I.
     *
     * Program (at $8000):
     *   SEI                        ; mask IRQs
     *   LDA #$80; STA T2CL ($F008) ; T2 low latch
     *   LDA #$00; STA T2CH ($F009) ; T2 high (starts T2)
     *   LDA #$A0; STA IER  ($F00E) ; IERSETCLEAR | IT2 enables T2
     *   WAI                        ; wait for T2 underflow
     *   STP                        ; halt cleanly
     *
     * If WAI honors the I mask (the pre-fix behavior) the run hits
     * the cycle cap and emu_run_wendy2c returns; we assert STP. */
    uint8_t prog[] = {
        0x78,                   /* SEI */
        0xA9, 0x80,             /* LDA #$80 */
        0x8D, 0x08, 0xF0,       /* STA T2CL */
        0xA9, 0x00,             /* LDA #$00 */
        0x8D, 0x09, 0xF0,       /* STA T2CH */
        0xA9, 0xA0,             /* LDA #$A0 (IERSETCLEAR | IT2) */
        0x8D, 0x0E, 0xF0,       /* STA IER */
        0xCB,                   /* WAI */
        0xDB                    /* STP */
    };
    const char *path = write_synthetic_rom(prog, sizeof(prog));
    ASSERT(path != NULL);

    struct emu_opts opts;
    emu_opts_init(&opts);
    opts.machine = MACHINE_WENDY2C;
    opts.cpu_variant_opt = CPU_65C02;
    opts.rom_filename = path;

    int rc = emu_run_wendy2c(&opts);
    ASSERT_EQ_FMT(0, rc, "%d");
    /* PC parked just past STP: 18 bytes of prog -> $8012. */
    ASSERT_EQ_FMT((uint16_t)0x8012, pc, "%04X");

    remove(path);
    PASS();
}

TEST cpu_executes_synthetic_rom_and_halts_on_stp(void) {
    /* LDA #$42; STA $0200; STP */
    uint8_t prog[] = { 0xA9, 0x42, 0x8D, 0x00, 0x02, 0xDB };
    const char *path = write_synthetic_rom(prog, sizeof(prog));
    ASSERT(path != NULL);

    struct emu_opts opts;
    emu_opts_init(&opts);
    opts.machine = MACHINE_WENDY2C;
    opts.cpu_variant_opt = CPU_65C02;
    opts.rom_filename = path;

    int rc = emu_run_wendy2c(&opts);
    /* Run returns 0 only on STP halt (not cycle-cap timeout). */
    ASSERT_EQ_FMT(0, rc, "%d");
    /* PC parked just past the STP byte ($8005 + 1 = $8006). */
    ASSERT_EQ_FMT((uint16_t)0x8006, pc, "%04X");
    /* CPU executed the program: 2(LDA) + 4(STA) + 3(STP) = 9 cycles. */
    ASSERT_EQ_FMT((unsigned long long)9,
                  (unsigned long long)clockticks6502, "%llu");

    remove(path);
    PASS();
}

TEST mhz_paces_osc_to_wall_clock(void) {
    /* --mhz N pins the OSC (crystal) frequency for wendy2c. Confirm
     * the non-live runner actually throttles to wall time: a cap of
     * 5M osc ticks at --mhz 5 should take ~1 s, well above the
     * uncapped throughput of ~24 MHz osc/s on a typical host. We use
     * a wide band so this stays CI-stable: at least 600 ms (cleanly
     * above the unthrottled ~210 ms minimum) and at most 3 s (well
     * above the 1 s ideal). The lower bound is what catches the
     * regression where --mhz is ignored.
     *
     * Program is a JMP-to-self at $8000: the CPU just spins so the
     * runner only exits on cap. */
    uint8_t prog[] = { 0x4C, 0x00, 0x80 };  /* JMP $8000 */
    const char *path = write_synthetic_rom(prog, sizeof(prog));
    ASSERT(path != NULL);

    struct emu_opts opts;
    emu_opts_init(&opts);
    opts.machine = MACHINE_WENDY2C;
    opts.cpu_variant_opt = CPU_65C02;
    opts.rom_filename = path;
    opts.cycle_cap = 5000000ULL;
    opts.cycle_cap_set = 1;
    opts.target_mhz = 5.0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int rc = emu_run_wendy2c(&opts);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long elapsed_ms = (t1.tv_sec - t0.tv_sec) * 1000L
                     + (t1.tv_nsec - t0.tv_nsec) / 1000000L;

    ASSERT_EQ_FMT(0, rc, "%d");
    if (elapsed_ms < 600) {
        FAILm("expected --mhz 5 to throttle 5M osc ticks to ~1 s; "
              "ran far too fast (--mhz almost certainly ignored)");
    }
    if (elapsed_ms > 3000) {
        FAILm("expected --mhz 5 to throttle 5M osc ticks to ~1 s; "
              "ran far too slow");
    }

    remove(path);
    PASS();
}

SUITE(cpu_65c02_chip_suite) {
    RUN_TEST(cpu_executes_synthetic_rom_and_halts_on_stp);
    RUN_TEST(wai_wakes_on_masked_t2_irq);
    RUN_TEST(mhz_paces_osc_to_wall_clock);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(cpu_65c02_chip_suite);
    GREATEST_MAIN_END();
}

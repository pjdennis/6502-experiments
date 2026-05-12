/* Phase 8: cpu_65c02 chip + emu_run_wendy2c smoke test.
 * Builds a synthetic 32 KiB ROM, calls emu_run_wendy2c, and verifies
 * the CPU executed the program and halted on STP. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <signal.h>

#include "greatest.h"
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

static const char *write_synthetic_rom(const uint8_t *prog, size_t prog_len) {
    static char path[] = "/tmp/wendy2c_test_XXXXXX";
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

SUITE(cpu_65c02_chip_suite) {
    RUN_TEST(cpu_executes_synthetic_rom_and_halts_on_stp);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(cpu_65c02_chip_suite);
    GREATEST_MAIN_END();
}

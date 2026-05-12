/* Klaus Dormann 6502/65C02 functional-test harness.
 *
 * Loads each binary into a 64 KiB test memory at $0000..$FFFF, sets
 * PC = $0400, and runs step6502() in a tight loop. The tests pass when
 * PC parks on a known "success" address (jmp *); fails when PC parks
 * on any other address (Klaus's error traps).
 *
 * The .bin files are produced by `tests/dormann/Makefile` (needs cc65
 * on PATH). If the .bin is missing, the relevant test reports SKIP. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

static uint8_t test_memory[0x10000];

uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

/* Load a Klaus binary (full 64 KiB memory image). Returns 0 on success,
 * -1 if the file is missing (caller should SKIP). */
static int load_binary(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t n = fread(test_memory, 1, sizeof(test_memory), f);
    fclose(f);
    if (n < 0x10000) {
        /* Klaus's bins are always 64 KiB. */
        fprintf(stderr, "test_dormann: %s read short (%zu bytes)\n", path, n);
        return -1;
    }
    return 0;
}

/* Run the loaded binary from $0400 until PC parks for >=2 consecutive
 * instructions. Returns the parked PC. */
static uint16_t run_until_trap(int variant) {
    cpu_variant = variant;
    pc = 0x0400;
    a = x = y = 0;
    sp = 0xFF;
    status = 0x24;  /* I=1, constant=1 */
    clockticks6502 = 0;
    clockgoal6502 = 0;

    uint16_t prev_pc = 0xFFFF;
    int stuck = 0;
    const uint64_t max_cycles = 200000000ULL;
    while (clockticks6502 < max_cycles) {
        uint16_t pc_before = pc;
        step6502();
        if (pc == pc_before) {
            stuck++;
            if (stuck >= 2) return pc;
        } else {
            stuck = 0;
        }
        prev_pc = pc_before;
    }
    (void)prev_pc;
    return 0xFFFF;  /* timed out without trap */
}

TEST dormann_nmos_functional(void) {
    const char *path = "emulator/tests/dormann/out/6502_functional_test.bin";
    if (load_binary(path) != 0) {
        SKIPm("Dormann NMOS binary not built; run `make -C emulator/tests/dormann`");
    }
    uint16_t trap = run_until_trap(CPU_NMOS);
    /* Expected success trap PC for the amb5l@966b1a35 build. */
    if (trap != 0x3469) {
        fprintf(stderr, "NMOS Dormann trapped at $%04X "
                "(ad1=$%02X ad2=$%02X adrl=$%02X adrh=$%02X a=$%02X sr=$%02X)\n",
                trap, test_memory[0x0D], test_memory[0x0E],
                test_memory[0x0F], test_memory[0x10], a, status);
    }
    ASSERT_EQ_FMT((uint16_t)0x3469, trap, "%04X");
    PASS();
}



TEST dormann_65c02_extended(void) {
    const char *path = "emulator/tests/dormann/out/65C02_extended_opcodes_test.bin";
    if (load_binary(path) != 0) {
        SKIPm("Dormann 65C02 binary not built; run `make -C emulator/tests/dormann`");
    }
    uint16_t trap = run_until_trap(CPU_65C02);
    if (trap != 0x24F1) {
        fprintf(stderr, "65C02 Dormann trapped at $%04X (a=$%02X x=$%02X y=$%02X sr=$%02X)\n",
                trap, a, x, y, status);
        fprintf(stderr, "Last bytes leading to trap: ");
        for (int i = -4; i <= 4; i++) {
            fprintf(stderr, "%02X ", test_memory[(trap + i) & 0xFFFF]);
        }
        fprintf(stderr, "\n");
    }
    ASSERT_EQ_FMT((uint16_t)0x24F1, trap, "%04X");
    PASS();
}

SUITE(dormann_suite) {
    RUN_TEST(dormann_nmos_functional);
    RUN_TEST(dormann_65c02_extended);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(dormann_suite);
    GREATEST_MAIN_END();
}

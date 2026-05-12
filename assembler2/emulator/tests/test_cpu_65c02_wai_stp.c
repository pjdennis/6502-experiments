/* Phase 3f: WAI ($CB) and STP ($DB). */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

static uint8_t test_memory[0x10000];
uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

static void setup(uint16_t entry, const uint8_t *bytes, size_t n) {
    memset(test_memory, 0, sizeof(test_memory));
    memcpy(test_memory + entry, bytes, n);
    test_memory[0xFFFC] = (uint8_t)(entry & 0xFF);
    test_memory[0xFFFD] = (uint8_t)(entry >> 8);
    test_memory[0xFFFE] = 0x00;
    test_memory[0xFFFF] = 0x03;  /* IRQ vector = $0300 */
    cpu_variant = CPU_65C02;
    reset6502();
}

TEST wai_pauses_until_irq(void) {
    uint8_t prog[] = {
        0xCB,                /* WAI at $0200 */
        0xA9, 0x42,          /* LDA #$42 at $0201 (after IRQ returns) */
        0x00                 /* BRK */
    };
    setup(0x0200, prog, sizeof(prog));
    /* IRQ handler at $0300: just RTI */
    test_memory[0x0300] = 0x40;  /* RTI */

    step6502();  /* WAI: pc -> $0201, wai_pending = 1 */
    ASSERT_EQ_FMT((uint16_t)0x0201, pc, "%04X");

    uint16_t pc_after_wai = pc;
    uint64_t ticks_after_wai = clockticks6502;

    /* While waiting, step6502 should not advance PC. */
    step6502();
    step6502();
    step6502();
    ASSERT_EQ_FMT(pc_after_wai, pc, "%04X");
    ASSERT(clockticks6502 > ticks_after_wai);

    /* Trigger IRQ; should wake from WAI and jump to vector. */
    irq6502();
    ASSERT_EQ_FMT((uint16_t)0x0300, pc, "%04X");

    /* Execute RTI; PC returns to instruction after WAI. */
    step6502();  /* RTI */
    ASSERT_EQ_FMT((uint16_t)0x0201, pc, "%04X");

    /* And the LDA #$42 still runs normally. */
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%02X");

    cpu_variant = CPU_NMOS;
    PASS();
}

TEST stp_halts_until_reset(void) {
    uint8_t prog[] = {
        0xDB,                /* STP at $0200 */
        0xA9, 0x42,          /* LDA #$42 at $0201 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    a = 0;

    step6502();  /* STP: pc -> $0201, stp_pending = 1 */
    ASSERT_EQ_FMT((uint16_t)0x0201, pc, "%04X");

    /* Subsequent steps do nothing; PC stays put, A stays 0. */
    for (int i = 0; i < 5; i++) step6502();
    ASSERT_EQ_FMT((uint16_t)0x0201, pc, "%04X");
    ASSERT_EQ_FMT((uint8_t)0, a, "%02X");

    /* IRQ should NOT clear STP. */
    irq6502();
    /* irq6502 pushed PC and jumped to vector $0300, but stp_pending is
     * still 1, so step6502 should not actually execute anything. */
    step6502();
    ASSERT_EQ_FMT((uint16_t)0x0300, pc, "%04X");

    /* Reset clears STP. Re-aim the reset vector at the LDA. */
    test_memory[0xFFFC] = 0x01;
    test_memory[0xFFFD] = 0x02;
    reset6502();
    step6502();  /* LDA #$42 */
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%02X");

    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(wai_stp_suite) {
    RUN_TEST(wai_pauses_until_irq);
    RUN_TEST(stp_halts_until_reset);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(wai_stp_suite);
    GREATEST_MAIN_END();
}

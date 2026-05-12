/* Phase 3d: 65C02 new opcodes group B
 *   $04/$0C TSB zp/abs       $14/$1C TRB zp/abs
 *   $12/$32/$52/$72/$92/$B2/$D2/$F2 ORA/AND/EOR/ADC/STA/LDA/CMP/SBC (zp)
 *   $7C JMP (abs,X)
 */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

#define FLAG_ZERO  0x02

static uint8_t test_memory[0x10000];
uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

static void setup(uint16_t entry, const uint8_t *bytes, size_t n) {
    memset(test_memory, 0, sizeof(test_memory));
    memcpy(test_memory + entry, bytes, n);
    test_memory[0xFFFC] = (uint8_t)(entry & 0xFF);
    test_memory[0xFFFD] = (uint8_t)(entry >> 8);
    test_memory[0xFFFE] = 0x00;
    test_memory[0xFFFF] = 0x90;
    cpu_variant = CPU_65C02;
    reset6502();
}

TEST tsb_zp_sets_bits_and_z_flag(void) {
    uint8_t prog[] = {
        0xA9, 0x06,           /* LDA #$06 */
        0x04, 0x50,           /* TSB $50 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0x03;  /* mem has bit 0+1; A=0x06 has bits 1+2 */
    step6502();  /* LDA */
    step6502();  /* TSB */
    /* A & M before write = 0x06 & 0x03 = 0x02, nonzero -> Z=0 */
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(status & FLAG_ZERO), "%02X");
    /* M after write = M | A = 0x03 | 0x06 = 0x07 */
    ASSERT_EQ_FMT((uint8_t)0x07, test_memory[0x0050], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST trb_abs_clears_bits_and_z_flag(void) {
    uint8_t prog[] = {
        0xA9, 0x0F,                /* LDA #$0F */
        0x1C, 0x00, 0x30,          /* TRB $3000 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x3000] = 0xF0;  /* A & M = 0F & F0 = 0 -> Z=1 */
    step6502();  /* LDA */
    step6502();  /* TRB */
    ASSERT_EQ_FMT((uint8_t)FLAG_ZERO, (uint8_t)(status & FLAG_ZERO), "%02X");
    /* M after write = M & ~A = 0xF0 & ~0x0F = 0xF0 */
    ASSERT_EQ_FMT((uint8_t)0xF0, test_memory[0x3000], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST lda_zp_indirect_with_wrap(void) {
    /* (zp) addressing should wrap on zp+1. Set zp pointer at $FF/$00. */
    uint8_t prog[] = {
        0xB2, 0xFF,           /* LDA ($FF) */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x00FF] = 0x34;  /* lo of pointer */
    test_memory[0x0000] = 0x12;  /* hi of pointer (wrap from $FF+1) */
    test_memory[0x1234] = 0x77;
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x77, a, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST sta_zp_indirect(void) {
    uint8_t prog[] = {
        0xA9, 0x42,           /* LDA #$42 */
        0x92, 0x10,           /* STA ($10) */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0010] = 0x00;
    test_memory[0x0011] = 0x40;
    step6502();
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x42, test_memory[0x4000], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST jmp_abs_indexed_indirect(void) {
    /* JMP ($3000,X) with X=$04 -> read from $3004/$3005. */
    uint8_t prog[] = {
        0xA2, 0x04,                /* LDX #$04 */
        0x7C, 0x00, 0x30,          /* JMP ($3000,X) */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x3004] = 0x00;
    test_memory[0x3005] = 0x60;
    step6502();  /* LDX */
    step6502();  /* JMP */
    ASSERT_EQ_FMT((uint16_t)0x6000, pc, "%04X");
    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(group_b_suite) {
    RUN_TEST(tsb_zp_sets_bits_and_z_flag);
    RUN_TEST(trb_abs_clears_bits_and_z_flag);
    RUN_TEST(lda_zp_indirect_with_wrap);
    RUN_TEST(sta_zp_indirect);
    RUN_TEST(jmp_abs_indexed_indirect);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(group_b_suite);
    GREATEST_MAIN_END();
}

/* Phase 3b: 65C02 baseline fixes vs. NMOS.
 *   - JMP ($abcd) page-bug: NMOS reads the high byte with low-byte page-wrap;
 *     65C02 reads ($abcd+1) cleanly.
 *   - ADC/SBC decimal mode: N/Z computed from the BCD-adjusted result on
 *     65C02; NMOS leaves them from the binary intermediate.
 *   - BRK: 65C02 clears D after pushing status; NMOS leaves D set. */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

#define FLAG_CARRY     0x01
#define FLAG_ZERO      0x02
#define FLAG_INTERRUPT 0x04
#define FLAG_DECIMAL   0x08
#define FLAG_BREAK     0x10
#define FLAG_CONSTANT  0x20
#define FLAG_OVERFLOW  0x40
#define FLAG_SIGN      0x80

static uint8_t test_memory[0x10000];

uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

static void load_at(uint16_t addr, const uint8_t *bytes, size_t n) {
    memcpy(test_memory + addr, bytes, n);
}

static void clear_memory_and_vector_to(uint16_t entry) {
    memset(test_memory, 0, sizeof(test_memory));
    test_memory[0xFFFC] = (uint8_t)(entry & 0xFF);
    test_memory[0xFFFD] = (uint8_t)(entry >> 8);
    test_memory[0xFFFE] = 0x00;
    test_memory[0xFFFF] = 0x90;  /* IRQ vector at $9000 (somewhere quiet) */
}

/* JMP ($10FF): pointer at $10FF+$1100 on 65C02; $10FF+$1000 on NMOS. */
TEST jmp_indirect_no_page_bug_on_65c02(void) {
    clear_memory_and_vector_to(0x0200);
    uint8_t prog[] = {0x6C, 0xFF, 0x10};  /* JMP ($10FF) */
    load_at(0x0200, prog, sizeof(prog));
    test_memory[0x10FF] = 0xAA;  /* low byte of target */
    test_memory[0x1000] = 0xFA;  /* what NMOS would read for high byte */
    test_memory[0x1100] = 0xBB;  /* what 65C02 reads for high byte */

    cpu_variant = CPU_65C02;
    reset6502();
    step6502();
    ASSERT_EQ_FMT((uint16_t)0xBBAA, pc, "%04X");

    cpu_variant = CPU_NMOS;
    reset6502();
    step6502();
    ASSERT_EQ_FMT((uint16_t)0xFAAA, pc, "%04X");

    cpu_variant = CPU_NMOS;
    PASS();
}

/* SED; CLC; LDA #$99; ADC #$01 -> A=$00 in BCD. 65C02 sets Z=1; NMOS
 * leaves Z reflecting the binary $9A which is non-zero, so Z=0. */
TEST adc_decimal_zero_flag_65c02(void) {
    clear_memory_and_vector_to(0x0200);
    uint8_t prog[] = {
        0xF8,             /* SED */
        0x18,             /* CLC */
        0xA9, 0x99,       /* LDA #$99 */
        0x69, 0x01,       /* ADC #$01 */
        0x00              /* BRK */
    };
    load_at(0x0200, prog, sizeof(prog));

    cpu_variant = CPU_65C02;
    reset6502();
    step6502();  /* SED */
    step6502();  /* CLC */
    step6502();  /* LDA #$99 */
    step6502();  /* ADC #$01 */
    ASSERT_EQ_FMT((uint8_t)0x00, a, "%02X");
    ASSERT_EQ_FMT((uint8_t)FLAG_CARRY, (uint8_t)(status & FLAG_CARRY), "%02X");
    ASSERT_EQ_FMT((uint8_t)FLAG_ZERO,  (uint8_t)(status & FLAG_ZERO),  "%02X");
    /* sign clear */
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(status & FLAG_SIGN), "%02X");

    cpu_variant = CPU_NMOS;
    PASS();
}

/* SED; SEC; LDA #$00; SBC #$01 -> A=$99 in BCD on 65C02. The result is
 * non-zero negative-looking but Z=0, N=1. */
TEST sbc_decimal_result_65c02(void) {
    clear_memory_and_vector_to(0x0200);
    uint8_t prog[] = {
        0xF8,             /* SED */
        0x38,             /* SEC */
        0xA9, 0x00,       /* LDA #$00 */
        0xE9, 0x01,       /* SBC #$01 */
        0x00
    };
    load_at(0x0200, prog, sizeof(prog));

    cpu_variant = CPU_65C02;
    reset6502();
    step6502();  /* SED */
    step6502();  /* SEC */
    step6502();  /* LDA */
    step6502();  /* SBC */
    ASSERT_EQ_FMT((uint8_t)0x99, a, "%02X");
    /* carry cleared because borrow occurred */
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(status & FLAG_CARRY), "%02X");
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(status & FLAG_ZERO), "%02X");
    ASSERT_EQ_FMT((uint8_t)FLAG_SIGN, (uint8_t)(status & FLAG_SIGN), "%02X");

    cpu_variant = CPU_NMOS;
    PASS();
}

/* BRK side-effects on D flag: 65C02 clears D, NMOS leaves it as-is. */
TEST brk_clears_decimal_on_65c02(void) {
    clear_memory_and_vector_to(0x0200);
    uint8_t prog[] = {
        0xF8,             /* SED */
        0x00              /* BRK */
    };
    load_at(0x0200, prog, sizeof(prog));

    cpu_variant = CPU_65C02;
    reset6502();
    step6502();  /* SED */
    ASSERT_EQ_FMT((uint8_t)FLAG_DECIMAL, (uint8_t)(status & FLAG_DECIMAL), "%02X");
    step6502();  /* BRK */
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(status & FLAG_DECIMAL), "%02X");

    cpu_variant = CPU_NMOS;
    clear_memory_and_vector_to(0x0200);
    load_at(0x0200, prog, sizeof(prog));
    reset6502();
    step6502();  /* SED */
    ASSERT_EQ_FMT((uint8_t)FLAG_DECIMAL, (uint8_t)(status & FLAG_DECIMAL), "%02X");
    step6502();  /* BRK */
    /* NMOS leaves D set */
    ASSERT_EQ_FMT((uint8_t)FLAG_DECIMAL, (uint8_t)(status & FLAG_DECIMAL), "%02X");

    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(cpu_65c02_fixes_suite) {
    RUN_TEST(jmp_indirect_no_page_bug_on_65c02);
    RUN_TEST(adc_decimal_zero_flag_65c02);
    RUN_TEST(sbc_decimal_result_65c02);
    RUN_TEST(brk_clears_decimal_on_65c02);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(cpu_65c02_fixes_suite);
    GREATEST_MAIN_END();
}

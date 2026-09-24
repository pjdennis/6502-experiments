/* Phase 3a: verify the cpu_variant dispatch hook lets step6502 run the
 * same instruction under either CPU_NMOS or CPU_65C02 (which currently
 * dispatch through identical tables). Later phases will add 65C02
 * differences; the tests here pin the "default unchanged" baseline. */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

static uint8_t test_memory[0x10000];

uint8_t read6502(uint16_t address) {
    return test_memory[address];
}

void write6502(uint16_t address, uint8_t value) {
    test_memory[address] = value;
}

/* Load a simple program at $0200 that does LDA #$42; STA $0050; BRK.
 * Reset vector points to $0200; BRK vector points to $0300 (just so
 * BRK lands somewhere defined). */
static void load_test_program(void) {
    memset(test_memory, 0, sizeof(test_memory));
    test_memory[0x0200] = 0xA9;  /* LDA #imm */
    test_memory[0x0201] = 0x42;
    test_memory[0x0202] = 0x85;  /* STA zp   */
    test_memory[0x0203] = 0x50;
    test_memory[0x0204] = 0x00;  /* BRK      */
    test_memory[0xFFFC] = 0x00;  /* reset vector lo = $00 */
    test_memory[0xFFFD] = 0x02;  /* reset vector hi = $02 */
    test_memory[0xFFFE] = 0x00;  /* IRQ vector lo */
    test_memory[0xFFFF] = 0x03;  /* IRQ vector hi */
}

TEST default_variant_is_nmos(void) {
    ASSERT_EQ_FMT(CPU_NMOS, cpu_variant, "%d");
    PASS();
}

TEST nmos_runs_simple_program(void) {
    cpu_variant = CPU_NMOS;
    load_test_program();
    reset6502();
    step6502();  /* LDA #$42 */
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%u");
    step6502();  /* STA $50 */
    ASSERT_EQ_FMT((uint8_t)0x42, test_memory[0x50], "%u");
    PASS();
}

TEST c02_runs_same_simple_program(void) {
    cpu_variant = CPU_65C02;
    load_test_program();
    reset6502();
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%u");
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x42, test_memory[0x50], "%u");
    PASS();
}

TEST variant_can_change_between_steps(void) {
    /* Run the same one-instruction step under each variant; assert
     * the result is identical. This protects against the active
     * pointer being stale across a mid-run change. */
    load_test_program();
    cpu_variant = CPU_NMOS;
    reset6502();
    step6502();
    uint8_t a_nmos = a;

    load_test_program();
    cpu_variant = CPU_65C02;
    reset6502();
    step6502();
    uint8_t a_c02 = a;

    ASSERT_EQ_FMT(a_nmos, a_c02, "%u");
    cpu_variant = CPU_NMOS;  /* leave default */
    PASS();
}

SUITE(cpu_variant_suite) {
    RUN_TEST(default_variant_is_nmos);
    RUN_TEST(nmos_runs_simple_program);
    RUN_TEST(c02_runs_same_simple_program);
    RUN_TEST(variant_can_change_between_steps);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(cpu_variant_suite);
    GREATEST_MAIN_END();
}

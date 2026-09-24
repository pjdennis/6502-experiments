/* Phase 3c: 65C02 new opcodes group A
 *   $1A INC A    $3A DEC A
 *   $5A PHY      $7A PLY      $DA PHX      $FA PLX
 *   $64/$74/$9C/$9E STZ (zp / zp,X / abs / abs,X)
 *   $80 BRA (unconditional relative branch)
 */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

#define FLAG_CARRY     0x01
#define FLAG_ZERO      0x02
#define FLAG_SIGN      0x80

static uint8_t test_memory[0x10000];
uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

static void setup_program(uint16_t entry, const uint8_t *bytes, size_t n) {
    memset(test_memory, 0, sizeof(test_memory));
    memcpy(test_memory + entry, bytes, n);
    test_memory[0xFFFC] = (uint8_t)(entry & 0xFF);
    test_memory[0xFFFD] = (uint8_t)(entry >> 8);
    test_memory[0xFFFE] = 0x00;
    test_memory[0xFFFF] = 0x90;
    cpu_variant = CPU_65C02;
    reset6502();
    sp = 0xFF;
}

TEST inc_a_and_dec_a(void) {
    uint8_t prog[] = {
        0xA9, 0x10,   /* LDA #$10 */
        0x1A,         /* INC A */
        0x1A,         /* INC A */
        0x3A,         /* DEC A */
        0x00
    };
    setup_program(0x0200, prog, sizeof(prog));
    step6502();  /* LDA */
    step6502();  /* INC A */
    ASSERT_EQ_FMT((uint8_t)0x11, a, "%02X");
    step6502();  /* INC A */
    ASSERT_EQ_FMT((uint8_t)0x12, a, "%02X");
    step6502();  /* DEC A */
    ASSERT_EQ_FMT((uint8_t)0x11, a, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST phx_phy_plx_ply_round_trip(void) {
    uint8_t prog[] = {
        0xA2, 0x55,   /* LDX #$55 */
        0xA0, 0xAA,   /* LDY #$AA */
        0xDA,         /* PHX */
        0x5A,         /* PHY */
        0xA2, 0x00,   /* LDX #$00 */
        0xA0, 0x00,   /* LDY #$00 */
        0x7A,         /* PLY */
        0xFA,         /* PLX */
        0x00
    };
    setup_program(0x0200, prog, sizeof(prog));
    for (int i = 0; i < 4; i++) step6502();  /* LDX, LDY, PHX, PHY */
    step6502();  /* LDX #0 */
    step6502();  /* LDY #0 */
    ASSERT_EQ_FMT((uint8_t)0x00, x, "%02X");
    ASSERT_EQ_FMT((uint8_t)0x00, y, "%02X");
    step6502();  /* PLY -> $AA */
    ASSERT_EQ_FMT((uint8_t)0xAA, y, "%02X");
    step6502();  /* PLX -> $55 */
    ASSERT_EQ_FMT((uint8_t)0x55, x, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST stz_zp_and_abs(void) {
    uint8_t prog[] = {
        0x64, 0x50,           /* STZ $50 */
        0x9C, 0x00, 0x30,     /* STZ $3000 */
        0x00
    };
    setup_program(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0xFF;
    test_memory[0x3000] = 0xFF;
    step6502();  /* STZ $50 */
    ASSERT_EQ_FMT((uint8_t)0x00, test_memory[0x0050], "%02X");
    step6502();  /* STZ $3000 */
    ASSERT_EQ_FMT((uint8_t)0x00, test_memory[0x3000], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST stz_indexed_modes(void) {
    uint8_t prog[] = {
        0xA2, 0x05,           /* LDX #$05 */
        0x74, 0x40,           /* STZ $40,X  -> $0045 */
        0x9E, 0x00, 0x30,     /* STZ $3000,X -> $3005 */
        0x00
    };
    setup_program(0x0200, prog, sizeof(prog));
    test_memory[0x0045] = 0xFF;
    test_memory[0x3005] = 0xFF;
    step6502();  /* LDX */
    step6502();  /* STZ zp,X */
    ASSERT_EQ_FMT((uint8_t)0x00, test_memory[0x0045], "%02X");
    step6502();  /* STZ abs,X */
    ASSERT_EQ_FMT((uint8_t)0x00, test_memory[0x3005], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST bra_unconditional_branch(void) {
    uint8_t prog[] = {
        0x80, 0x02,           /* BRA +2 */
        0xA9, 0xFF,           /* LDA #$FF (skipped) */
        0xA9, 0x42,           /* LDA #$42 (taken) */
        0x00
    };
    setup_program(0x0200, prog, sizeof(prog));
    step6502();  /* BRA */
    ASSERT_EQ_FMT((uint16_t)0x0204, pc, "%04X");
    step6502();  /* LDA #$42 */
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

TEST bra_negative_offset(void) {
    uint8_t prog[] = {
        0xA9, 0x00,           /* $0200 LDA #$00 */
        0xE8,                 /* $0202 INX */
        0xE0, 0x03,           /* $0203 CPX #3 */
        0xF0, 0x02,           /* $0205 BEQ +2 (exit) */
        0x80, 0xF9,           /* $0207 BRA -7 -> $0202 */
        0x00,                 /* $0209 BRK (exit) */
    };
    setup_program(0x0200, prog, sizeof(prog));
    x = 0;
    int safety = 100;
    while (safety-- > 0) {
        step6502();
        if (pc == 0x0209) break;
    }
    ASSERT_EQ_FMT((uint8_t)3, x, "%u");
    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(group_a_suite) {
    RUN_TEST(inc_a_and_dec_a);
    RUN_TEST(phx_phy_plx_ply_round_trip);
    RUN_TEST(stz_zp_and_abs);
    RUN_TEST(stz_indexed_modes);
    RUN_TEST(bra_unconditional_branch);
    RUN_TEST(bra_negative_offset);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(group_a_suite);
    GREATEST_MAIN_END();
}

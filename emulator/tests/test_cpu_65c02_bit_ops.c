/* Phase 3e: 65C02 RMB/SMB/BBR/BBS bit ops. 32 opcodes total. */

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
    test_memory[0xFFFF] = 0x90;
    cpu_variant = CPU_65C02;
    reset6502();
}

/* SMB0..7 set each bit of $50 from initial 0x00; verify resulting value. */
TEST smb_all_eight_bits(void) {
    uint8_t prog[] = {
        0x87, 0x50,   /* SMB0 $50 */
        0x97, 0x50,   /* SMB1 $50 */
        0xA7, 0x50,   /* SMB2 $50 */
        0xB7, 0x50,   /* SMB3 $50 */
        0xC7, 0x50,   /* SMB4 $50 */
        0xD7, 0x50,   /* SMB5 $50 */
        0xE7, 0x50,   /* SMB6 $50 */
        0xF7, 0x50,   /* SMB7 $50 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0x00;
    for (int i = 0; i < 8; i++) step6502();
    ASSERT_EQ_FMT((uint8_t)0xFF, test_memory[0x0050], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

/* RMB0..7 clear each bit of $50 from initial 0xFF. */
TEST rmb_all_eight_bits(void) {
    uint8_t prog[] = {
        0x07, 0x50,   /* RMB0 $50 */
        0x17, 0x50,   /* RMB1 $50 */
        0x27, 0x50,   /* RMB2 $50 */
        0x37, 0x50,   /* RMB3 $50 */
        0x47, 0x50,   /* RMB4 $50 */
        0x57, 0x50,   /* RMB5 $50 */
        0x67, 0x50,   /* RMB6 $50 */
        0x77, 0x50,   /* RMB7 $50 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0xFF;
    for (int i = 0; i < 8; i++) step6502();
    ASSERT_EQ_FMT((uint8_t)0x00, test_memory[0x0050], "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

/* BBR3 $50, +2 with bit 3 clear -> branch taken. */
TEST bbr_taken_when_bit_clear(void) {
    uint8_t prog[] = {
        0x3F, 0x50, 0x02,   /* BBR3 $50, +2  ($0200 -> $0205 if taken) */
        0xA9, 0xFF,         /* LDA #$FF      ($0203, should be skipped) */
        0xA9, 0x42,         /* LDA #$42      ($0205) */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0xF7;  /* bit 3 is 0 in 0xF7 */
    step6502();  /* BBR3 -> taken */
    ASSERT_EQ_FMT((uint16_t)0x0205, pc, "%04X");
    step6502();  /* LDA #$42 */
    ASSERT_EQ_FMT((uint8_t)0x42, a, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

/* BBS5 $50, +2 with bit 5 set -> branch taken. */
TEST bbs_taken_when_bit_set(void) {
    uint8_t prog[] = {
        0xDF, 0x50, 0x02,
        0xA9, 0xFF,
        0xA9, 0x77,
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0x20;  /* only bit 5 set */
    step6502();  /* BBS5 -> taken */
    ASSERT_EQ_FMT((uint16_t)0x0205, pc, "%04X");
    step6502();
    ASSERT_EQ_FMT((uint8_t)0x77, a, "%02X");
    cpu_variant = CPU_NMOS;
    PASS();
}

/* BBR not taken when the tested bit is set: PC advances past the 3-byte
 * instruction normally. */
TEST bbr_not_taken_when_bit_set(void) {
    uint8_t prog[] = {
        0x0F, 0x50, 0x10,   /* BBR0 $50, +16 */
        0x00
    };
    setup(0x0200, prog, sizeof(prog));
    test_memory[0x0050] = 0x01;  /* bit 0 set */
    step6502();
    ASSERT_EQ_FMT((uint16_t)0x0203, pc, "%04X");
    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(bit_ops_suite) {
    RUN_TEST(smb_all_eight_bits);
    RUN_TEST(rmb_all_eight_bits);
    RUN_TEST(bbr_taken_when_bit_clear);
    RUN_TEST(bbs_taken_when_bit_set);
    RUN_TEST(bbr_not_taken_when_bit_set);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(bit_ops_suite);
    GREATEST_MAIN_END();
}

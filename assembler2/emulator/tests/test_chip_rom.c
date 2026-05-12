/* Phase 6: 28C256 ROM module smoke test. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/rom_28c256.h"
#include "../chips/clock_22v10.h"

TEST rom_returns_bytes_when_romcs_asserted(void) {
    static struct rom_28c256_state rom_state;
    struct chip rom_chip;
    rom_28c256_init(&rom_chip, &rom_state);

    /* Stuff a recognizable pattern into the ROM image. */
    for (int i = 0; i < ROM_28C256_SIZE; i++) {
        rom_state.contents[i] = (uint8_t)(i & 0xFF);
    }

    /* Build a bus with the clock + ROM. Set addr in ROM range and read. */
    static struct clock_22v10_state clk_state;
    struct chip clk_chip;
    clock_22v10_init(&clk_chip, &clk_state);

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &clk_chip);
    bus_add_chip(&b, &rom_chip);

    b.addr = 0x8123;
    b.bank_config = 0x00;  /* bank0 -> ROM mapped at $8000+ */
    b.rwb = 1;
    bus_step(&b);  /* clock_22v10 sets romcs */
    ASSERT_EQ_FMT((uint8_t)1, b.romcs, "%u");

    uint8_t out = 0;
    int claimed = bus_read(&b, 0x8123, &out);
    ASSERT_EQ_FMT(1, claimed, "%d");
    ASSERT_EQ_FMT((uint8_t)0x23, out, "%02X");  /* low 8 bits of $8123 */
    PASS();
}

TEST rom_does_not_claim_when_romcs_deasserted(void) {
    static struct rom_28c256_state rom_state;
    struct chip rom_chip;
    rom_28c256_init(&rom_chip, &rom_state);
    rom_state.contents[0x1234] = 0x42;

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &rom_chip);
    b.addr = 0x1234;
    b.romcs = 0;
    b.rwb = 1;
    uint8_t out = 0xCC;
    int claimed = bus_read(&b, 0x1234, &out);
    ASSERT_EQ_FMT(0, claimed, "%d");
    ASSERT_EQ_FMT((uint8_t)0xCC, out, "%02X");
    PASS();
}

TEST rom_load_from_file(void) {
    /* Write a short test file and load it. */
    char path[] = "/tmp/rom_28c256_test_XXXXXX";
    int fd = mkstemp(path);
    ASSERT(fd >= 0);
    uint8_t payload[16];
    for (int i = 0; i < 16; i++) payload[i] = (uint8_t)(0xA0 + i);
    if (write(fd, payload, sizeof(payload)) != sizeof(payload)) FAIL();
    close(fd);

    static struct rom_28c256_state rom_state;
    struct chip rom_chip;
    rom_28c256_init(&rom_chip, &rom_state);

    int rc = rom_28c256_load(&rom_state, path);
    ASSERT_EQ_FMT(0, rc, "%d");
    for (int i = 0; i < 16; i++) {
        ASSERT_EQ_FMT(payload[i], rom_state.contents[i], "%02X");
    }
    /* Trailing fill is 0xFF. */
    ASSERT_EQ_FMT((uint8_t)0xFF, rom_state.contents[16], "%02X");
    ASSERT_EQ_FMT((uint8_t)0xFF, rom_state.contents[ROM_28C256_SIZE - 1], "%02X");
    remove(path);
    PASS();
}

SUITE(rom_28c256_suite) {
    RUN_TEST(rom_returns_bytes_when_romcs_asserted);
    RUN_TEST(rom_does_not_claim_when_romcs_deasserted);
    RUN_TEST(rom_load_from_file);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(rom_28c256_suite);
    GREATEST_MAIN_END();
}

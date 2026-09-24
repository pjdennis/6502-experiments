/* Phase 7: 628128 RAM bank-mapping smoke test. */

#include <stdint.h>
#include <stdlib.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/clock_22v10.h"
#include "../chips/ram_628128.h"

static struct ram_628128_state ram_state;
static struct clock_22v10_state clk_state;
static struct chip ram_chip, clk_chip;
static struct bus bus_;

static void setup(void) {
    ram_628128_init(&ram_chip, &ram_state);
    clock_22v10_init(&clk_chip, &clk_state);
    bus_init(&bus_);
    bus_add_chip(&bus_, &clk_chip);
    bus_add_chip(&bus_, &ram_chip);
}

TEST ram_write_read_round_trip(void) {
    setup();
    /* Bank 1 (config 00001 -> RAM mapped low), write to $0100, read back. */
    bus_.addr = 0x0100;
    bus_.bank_config = 0x01;
    bus_.rwb = 0;
    bus_step(&bus_);  /* clock asserts RAMCS for low-addr bank 1 */
    ASSERT_EQ_FMT((uint8_t)1, bus_.ramcs, "%u");
    int wclaim = bus_write(&bus_, 0x0100, 0x42);
    ASSERT_EQ_FMT(1, wclaim, "%d");

    /* Now read in the same bank. */
    bus_.rwb = 1;
    bus_step(&bus_);
    uint8_t data = 0;
    int rclaim = bus_read(&bus_, 0x0100, &data);
    ASSERT_EQ_FMT(1, rclaim, "%d");
    ASSERT_EQ_FMT((uint8_t)0x42, data, "%02X");
    PASS();
}

TEST ram_banks_are_physically_distinct(void) {
    setup();
    /* Write byte to $0200 in bank 1. */
    bus_.addr = 0x0200;
    bus_.bank_config = 0x01;
    bus_.rwb = 0;
    bus_step(&bus_);
    bus_write(&bus_, 0x0200, 0xAA);

    /* Switch to bank 2 (config 00010). Same address should now read 0. */
    bus_.bank_config = 0x02;
    bus_.rwb = 1;
    bus_step(&bus_);
    uint8_t data = 0;
    bus_read(&bus_, 0x0200, &data);
    ASSERT_EQ_FMT((uint8_t)0x00, data, "%02X");

    /* Switching back to bank 1 must still read 0xAA. */
    bus_.bank_config = 0x01;
    bus_step(&bus_);
    bus_read(&bus_, 0x0200, &data);
    ASSERT_EQ_FMT((uint8_t)0xAA, data, "%02X");
    PASS();
}

TEST ram_does_not_claim_in_via_window(void) {
    setup();
    /* $F500 is in the VIA window. Per the PLD, RAMCS is NOT asserted
     * (the equation includes VIA as one of the not-RAMCS terms). */
    bus_.addr = 0xF500;
    bus_.bank_config = 0x00;
    bus_.rwb = 1;
    bus_step(&bus_);
    ASSERT_EQ_FMT((uint8_t)1, bus_.viacs, "%u");
    ASSERT_EQ_FMT((uint8_t)0, bus_.ramcs, "%u");
    uint8_t data = 0xCC;
    int claimed = bus_read(&bus_, 0xF500, &data);
    ASSERT_EQ_FMT(0, claimed, "%d");
    PASS();
}

SUITE(ram_628128_suite) {
    RUN_TEST(ram_write_read_round_trip);
    RUN_TEST(ram_banks_are_physically_distinct);
    RUN_TEST(ram_does_not_claim_in_via_window);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(ram_628128_suite);
    GREATEST_MAIN_END();
}

/* Phase 9 VIA 6522 unit tests. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/via_6522.h"

static struct via_6522_state vs;
static struct chip vch;
static struct bus bus_;

static void setup(void) {
    via_6522_init(&vch, &vs);
    bus_init(&bus_);
    bus_add_chip(&bus_, &vch);
    bus_.viacs = 1;
}

static uint8_t r(uint8_t reg) {
    uint8_t v = 0;
    bus_read(&bus_, (uint16_t)(0xF000 | reg), &v);
    return v;
}

static void w(uint8_t reg, uint8_t val) {
    bus_write(&bus_, (uint16_t)(0xF000 | reg), val);
}

TEST init_state_is_zero(void) {
    setup();
    ASSERT_EQ_FMT((uint8_t)0, r(VIA_REG_ORB), "%02X");
    ASSERT_EQ_FMT((uint8_t)0, r(VIA_REG_ORA), "%02X");
    ASSERT_EQ_FMT((uint8_t)0, r(VIA_REG_DDRB), "%02X");
    ASSERT_EQ_FMT((uint8_t)0, r(VIA_REG_DDRA), "%02X");
    /* IFR/IER both 0; reading IER also forces bit 7 high. */
    ASSERT_EQ_FMT((uint8_t)0x80, r(VIA_REG_IER), "%02X");
    /* bus.bank_config reflects pull-down state (= 0). */
    ASSERT_EQ_FMT((uint8_t)0, bus_.bank_config, "%02X");
    /* No IRQ at reset. */
    ASSERT_EQ_FMT((uint8_t)0, bus_.irq, "%u");
    PASS();
}

TEST porta_input_output_direction(void) {
    setup();
    /* DDRA=$0F (low nibble out), ORA=$5A. PORTA reads back the
     * driven low nibble (= 0xA) with the high nibble at 0 (input,
     * floats 0 in our model since the wendy2c high-nibble pull is
     * off the LCD data side). */
    w(VIA_REG_DDRA, 0x0F);
    w(VIA_REG_ORA, 0x5A);
    ASSERT_EQ_FMT((uint8_t)0x0A, r(VIA_REG_ORA), "%02X");
    PASS();
}

/* PB0..PB4 drive bus.bank_config. */
TEST bank_config_follows_orb_and_ddrb(void) {
    setup();
    w(VIA_REG_DDRB, 0x1F);
    w(VIA_REG_ORB, 0x05);
    ASSERT_EQ_FMT((uint8_t)0x05, bus_.bank_config, "%02X");
    /* DDR=0 means pin floats (= 0 with pull-downs). */
    w(VIA_REG_DDRB, 0x10);  /* only PB4 driven */
    w(VIA_REG_ORB, 0x1F);
    ASSERT_EQ_FMT((uint8_t)0x10, bus_.bank_config, "%02X");
    PASS();
}

/* T1 timed (one-shot) IRQ count. */
TEST t1_timed_one_shot_fires_irq(void) {
    setup();
    w(VIA_REG_IER, 0x80 | VIA_INT_T1);  /* enable T1 */
    /* Latch low byte to 5, then writing high byte (=0) loads counter
     * with 0x0005 and starts T1. */
    w(VIA_REG_T1CL, 0x05);
    w(VIA_REG_T1CH, 0x00);
    ASSERT_EQ_FMT((uint8_t)0, bus_.irq, "%u");
    /* Tick down 6 times; T1 fires when it underflows from 0. */
    for (int i = 0; i < 6; i++) bus_step(&bus_);
    ASSERT_EQ_FMT((uint8_t)1, bus_.irq, "%u");
    /* IFR shows T1 set + bit 7 (any-IRQ). */
    uint8_t ifr = r(VIA_REG_IFR);
    ASSERT(ifr & VIA_INT_T1);
    ASSERT(ifr & 0x80);
    /* Reading T1CL clears T1 IFR. */
    (void)r(VIA_REG_T1CL);
    ASSERT_EQ_FMT((uint8_t)0, bus_.irq, "%u");
    /* T1 was one-shot, doesn't auto-rearm. Tick more, no new IRQ. */
    for (int i = 0; i < 100; i++) bus_step(&bus_);
    ASSERT_EQ_FMT((uint8_t)0, bus_.irq, "%u");
    PASS();
}

/* T1 continuous + PB7 squarewave: PB7 should toggle each T1 underflow. */
TEST t1_continuous_toggles_pb7(void) {
    setup();
    w(VIA_REG_DDRB, 0x80);  /* PB7 output */
    /* ACR_T1_CONT=$40, ACR_T1_OUT=$80 -> $C0 */
    w(VIA_REG_ACR, 0xC0);
    w(VIA_REG_T1CL, 0x02);
    w(VIA_REG_T1CH, 0x00);  /* counter = 2, starts */
    /* PB7 starts low. */
    ASSERT_EQ_FMT((uint8_t)0, via_6522_get_pb7(&vs), "%u");
    /* Tick 3 -> first underflow -> PB7 toggles to 1. */
    for (int i = 0; i < 3; i++) bus_step(&bus_);
    ASSERT_EQ_FMT((uint8_t)1, via_6522_get_pb7(&vs), "%u");
    /* Another 3 ticks -> toggles back to 0. */
    for (int i = 0; i < 3; i++) bus_step(&bus_);
    ASSERT_EQ_FMT((uint8_t)0, via_6522_get_pb7(&vs), "%u");
    PASS();
}

/* IFR write semantics: writing 1 to a bit clears it. */
TEST ifr_write_clears_bits(void) {
    setup();
    w(VIA_REG_IER, 0x80 | VIA_INT_T1 | VIA_INT_T2);
    w(VIA_REG_T1CL, 1); w(VIA_REG_T1CH, 0);
    w(VIA_REG_T2CL, 1); w(VIA_REG_T2CH, 0);
    /* Tick enough to fire both. */
    for (int i = 0; i < 4; i++) bus_step(&bus_);
    uint8_t ifr = r(VIA_REG_IFR);
    ASSERT(ifr & VIA_INT_T1);
    ASSERT(ifr & VIA_INT_T2);
    /* Clear T1 only. */
    w(VIA_REG_IFR, VIA_INT_T1);
    ifr = r(VIA_REG_IFR);
    ASSERT(!(ifr & VIA_INT_T1));
    ASSERT(ifr & VIA_INT_T2);
    PASS();
}

/* CB2 negative-edge in independent-interrupt mode arms the SR for an
 * 8-bit shift-in via T2 underflows. Drive CB2 low/then-clock 8 times
 * with known bit pattern -> SR matches the pattern. */
TEST cb2_neg_edge_then_sr_in_t2_byte(void) {
    setup();
    /* Configure: PCR_CB2_IND_NEG_E ($20), ACR=SR_IN_T2 ($04). */
    w(VIA_REG_PCR, VIA_PCR_CB2_IND_NEG_E);
    w(VIA_REG_ACR, VIA_ACR_SR_IN_T2);
    /* Set T2 latch to 1 cycle. */
    w(VIA_REG_T2CL, 0x01);
    w(VIA_REG_T2CH, 0x00);  /* arm T2 with $0001 */

    /* Pulse CB2 low to arm SR for 8 bits. CB2 high first (idle). */
    via_6522_set_cb2(&vs, &bus_, 1);
    via_6522_set_cb2(&vs, &bus_, 0);  /* falling edge */

    /* Drive a known pattern (1,0,1,0,1,0,1,0 -> $AA) into CB2 right
     * before each T2 underflow. Each underflow needs ~2 ticks. */
    static const uint8_t bits[8] = {1,0,1,0,1,0,1,0};
    for (int i = 0; i < 8; i++) {
        via_6522_set_cb2(&vs, &bus_, bits[i]);
        /* Tick T2 down to 0; underflow on next tick. */
        bus_step(&bus_);  /* counter 1 -> 0 */
        bus_step(&bus_);  /* underflow, shift bit i */
    }
    /* SR should now hold $AA. */
    uint8_t sr = r(VIA_REG_SR);
    ASSERT_EQ_FMT((uint8_t)0xAA, sr, "%02X");
    PASS();
}

SUITE(via_6522_suite) {
    RUN_TEST(init_state_is_zero);
    RUN_TEST(porta_input_output_direction);
    RUN_TEST(bank_config_follows_orb_and_ddrb);
    RUN_TEST(t1_timed_one_shot_fires_irq);
    RUN_TEST(t1_continuous_toggles_pb7);
    RUN_TEST(ifr_write_clears_bits);
    RUN_TEST(cb2_neg_edge_then_sr_in_t2_byte);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(via_6522_suite);
    GREATEST_MAIN_END();
}

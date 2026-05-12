/* Phase 5 tests for chips/clock_22v10: verify the PLD equations. */

#include <stdint.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/clock_22v10.h"

static void attach_clock(struct bus *b, struct chip *c, struct clock_22v10_state *s) {
    clock_22v10_init(c, s);
    bus_init(b);
    bus_add_chip(b, c);
}

/* Free-running CKS toggles every OSC tick (= OSC/2). With ROMCS not
 * asserted (no ROM access), CK == CKS. */
TEST cks_runs_at_osc_over_2_no_rom(void) {
    struct chip c; struct clock_22v10_state s; struct bus b;
    attach_clock(&b, &c, &s);
    b.addr = 0x0100;  /* low address, neither ROM nor VIA */
    b.bank_config = 0x01;  /* bank 1 -- RAM mapped at $0000-$3FFF */
    b.rwb = 1;

    uint8_t cks_seq[8], ck_seq[8];
    for (int i = 0; i < 8; i++) {
        bus_step(&b);
        cks_seq[i] = b.cks;
        ck_seq[i] = b.ck;
    }
    /* Starting from cks=0,ck=0: tick 1 -> cks=1,ck=0; tick 2 -> cks=0,
     * ck=0. In the no-rom case the PLD equation makes CK == CKS one
     * tick later. Per INVESTIGATION-wendy2c.md: CKS toggles each
     * tick, CK == CKS. */
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ_FMT(cks_seq[i], ck_seq[i], "%u");
    }
    /* CKS pattern: 1,0,1,0,1,0,1,0 starting from 0. */
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ_FMT((uint8_t)((i % 2 == 0) ? 1 : 0), cks_seq[i], "%u");
    }
    PASS();
}

/* With ROMCS asserted, CK runs at half the speed of CKS. PC at $8000
 * with bank-config 0 maps to the ROM region per the PLD ROMCS equation. */
TEST ck_runs_at_cks_over_2_when_rom(void) {
    struct chip c; struct clock_22v10_state s; struct bus b;
    attach_clock(&b, &c, &s);
    b.addr = 0x8000;
    b.bank_config = 0x00;  /* bank 0: ROM at $8000+ */
    b.rwb = 1;

    /* Run 8 ticks; record cks/ck. */
    uint8_t cks_seq[8], ck_seq[8];
    for (int i = 0; i < 8; i++) {
        bus_step(&b);
        cks_seq[i] = b.cks;
        ck_seq[i] = b.ck;
    }
    /* Per INVESTIGATION-wendy2c.md (ROM case):
     *   tick 1: cks=1, ck=0
     *   tick 2: cks=0, ck=1
     *   tick 3: cks=1, ck=1
     *   tick 4: cks=0, ck=0
     *   ...repeats with period 4 */
    uint8_t expected_cks[8] = {1, 0, 1, 0, 1, 0, 1, 0};
    uint8_t expected_ck[8]  = {0, 1, 1, 0, 0, 1, 1, 0};
    for (int i = 0; i < 8; i++) {
        ASSERT_EQ_FMT(expected_cks[i], cks_seq[i], "%u");
        ASSERT_EQ_FMT(expected_ck[i], ck_seq[i], "%u");
    }
    /* ROMCS must be asserted throughout (addr is in ROM region). */
    ASSERT_EQ_FMT((uint8_t)1, b.romcs, "%u");
    PASS();
}

/* CS lines are mutually exclusive across a sample of addresses. */
TEST cs_lines_mutually_exclusive(void) {
    struct chip c; struct clock_22v10_state s; struct bus b;
    attach_clock(&b, &c, &s);
    /* Sample a few addresses, both bank configs. */
    struct sample { uint16_t addr; uint8_t cb; };
    struct sample samples[] = {
        {0x0000, 0x00},  /* low addr, bank 0 -- nothing selected */
        {0x8000, 0x00},  /* ROM */
        {0xC000, 0x00},  /* ROM */
        {0xF000, 0x00},  /* VIA */
        {0xF800, 0x00},  /* ROM (high-FFFF block) */
        {0x8000, 0x10},  /* C4=1, bank 16: RAM */
        {0xF000, 0x10},  /* VIA still selected */
        {0x0000, 0x01},  /* low, bank 1: RAM */
    };
    for (size_t i = 0; i < sizeof(samples)/sizeof(samples[0]); i++) {
        b.addr = samples[i].addr;
        b.bank_config = samples[i].cb;
        b.rwb = 1;
        bus_step(&b);
        int sum = b.romcs + b.ramcs + b.viacs;
        ASSERT(sum <= 1);  /* at most one CS asserted */
    }
    PASS();
}

/* R-bits truth table: spot-check a handful of (A11..A15, C0..C4) inputs
 * against hand-computed expected values from the PLD source. */
TEST r_bits_truth_table_samples(void) {
    struct chip c; struct clock_22v10_state s; struct bus b;
    attach_clock(&b, &c, &s);

    struct sample {
        uint16_t addr;
        uint8_t cb;
        uint8_t expected_r;  /* low 4 bits = R18 R17 R16 R15 */
        const char *desc;
    };
    struct sample samples[] = {
        /* Low addr, bank0: R15 high (first PLD line for R15), others
         * zero. Expected R15..R18 = 0001. */
        {0x0000, 0x00, 0b0001, "bank0 low"},
        /* High addr (A15=A14=1), bank 16 (C4=1, others 0): R15 = 1
         * via the A15*A14 line; R16=R17=R18=0 in C000-FFFF here.
         * Expected = 0001. */
        {0xC000, 0x10, 0b0001, "C000 bank16"},
        /* Low addr, bank 5 (binary 00101) means C2=1, C0=1.
         * R15 = (!a15)(!a14)(!c4)(c0) -> 1, R16 = (!a15)(!a14)(!c4)
         * c1 -> 0, R17 = (!a15)(!a14)(!c4)c2 -> 1, R18 = 0.
         * Expected R = 0101. */
        {0x0100, 0x05, 0b0101, "bank5 low"},
    };
    for (size_t i = 0; i < sizeof(samples)/sizeof(samples[0]); i++) {
        b.addr = samples[i].addr;
        b.bank_config = samples[i].cb;
        b.rwb = 1;
        bus_step(&b);
        ASSERT_EQm(samples[i].desc, samples[i].expected_r, b.r_bits);
    }
    PASS();
}

/* CK falling edge sets cpu_cycle_due. */
TEST falling_ck_signals_cpu_cycle(void) {
    struct chip c; struct clock_22v10_state s; struct bus b;
    attach_clock(&b, &c, &s);
    b.addr = 0x0100;  /* RAM region */
    b.bank_config = 0x01;
    b.rwb = 1;

    int cycles = 0;
    for (int i = 0; i < 8; i++) {
        b.cpu_cycle_due = 0;
        bus_step(&b);
        if (b.cpu_cycle_due) cycles++;
    }
    /* Under no-ROM, CK toggles every other tick; falling edges happen at
     * half that rate. Over 8 ticks we expect 2 falling edges. */
    ASSERT(cycles >= 1 && cycles <= 4);
    PASS();
}

SUITE(clock_22v10_suite) {
    RUN_TEST(cks_runs_at_osc_over_2_no_rom);
    RUN_TEST(ck_runs_at_cks_over_2_when_rom);
    RUN_TEST(cs_lines_mutually_exclusive);
    RUN_TEST(r_bits_truth_table_samples);
    RUN_TEST(falling_ck_signals_cpu_cycle);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(clock_22v10_suite);
    GREATEST_MAIN_END();
}

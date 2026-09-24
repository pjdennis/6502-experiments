/* Independent, line-by-line transcription of 22V10-wendy2c.pld for
 * comparison with the existing clock_22v10.c implementation.
 *
 * The intent is to defend against subtle bugs in the existing
 * transcription: this file is written by reading the .pld source
 * end-to-end, one product term per C line, with the original PLD
 * comment preserved alongside each term. Then we exhaustively compare
 * compute_r_bits / compute_romcs / compute_viacs / compute_ramcs from
 * the emulator against the transcription for every (address, config)
 * pair the wendy2c validation program touches, and report any
 * disagreement.
 *
 * Run this test to either:
 *   (a) confirm clock_22v10.c is faithful to the .pld source, OR
 *   (b) flag the exact (address, config) where they diverge.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/clock_22v10.h"

/* ===== Literal 1:1 transcription of 22V10-wendy2c.pld ===== */

/* PLD inputs: A15..A11 (address bits), C4..C0 (bank-config bits).
 * Each function returns 0/1. Logic follows the .pld source line for
 * line; OR each product term into the output. */

static int pld_romcs(int a15, int a14, int a13, int a12, int a11,
                     int c4, int c3, int c2, int c1, int c0) {
    int n_a14 = !a14, n_a13 = !a13, n_a12 = !a12;
    int n_c4 = !c4, n_c3 = !c3, n_c2 = !c2, n_c1 = !c1, n_c0 = !c0;
    (void)n_c4;
    int x = 0;
    /* /C4 * /C3 * /C2 * /C1 * /C0 * A15 *  A14 *  A13 *  A12 * A11 */
    x |= n_c4 & n_c3 & n_c2 & n_c1 & n_c0 & a15 &  a14 &  a13 &  a12 & a11;
    /* /C4 * /C3 * /C2 * /C1 * /C0 * A15 * /A14 */
    x |= n_c4 & n_c3 & n_c2 & n_c1 & n_c0 & a15 & n_a14;
    /* /C4 * /C3 * /C2 * /C1 * /C0 * A15 *  A14 * /A13 */
    x |= n_c4 & n_c3 & n_c2 & n_c1 & n_c0 & a15 &  a14 & n_a13;
    /* /C4 * /C3 * /C2 * /C1 * /C0 * A15 *  A14 *  A13 * /A12 */
    x |= n_c4 & n_c3 & n_c2 & n_c1 & n_c0 & a15 &  a14 &  a13 & n_a12;
    /*  C4       * /C2 * /C1 * /C0 * A15 * /A14                     ; ROM with RAM at $f800 */
    x |= c4              & n_c2 & n_c1 & n_c0 & a15 & n_a14;
    /*  C4       * /C2 * /C1 * /C0 * A15 *  A14 * /A13              ; . */
    x |= c4              & n_c2 & n_c1 & n_c0 & a15 &  a14 & n_a13;
    /*  C4       * /C2 * /C1 * /C0 * A15 *  A14 * A13 * /A12        ; . */
    x |= c4              & n_c2 & n_c1 & n_c0 & a15 &  a14 &  a13 & n_a12;
    return x ? 1 : 0;
}

static int pld_viacs(int a15, int a14, int a13, int a12, int a11) {
    /* VIACS = A15 * A14 * A13 * A12 * /A11 */
    return (a15 & a14 & a13 & a12 & (!a11)) ? 1 : 0;
}

static int pld_ramcs(int a15, int a14, int a13, int a12, int a11,
                     int c4, int c3, int c2, int c1, int c0) {
    /* /RAMCS = (ROMCS terms) + (VIACS term). RAMCS is the positive form. */
    if (pld_romcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0)) return 0;
    if (pld_viacs(a15, a14, a13, a12, a11))                     return 0;
    return 1;
}

static int pld_r15(int a15, int a14, int a13, int a12, int a11,
                   int c4, int c3, int c2, int c1, int c0) {
    (void)a13; (void)a12; (void)a11;
    int n_a15 = !a15, n_a14 = !a14;
    int n_c4 = !c4, n_c3 = !c3, n_c2 = !c2, n_c1 = !c1, n_c0 = !c0;
    int x = 0;
    /* /A15 * /A14 * /C4 * /C3 * /C2 * /C1 * /C0 ; $0000..$3fff config $00000 */
    x |= n_a15 & n_a14 & n_c4 & n_c3 & n_c2 & n_c1 & n_c0;
    /* /A15 * /A14 * /C4 *  C0                   ; $0000..$3fff config $00001..$01111 */
    x |= n_a15 & n_a14 & n_c4 & c0;
    /* /A15 * /A14 *  C4 * /C3                   ; $0000..$3fff config $10000..$10111 */
    x |= n_a15 & n_a14 & c4 & n_c3;
    /*  A15 *  A14                               ; $8000..$ffff config $10000..$11111 */
    x |= a15 & a14;
    return x ? 1 : 0;
}

static int pld_r16(int a15, int a14, int a13, int a12, int a11,
                   int c4, int c3, int c2, int c1, int c0) {
    int n_a15 = !a15, n_a14 = !a14, n_a13 = !a13, n_a12 = !a12, n_a11 = !a11;
    int n_c4 = !c4;
    int x = 0;
    /* /A15 * /A14 * /C4 * C1 ; $0000..$3fff config $00001..$01111 */
    x |= n_a15 & n_a14 & n_c4 & c1;
    /* /A15 * /A14 *  C4 * C3 ; $0000..$3fff config $10000..$10111 */
    x |= n_a15 & n_a14 & c4 & c3;
    /*  A15 * /A14 *  C4 * C0 ; $8000..$ffff config $10000..$11111 */
    x |= a15 & n_a14 & c4 & c0;
    /*  A15 * /A13 *  C4 * C0 */
    x |= a15 & n_a13 & c4 & c0;
    /*  A15 * /A12 *  C4 * C0 */
    x |= a15 & n_a12 & c4 & c0;
    /*  A15 * /A11 *  C4 * C0 */
    x |= a15 & n_a11 & c4 & c0;
    return x ? 1 : 0;
}

static int pld_r17(int a15, int a14, int a13, int a12, int a11,
                   int c4, int c3, int c2, int c1, int c0) {
    int n_a15 = !a15, n_a14 = !a14, n_a13 = !a13, n_a12 = !a12, n_a11 = !a11;
    int n_c4 = !c4;
    (void)c3; (void)c0;
    int x = 0;
    /* /A15 * /A14 * /C4 * C2 ; $0000..$3fff config $00001..$01111 */
    x |= n_a15 & n_a14 & n_c4 & c2;
    /*  A15 * /A14 *  C4 * C1 ; $8000..$ffff config $10000..$11111 */
    x |= a15 & n_a14 & c4 & c1;
    /*  A15 * /A13 *  C4 * C1 */
    x |= a15 & n_a13 & c4 & c1;
    /*  A15 * /A12 *  C4 * C1 */
    x |= a15 & n_a12 & c4 & c1;
    /*  A15 * /A11 *  C4 * C1 */
    x |= a15 & n_a11 & c4 & c1;
    return x ? 1 : 0;
}

static int pld_r18(int a15, int a14, int a13, int a12, int a11,
                   int c4, int c3, int c2, int c1, int c0) {
    int n_a15 = !a15, n_a14 = !a14, n_a13 = !a13, n_a12 = !a12, n_a11 = !a11;
    int n_c4 = !c4;
    (void)c1; (void)c0;
    int x = 0;
    /* /A15 * /A14 * /C4 * C3 ; $0000..$3fff config $00001..$01111 */
    x |= n_a15 & n_a14 & n_c4 & c3;
    /*  A15 * /A14 *  C4 * C2 ; $8000..$ffff config $10000..$11111 */
    x |= a15 & n_a14 & c4 & c2;
    /*  A15 * /A13 *  C4 * C2 */
    x |= a15 & n_a13 & c4 & c2;
    /*  A15 * /A12 *  C4 * C2 */
    x |= a15 & n_a12 & c4 & c2;
    /*  A15 * /A11 *  C4 * C2 */
    x |= a15 & n_a11 & c4 & c2;
    return x ? 1 : 0;
}

/* ===== Probe via the live emulator chip ===== */

static struct bus bus_;
static struct chip clk_ch;
static struct clock_22v10_state clk_state;

static void emu_set(uint16_t addr, uint8_t cfg) {
    bus_.addr = addr;
    bus_.bank_config = cfg & 0x1F;
    clock_22v10_refresh_combinational(&bus_);
}

/* ===== The audit ===== */

TEST literal_matches_clock_22v10_for_all_inputs(void) {
    bus_init(&bus_);
    clock_22v10_init(&clk_ch, &clk_state);
    bus_add_chip(&bus_, &clk_ch);

    /* The PLD only looks at A11..A15, so it's sufficient to sweep
     * those 5 bits times the 5 config bits = 1024 combinations. We
     * encode the address bits at fixed lower positions so the
     * emulator sees the exact same a15..a11 pattern as the PLD code
     * computes from. */
    int divergences = 0;
    for (int abits = 0; abits < 32; abits++) {
        int a15 = (abits >> 4) & 1;
        int a14 = (abits >> 3) & 1;
        int a13 = (abits >> 2) & 1;
        int a12 = (abits >> 1) & 1;
        int a11 = (abits >> 0) & 1;
        uint16_t addr = (uint16_t)((a15 << 15) | (a14 << 14) | (a13 << 13) |
                                   (a12 << 12) | (a11 << 11));
        for (int cfg = 0; cfg < 32; cfg++) {
            int c4 = (cfg >> 4) & 1;
            int c3 = (cfg >> 3) & 1;
            int c2 = (cfg >> 2) & 1;
            int c1 = (cfg >> 1) & 1;
            int c0 = (cfg >> 0) & 1;

            emu_set(addr, (uint8_t)cfg);

            int want_romcs = pld_romcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_viacs = pld_viacs(a15, a14, a13, a12, a11);
            int want_ramcs = pld_ramcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_r15   = pld_r15(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_r16   = pld_r16(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_r17   = pld_r17(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_r18   = pld_r18(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
            int want_rbits = (want_r18 << 3) | (want_r17 << 2) | (want_r16 << 1) | want_r15;

            if ((int)bus_.romcs  != want_romcs ||
                (int)bus_.viacs  != want_viacs ||
                (int)bus_.ramcs  != want_ramcs ||
                (int)bus_.r_bits != want_rbits) {
                if (divergences < 5) {
                    fprintf(stderr,
                        "diverge: addr=$%04X cfg=$%02X | "
                        "emu romcs=%u viacs=%u ramcs=%u rbits=%X | "
                        "pld romcs=%d viacs=%d ramcs=%d rbits=%X\n",
                        addr, cfg,
                        bus_.romcs, bus_.viacs, bus_.ramcs, bus_.r_bits,
                        want_romcs, want_viacs, want_ramcs, want_rbits);
                }
                divergences++;
            }
        }
    }
    ASSERT_EQ_FMT(0, divergences, "%d");
    PASS();
}

/* Spot-check the specific physical-address pairings the wendy2c
 * verification_wendy2c.s `test_all` writes -- so we can see directly
 * whether the alias pairs that the test relies on being distinct ARE
 * distinct or not. Printed for human inspection; doesn't assert. */
TEST print_test_all_physical_map(void) {
    bus_init(&bus_);
    clock_22v10_init(&clk_ch, &clk_state);
    bus_add_chip(&bus_, &clk_ch);

    fprintf(stderr, "verification_wendy2c test_all sequence:\n");
    for (int K = 1; K <= 15; K++) {
        emu_set(0x2000, (uint8_t)K);
        uint32_t pa = ((uint32_t)bus_.r_bits << 15) | (0x2000 & 0x7FFF);
        fprintf(stderr, "  $2000 cfg=%%%c%c%c%c%c rbits=%X -> phys $%05X "
                        "(lower bank %d val %d)\n",
                ((K>>4)&1)?'1':'0', ((K>>3)&1)?'1':'0', ((K>>2)&1)?'1':'0',
                ((K>>1)&1)?'1':'0', (K&1)?'1':'0',
                bus_.r_bits, pa, K, K);
    }
    for (int J = 1; J <= 7; J++) {
        int cfg = 0x10 | J;  /* %1000_J */
        emu_set(0xA000, (uint8_t)cfg);
        uint32_t pa = ((uint32_t)bus_.r_bits << 15) | (0xA000 & 0x7FFF);
        fprintf(stderr, "  $A000 cfg=%%%c%c%c%c%c rbits=%X -> phys $%05X "
                        "(upper bank %d L val %d)\n",
                ((cfg>>4)&1)?'1':'0', ((cfg>>3)&1)?'1':'0',
                ((cfg>>2)&1)?'1':'0', ((cfg>>1)&1)?'1':'0',
                (cfg&1)?'1':'0',
                bus_.r_bits, pa, J + 1, J + 17);
    }
    PASS();
}

SUITE(pld_literal_suite) {
    RUN_TEST(literal_matches_clock_22v10_for_all_inputs);
    RUN_TEST(print_test_all_physical_map);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(pld_literal_suite);
    GREATEST_MAIN_END();
}

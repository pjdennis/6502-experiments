#include "clock_22v10.h"

#include <stddef.h>

/* All comments below use "(!X)" for NOT-X and "*" for AND, to avoid
 * stray comment-terminator sequences. The actual PLD source uses the
 * traditional "/X" for NOT-X. */

/* compute_romcs (positive logic; 1 = ROM selected). From the PLD:
 *   ROMCS = (!c4)(!c3)(!c2)(!c1)(!c0) * a15*a14*a13*a12*a11
 *         + (!c4)(!c3)(!c2)(!c1)(!c0) * a15*(!a14)
 *         + (!c4)(!c3)(!c2)(!c1)(!c0) * a15*a14*(!a13)
 *         + (!c4)(!c3)(!c2)(!c1)(!c0) * a15*a14*a13*(!a12)
 *         +   c4 *(!c2)(!c1)(!c0) * a15*(!a14)
 *         +   c4 *(!c2)(!c1)(!c0) * a15*a14*(!a13)
 *         +   c4 *(!c2)(!c1)(!c0) * a15*a14*a13*(!a12)
 */
static uint8_t compute_romcs(uint8_t a15, uint8_t a14, uint8_t a13, uint8_t a12,
                             uint8_t a11, uint8_t c4, uint8_t c3, uint8_t c2,
                             uint8_t c1, uint8_t c0) {
    uint8_t bank0 = (!c4) & (!c3) & (!c2) & (!c1) & (!c0);
    uint8_t bank_c4_x000_to_x111 = c4 & (!c2) & (!c1) & (!c0);
    if (bank0) {
        if (a15 & a14 & a13 & a12 & a11) return 1;
        if (a15 & (!a14)) return 1;
        if (a15 & a14 & (!a13)) return 1;
        if (a15 & a14 & a13 & (!a12)) return 1;
    }
    if (bank_c4_x000_to_x111) {
        if (a15 & (!a14)) return 1;
        if (a15 & a14 & (!a13)) return 1;
        if (a15 & a14 & a13 & (!a12)) return 1;
    }
    return 0;
}

/* compute_viacs: a15 * a14 * a13 * a12 * (!a11)  --  $F000..$F7FF. */
static uint8_t compute_viacs(uint8_t a15, uint8_t a14, uint8_t a13, uint8_t a12,
                             uint8_t a11) {
    return (a15 & a14 & a13 & a12 & (!a11)) ? 1 : 0;
}

/* RAMCS positive-logic. The PLD writes the negated form
 * "/RAMCS = (all ROMCS terms) + (VIA term)"; equivalently RAM is
 * selected when none of those terms is true. */
static uint8_t compute_ramcs(uint8_t a15, uint8_t a14, uint8_t a13, uint8_t a12,
                             uint8_t a11, uint8_t c4, uint8_t c3, uint8_t c2,
                             uint8_t c1, uint8_t c0) {
    if (compute_romcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0)) return 0;
    if (compute_viacs(a15, a14, a13, a12, a11)) return 0;
    return 1;
}

/* R15..R18 high RAM address lines per PLD. */
static uint8_t compute_r_bits(uint8_t a15, uint8_t a14, uint8_t a13, uint8_t a12,
                              uint8_t a11, uint8_t c4, uint8_t c3, uint8_t c2,
                              uint8_t c1, uint8_t c0) {
    uint8_t r15 = 0, r16 = 0, r17 = 0, r18 = 0;

    if ((!a15) & (!a14) & (!c4) & (!c3) & (!c2) & (!c1) & (!c0)) r15 = 1;
    if ((!a15) & (!a14) & (!c4) & c0) r15 = 1;
    if ((!a15) & (!a14) & c4 & (!c3)) r15 = 1;
    if (a15 & a14) r15 = 1;

    if ((!a15) & (!a14) & (!c4) & c1) r16 = 1;
    if ((!a15) & (!a14) & c4 & c3) r16 = 1;
    if (a15 & (!a14) & c4 & c0) r16 = 1;
    if (a15 & (!a13) & c4 & c0) r16 = 1;
    if (a15 & (!a12) & c4 & c0) r16 = 1;
    if (a15 & (!a11) & c4 & c0) r16 = 1;

    if ((!a15) & (!a14) & (!c4) & c2) r17 = 1;
    if (a15 & (!a14) & c4 & c1) r17 = 1;
    if (a15 & (!a13) & c4 & c1) r17 = 1;
    if (a15 & (!a12) & c4 & c1) r17 = 1;
    if (a15 & (!a11) & c4 & c1) r17 = 1;

    if ((!a15) & (!a14) & (!c4) & c3) r18 = 1;
    if (a15 & (!a14) & c4 & c2) r18 = 1;
    if (a15 & (!a13) & c4 & c2) r18 = 1;
    if (a15 & (!a12) & c4 & c2) r18 = 1;
    if (a15 & (!a11) & c4 & c2) r18 = 1;

    return (uint8_t)((r18 << 3) | (r17 << 2) | (r16 << 1) | r15);
}

void clock_22v10_refresh_combinational(struct bus *bus) {
    uint16_t a = bus->addr;
    uint8_t a15 = (a >> 15) & 1;
    uint8_t a14 = (a >> 14) & 1;
    uint8_t a13 = (a >> 13) & 1;
    uint8_t a12 = (a >> 12) & 1;
    uint8_t a11 = (a >> 11) & 1;
    uint8_t cb = bus->bank_config;
    uint8_t c4 = (cb >> 4) & 1;
    uint8_t c3 = (cb >> 3) & 1;
    uint8_t c2 = (cb >> 2) & 1;
    uint8_t c1 = (cb >> 1) & 1;
    uint8_t c0 = cb & 1;

    bus->romcs  = compute_romcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
    bus->ramcs  = compute_ramcs(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
    bus->viacs  = compute_viacs(a15, a14, a13, a12, a11);
    bus->r_bits = compute_r_bits(a15, a14, a13, a12, a11, c4, c3, c2, c1, c0);
    bus->wr     = (bus->rwb ? 0 : 1) & bus->ck;
}

static void clock_22v10_tick(struct chip *self, struct bus *bus) {
    (void)self;

    /* Refresh combinational outputs from the current address/RWB/bank. */
    clock_22v10_refresh_combinational(bus);

    /* Registered: cks_next = NOT cks_prev. */
    uint8_t prev_cks = bus->cks;
    uint8_t prev_ck = bus->ck;
    uint8_t new_cks = prev_cks ? 0 : 1;

    /* Registered ck_next = ck_prev AND NOT cks_prev
     *               PLUS  NOT ck_prev AND cks_prev
     *               PLUS  NOT romcs AND NOT ck_prev. */
    uint8_t new_ck = 0;
    if (prev_ck && !prev_cks) new_ck = 1;
    if (!prev_ck && prev_cks) new_ck = 1;
    if (!bus->romcs && !prev_ck) new_ck = 1;

    if (prev_ck && !new_ck) bus->cpu_cycle_due = 1;

    bus->cks = new_cks;
    bus->ck  = new_ck;
    /* WR depends on new CK; recompute. */
    bus->wr  = (bus->rwb ? 0 : 1) & new_ck;
}

static void clock_22v10_reset(struct chip *self) {
    (void)self;
}

void clock_22v10_init(struct chip *chip, struct clock_22v10_state *state) {
    static const struct chip_ops ops = {
        .tick  = clock_22v10_tick,
        .read  = NULL,
        .write = NULL,
        .reset = clock_22v10_reset,
    };
    state->dummy = 0;
    chip->ops = &ops;
    chip->name = "clock_22v10";
    chip->state = state;
}

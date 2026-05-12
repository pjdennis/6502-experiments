#ifndef EMULATOR_CHIPS_CLOCK_22V10_H
#define EMULATOR_CHIPS_CLOCK_22V10_H

#include <stdint.h>
#include "../bus.h"

/* 22V10-wendy2c PLD model. Implements the equations from
 * 22V10-wendy2c.pld literally. Registered: CKS, CK. Combinational:
 * WR, ROMCS, RAMCS, VIACS, R15..R18. See clock_22v10.c for the
 * equations themselves.
 *
 * Each tick(bus*):
 *   1. Read inputs from bus (addr bits A11..A15, rwb, bank_config).
 *   2. Compute combinational outputs (ROMCS, RAMCS, VIACS, R-bits)
 *      from those inputs.
 *   3. Compute new registered CKS = NOT(prev CKS).
 *   4. Compute new registered CK from the PLD sum-of-products using
 *      prev CKS, prev CK, current ROMCS.
 *   5. If CK falls (prev=1 then new=0), set bus->cpu_cycle_due = 1.
 *
 * No chip-private state -- prev CKS/CK live on the bus. */

struct clock_22v10_state {
    int dummy;  /* reserved for future use */
};

void clock_22v10_init(struct chip *chip, struct clock_22v10_state *state);

#endif

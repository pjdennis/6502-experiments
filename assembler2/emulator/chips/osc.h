#ifndef EMULATOR_CHIPS_OSC_H
#define EMULATOR_CHIPS_OSC_H

#include <stdint.h>

#include "../bus.h"

/* OSC chip. Holds the crystal frequency (used later by the audio sink
 * to set sample-rate decimation, and informational for diagnostics).
 * Its tick() advances bus->osc_ticks; bus_step() does the same in the
 * absence of an OSC, so having both attached counts only once -- the
 * OSC's tick() runs before bus_step's bump in the current
 * scaffolding. (Phase 5 / clock_22v10 takes over scheduling.) */
struct osc_state {
    uint64_t frequency_hz;
};

void osc_init(struct chip *chip, struct osc_state *state, uint64_t frequency_hz);

#endif

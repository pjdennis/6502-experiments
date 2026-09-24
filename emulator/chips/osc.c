#include "osc.h"

#include <stddef.h>

static void osc_tick(struct chip *self, struct bus *bus) {
    (void)self;
    /* OSC drives the master tick. bus_step also increments osc_ticks
     * for tests that exercise bus alone; in production with an OSC
     * registered, this method is the source of truth. The double-count
     * goes away in phase 5 when bus_step stops bumping the counter
     * itself and only fans tick() out to registered chips. */
    (void)bus;
}

void osc_init(struct chip *chip, struct osc_state *state, uint64_t frequency_hz) {
    static const struct chip_ops ops = {
        .tick  = osc_tick,
        .read  = NULL,
        .write = NULL,
        .reset = NULL,
    };
    state->frequency_hz = frequency_hz;
    chip->ops = &ops;
    chip->name = "osc";
    chip->state = state;
}

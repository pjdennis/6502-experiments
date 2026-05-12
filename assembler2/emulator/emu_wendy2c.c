#include "emu_wendy2c.h"

#include "bus.h"
#include "cpu_core.h"

int emu_run_wendy2c(const struct emu_opts *opts) {
    /* Pick the CPU variant from the parsed options (--cpu defaults to
     * 65c02 for --machine wendy2c, validated in parse_args). */
    cpu_variant = opts->cpu_variant_opt;

    /* Construct an empty bus. Future phases (5..9) will attach the
     * clock, ROM, RAM, VIA, and the CPU itself. */
    struct bus b;
    bus_init(&b);

    /* Spin a small OSC tick cap. With no chips attached this loop
     * does nothing useful; the cap lets the phase 4 smoke test exit
     * quickly. Phase 8 replaces this with the real CK-driven loop. */
    const uint64_t cap = 1024;
    while (b.osc_ticks < cap) {
        bus_step(&b);
    }

    return 0;
}

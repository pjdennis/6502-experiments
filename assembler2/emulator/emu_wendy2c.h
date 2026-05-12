#ifndef EMULATOR_EMU_WENDY2C_H
#define EMULATOR_EMU_WENDY2C_H

#include "cli.h"

/* Run the wendy2c machine model. Phase 4b: only constructs an empty
 * bus, sets cpu_variant, and spins a small OSC tick loop. Real chip
 * wiring (clock_22v10, ROM, RAM, VIA, CPU-on-bus, etc.) lands in
 * phases 5..9. Returns 0 on normal exit, non-zero on error. */
int emu_run_wendy2c(const struct emu_opts *opts);

#endif

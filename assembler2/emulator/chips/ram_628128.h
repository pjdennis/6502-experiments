#ifndef EMULATOR_CHIPS_RAM_628128_H
#define EMULATOR_CHIPS_RAM_628128_H

#include <stdint.h>
#include "../bus.h"

/* RAM chip on the wendy2c. The investigation note pinned the chip to
 * a 128 KiB 628128 (A0..A16, 17 address pins), but the PLD drives
 * four high address lines R15..R18 unconditionally -- so we emulate
 * the full 512 KiB physical address space (sufficient as a superset
 * of either 128 KiB or 512 KiB physical chips). The breadboard
 * inspection has not yet confirmed which is installed; banks beyond
 * what 128 KiB supports may alias on real hardware.
 *
 * Physical address = (r_bits & 0x0F) << 15 | (A14..A0).
 *
 * Reads claim when bus->ramcs && bus->rwb. Writes claim when
 * bus->ramcs && !bus->rwb. The PLD's RAMCS already excludes the
 * VIA window ($F000..$F7FF) and ROM region, so no additional address
 * filtering is needed here. */

#define RAM_628128_SIZE 0x80000  /* 512 KiB superset */

struct ram_628128_state {
    uint8_t contents[RAM_628128_SIZE];
};

void ram_628128_init(struct chip *chip, struct ram_628128_state *state);

#endif

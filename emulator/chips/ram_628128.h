#ifndef EMULATOR_CHIPS_RAM_628128_H
#define EMULATOR_CHIPS_RAM_628128_H

#include <stdint.h>
#include "../bus.h"

/* RAM chip on the wendy2c: a 512 KiB SRAM (the module keeps its
 * historical 628128 name). The PLD's R15..R18 all drive RAM address
 * lines, so every bank it selects is physically distinct.
 *
 * Physical address = (r_bits & 0x0F) << 15 | CPU A15 << 14 | (A13..A0).
 * CPU A14 goes only to the PLD; see physical_addr() in ram_628128.c.
 *
 * Reads claim when bus->ramcs && bus->rwb. Writes claim when
 * bus->ramcs && !bus->rwb. The PLD's RAMCS already excludes the
 * VIA window ($F000..$F7FF) and ROM region, so no additional address
 * filtering is needed here. */

#define RAM_628128_SIZE 0x80000  /* 512 KiB */

struct ram_628128_state {
    uint8_t contents[RAM_628128_SIZE];
};

void ram_628128_init(struct chip *chip, struct ram_628128_state *state);

#endif

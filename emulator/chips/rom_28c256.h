#ifndef EMULATOR_CHIPS_ROM_28C256_H
#define EMULATOR_CHIPS_ROM_28C256_H

#include <stdint.h>
#include <stddef.h>
#include "../bus.h"

/* 28C256 32 KiB EEPROM. Loaded from a file at init; writes ignored
 * (the 28C256 write protocol is not modeled -- on the real board the
 * EEPROM is programmed offline by a flasher). Reads claim when the
 * clock_22v10 asserts ROMCS. */

#define ROM_28C256_SIZE 0x8000

struct rom_28c256_state {
    uint8_t contents[ROM_28C256_SIZE];
};

void rom_28c256_init(struct chip *chip, struct rom_28c256_state *state);

/* Load a binary file into the ROM image. Returns 0 on success,
 * non-zero if the file is missing or unreadable. Up to ROM_28C256_SIZE
 * bytes are loaded; if the file is shorter, the remainder is zero. */
int rom_28c256_load(struct rom_28c256_state *state, const char *path);

#endif

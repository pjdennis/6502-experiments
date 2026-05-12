#ifndef EMULATOR_BUS_H
#define EMULATOR_BUS_H

#include <stdint.h>
#include <stdbool.h>

struct bus;
struct chip;

/* Each chip implements a subset of these methods. NULL means "not
 * implemented; bus skips this method for this chip." */
struct chip_ops {
    void (*tick)(struct chip *self, struct bus *bus);
    bool (*read)(struct chip *self, struct bus *bus,
                 uint16_t addr, uint8_t *data_out);
    bool (*write)(struct chip *self, struct bus *bus,
                  uint16_t addr, uint8_t data);
    void (*reset)(struct chip *self);
};

struct chip {
    const struct chip_ops *ops;
    const char *name;
    void *state;
};

#define BUS_MAX_CHIPS 16

/* Bus lines. Positive-logic mirroring the PLD pin labels (so e.g.
 * `romcs = 1` means "ROM is selected"). */
struct bus {
    uint16_t addr;
    uint8_t data;
    uint8_t rwb;       /* 1 = read, 0 = write */
    uint8_t romcs;
    uint8_t ramcs;
    uint8_t viacs;
    uint8_t wr;        /* asserted = write strobe */
    uint8_t irq;
    uint8_t nmi;
    uint8_t res;
    uint64_t osc_ticks;
    struct chip *chips[BUS_MAX_CHIPS];
    int chip_count;
};

void bus_init(struct bus *b);

/* Register a chip with the bus. Returns 0 on success, -1 if full. */
int bus_add_chip(struct bus *b, struct chip *chip);

/* Broadcast reset() to every chip that implements it. */
void bus_reset(struct bus *b);

/* Bus read/write. Walks chips in registration order and the first
 * chip whose read()/write() returns true claims the transaction.
 * Returns 1 if claimed, 0 if unclaimed (caller is responsible for the
 * "open bus" value in the unclaimed case). */
int bus_read(struct bus *b, uint16_t addr, uint8_t *data_out);
int bus_write(struct bus *b, uint16_t addr, uint8_t data);

/* One OSC tick. Stub for phase 2: only increments osc_ticks. Real
 * tick scheduling (combinational vs registered outputs) lands in
 * phase 5 (clock_22v10). */
void bus_step(struct bus *b);

#endif

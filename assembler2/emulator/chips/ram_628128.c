#include "ram_628128.h"

#include <string.h>

static uint32_t physical_addr(struct bus *bus, uint16_t addr) {
    /* High 4 bits from r_bits, low 15 from address. */
    return ((uint32_t)(bus->r_bits & 0x0F) << 15) | (addr & 0x7FFF);
}

static bool ram_628128_read(struct chip *self, struct bus *bus,
                            uint16_t addr, uint8_t *data_out) {
    if (!bus->ramcs || !bus->rwb) return false;
    struct ram_628128_state *s = (struct ram_628128_state *)self->state;
    uint32_t pa = physical_addr(bus, addr);
    *data_out = s->contents[pa];
    return true;
}

static bool ram_628128_write(struct chip *self, struct bus *bus,
                             uint16_t addr, uint8_t data) {
    if (!bus->ramcs || bus->rwb) return false;
    struct ram_628128_state *s = (struct ram_628128_state *)self->state;
    uint32_t pa = physical_addr(bus, addr);
    s->contents[pa] = data;
    return true;
}

static void ram_628128_reset(struct chip *self) {
    (void)self;
}

void ram_628128_init(struct chip *chip, struct ram_628128_state *state) {
    static const struct chip_ops ops = {
        .tick  = NULL,
        .read  = ram_628128_read,
        .write = ram_628128_write,
        .reset = ram_628128_reset,
    };
    memset(state->contents, 0, RAM_628128_SIZE);
    chip->ops = &ops;
    chip->name = "ram_628128";
    chip->state = state;
}

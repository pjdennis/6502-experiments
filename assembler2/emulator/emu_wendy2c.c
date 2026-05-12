#include "emu_wendy2c.h"

#include <stdio.h>
#include <string.h>

#include "bus.h"
#include "cpu_core.h"
#include "chips/clock_22v10.h"
#include "chips/rom_28c256.h"
#include "chips/ram_628128.h"
#include "chips/via_6522.h"
#include "chips/cpu_65c02.h"

/* Module-scope bus pointer used by the cpu_external_read/write hooks
 * the CPU dispatch reaches into. There's at most one wendy2c run
 * active per process. */
static struct bus *active_bus = NULL;

static uint8_t wendy2c_cpu_read(uint16_t addr) {
    if (!active_bus) return 0xFF;
    /* Reflect the address on the bus and refresh chip-select lines so
     * ROM/RAM/VIA see the right CS for THIS access. (CKS/CK are not
     * touched -- those advance on bus_step, not on per-access reads.) */
    active_bus->addr = addr;
    active_bus->rwb = 1;
    clock_22v10_refresh_combinational(active_bus);
    uint8_t data = 0xFF;
    bus_read(active_bus, addr, &data);
    return data;
}

static void wendy2c_cpu_write(uint16_t addr, uint8_t data) {
    if (!active_bus) return;
    active_bus->addr = addr;
    active_bus->rwb = 0;
    clock_22v10_refresh_combinational(active_bus);
    bus_write(active_bus, addr, data);
}

int emu_run_wendy2c(const struct emu_opts *opts) {
    cpu_variant = opts->cpu_variant_opt;

    static struct clock_22v10_state clk_state;
    static struct rom_28c256_state  rom_state;
    static struct ram_628128_state  ram_state;
    static struct via_6522_state    via_state;
    static struct cpu_65c02_state   cpu_state;
    struct chip clk_chip, rom_chip, ram_chip, via_chip, cpu_chip;

    clock_22v10_init(&clk_chip, &clk_state);
    rom_28c256_init(&rom_chip, &rom_state);
    ram_628128_init(&ram_chip, &ram_state);
    via_6522_init  (&via_chip, &via_state);
    cpu_65c02_init (&cpu_chip, &cpu_state);

    /* Load ROM image. Falls back to code_filename if --rom is omitted. */
    const char *rom_path = opts->rom_filename ? opts->rom_filename
                                              : opts->code_filename;
    if (rom_path) {
        if (rom_28c256_load(&rom_state, rom_path) != 0) {
            fprintf(stderr, "wendy2c: could not load ROM image: %s\n", rom_path);
            return 1;
        }
    } else {
        fprintf(stderr, "wendy2c: no ROM image (use --rom PATH or positional argv)\n");
        return 1;
    }

    struct bus b;
    bus_init(&b);
    /* The clock must be the FIRST chip so wendy2c_cpu_read/write can
     * tick it before bus_read/bus_write fans out to ROM/RAM. */
    bus_add_chip(&b, &clk_chip);
    bus_add_chip(&b, &rom_chip);
    bus_add_chip(&b, &ram_chip);
    bus_add_chip(&b, &via_chip);
    bus_add_chip(&b, &cpu_chip);

    active_bus = &b;
    cpu_external_read  = wendy2c_cpu_read;
    cpu_external_write = wendy2c_cpu_write;

    /* Pulse RES so the CPU latches its reset vector through the bus
     * (i.e. through the ROM at $FFFC/$FFFD). */
    b.res = 1;
    for (int i = 0; i < 8; i++) bus_step(&b);
    b.res = 0;

    /* Run until STP halts the CPU or we hit a hard cap. The cap also
     * limits run-away tests; the wendy2c sample programs that use STP
     * (e.g. wendy2c_eeprom_show.s) terminate well within it. */
    const uint64_t cap = 200000000ULL;
    while (b.osc_ticks < cap) {
        bus_step(&b);
        if (cpu_stp_pending()) break;
    }

    int halted_on_stp = cpu_stp_pending();
    fprintf(stderr,
        "wendy2c: exit  osc_ticks=%llu  cpu_cycles=%llu  pc=$%04X  %s\n",
        (unsigned long long)b.osc_ticks,
        (unsigned long long)clockticks6502,
        pc,
        halted_on_stp ? "(STP)" : "(cycle cap)");

    /* Tear down the external hooks before returning so other code (e.g.
     * the test harness or a subsequent run) doesn't dangle on a dead
     * bus pointer. */
    cpu_external_read  = NULL;
    cpu_external_write = NULL;
    active_bus = NULL;

    return halted_on_stp ? 0 : 1;
}

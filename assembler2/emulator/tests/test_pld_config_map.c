/* PLD config-map tests: for every 5-bit bank-config value (0..31), assert
 * the canonical chip-select and R-bits the 22V10 must produce at a handful
 * of representative CPU addresses. Effectively a truth-table snapshot of
 * the breadboard's address map.
 *
 * This is the "design-intent" test: it captures what each config SHOULD
 * mean from the on-target software's point of view. Currently cfg=$18
 * (the second ROM-upper variant) fails -- the .pld treats it as
 * "ROM upper, RAM top" same as cfg=$10, but the design intends cfg=$18
 * to be the C3=1 / lower-bank-2 analogue of cfg=$01 (lower=bank 2,
 * upper=RAM banks 0/1). See PLD_BANK_ALIASING_NOTES.md for the history.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/clock_22v10.h"

static struct clock_22v10_state clk_state;
static struct chip             clk_ch;
static struct bus              bus_;

static void emu_set(uint16_t addr, uint8_t cfg) {
    bus_.addr = addr;
    bus_.rwb  = 1;
    bus_.bank_config = cfg & 0x1F;
    clock_22v10_refresh_combinational(&bus_);
}

/* Compact description of what's expected at a single (cfg, addr).
 * `cs` is one of 'R' (ROM), 'M' (RAM), 'V' (VIA), '-' (open bus).
 * `r_bits` is meaningful only when cs == 'M'. */
struct expect {
    uint16_t addr;
    char     cs;
    uint8_t  r_bits;        /* expected r_bits when cs == 'M' */
    const char *what;       /* short label for failure messages */
};

/* Per-config expectations. Lengths vary because we sample different
 * addresses depending on what each config exposes. */
struct cfg_expect {
    uint8_t cfg;
    const char *summary;
    const struct expect *checks;
    int n;
};

#define EXPECT_RAM(addr, bank, what) { (addr), 'M', (bank), (what) }
#define EXPECT_ROM(addr, what)       { (addr), 'R', 0, (what) }
#define EXPECT_VIA(addr, what)       { (addr), 'V', 0, (what) }

/* Common per-config sample points. Lower $2000, fixed $6000, upper $a000,
 * upper $e000, VIA $f000, top $f800. */

/* cfg=$00 -- startup: ROM upper + top, RAM lower */
static const struct expect cfg00[] = {
    EXPECT_RAM(0x2000, 1, "$00 lower=bank 1"),
    EXPECT_RAM(0x6000, 0, "$00 fixed=bank 0"),
    EXPECT_ROM(0xA000,    "$00 upper L=ROM"),
    EXPECT_ROM(0xE000,    "$00 upper H=ROM"),
    EXPECT_VIA(0xF000,    "$00 VIA"),
    EXPECT_ROM(0xF800,    "$00 top=ROM"),
};

/* cfg=$10 -- ROM upper, RAM top, lower=bank 1 */
static const struct expect cfg10[] = {
    EXPECT_RAM(0x2000, 1, "$10 lower=bank 1"),
    EXPECT_RAM(0x6000, 0, "$10 fixed=bank 0"),
    EXPECT_ROM(0xA000,    "$10 upper L=ROM"),
    EXPECT_ROM(0xE000,    "$10 upper H=ROM"),
    EXPECT_VIA(0xF000,    "$10 VIA"),
    EXPECT_RAM(0xF800, 1, "$10 top=RAM bank 1"),
};

/* For all "lower-bank-only" configs cfg=$01..$0F we get:
 *   $2000 -> RAM bank cfg
 *   $6000 -> RAM bank 0 (fixed)
 *   $a000 -> RAM bank 0 (upper low half)
 *   $e000 -> RAM bank 1 (upper high half)
 *   $f000 -> VIA
 *   $f800 -> RAM bank 1
 * cfg=$01 is the canonical example. */
#define LOWER_BANK_EXPECT(NAME, CFG, LBANK) \
    static const struct expect NAME[] = { \
        EXPECT_RAM(0x2000, (LBANK), "lower bank " #LBANK), \
        EXPECT_RAM(0x6000, 0,       "fixed=bank 0"), \
        EXPECT_RAM(0xA000, 0,       "upper L=bank 0"), \
        EXPECT_RAM(0xE000, 1,       "upper H=bank 1"), \
        EXPECT_VIA(0xF000,          "VIA"), \
        EXPECT_RAM(0xF800, 1,       "top=bank 1"), \
    }

LOWER_BANK_EXPECT(cfg01, 0x01, 1);
LOWER_BANK_EXPECT(cfg02, 0x02, 2);
LOWER_BANK_EXPECT(cfg03, 0x03, 3);
LOWER_BANK_EXPECT(cfg04, 0x04, 4);
LOWER_BANK_EXPECT(cfg05, 0x05, 5);
LOWER_BANK_EXPECT(cfg06, 0x06, 6);
LOWER_BANK_EXPECT(cfg07, 0x07, 7);
LOWER_BANK_EXPECT(cfg08, 0x08, 8);
LOWER_BANK_EXPECT(cfg09, 0x09, 9);
LOWER_BANK_EXPECT(cfg0A, 0x0A, 10);
LOWER_BANK_EXPECT(cfg0B, 0x0B, 11);
LOWER_BANK_EXPECT(cfg0C, 0x0C, 12);
LOWER_BANK_EXPECT(cfg0D, 0x0D, 13);
LOWER_BANK_EXPECT(cfg0E, 0x0E, 14);
LOWER_BANK_EXPECT(cfg0F, 0x0F, 15);

/* Upper-bank configs with lower=bank 1 (C4=1, C3=0).
 * Selector C2 C1 C0 picks the upper bank pair:
 *   000 -> $10 = ROM upper, RAM top
 *   001 -> $11 = (b2, b3)
 *   010 -> $12 = (b4, b5)
 *   011 -> $13 = (b6, b7)
 *   100 -> $14 = (b8, b9)
 *   101 -> $15 = (b10, b11)
 *   110 -> $16 = (b12, b13)
 *   111 -> $17 = (b14, b15)
 */
#define UPPER_LB1_EXPECT(NAME, BL, BH) \
    static const struct expect NAME[] = { \
        EXPECT_RAM(0x2000, 1,    "lower=bank 1"), \
        EXPECT_RAM(0x6000, 0,    "fixed=bank 0"), \
        EXPECT_RAM(0xA000, (BL), "upper L"), \
        EXPECT_RAM(0xE000, (BH), "upper H"), \
        EXPECT_VIA(0xF000,       "VIA"), \
        EXPECT_RAM(0xF800, 1,    "top=bank 1"), \
    }
UPPER_LB1_EXPECT(cfg11,  2,  3);
UPPER_LB1_EXPECT(cfg12,  4,  5);
UPPER_LB1_EXPECT(cfg13,  6,  7);
UPPER_LB1_EXPECT(cfg14,  8,  9);
UPPER_LB1_EXPECT(cfg15, 10, 11);
UPPER_LB1_EXPECT(cfg16, 12, 13);
UPPER_LB1_EXPECT(cfg17, 14, 15);

/* Upper-bank configs with lower=bank 2 (C4=1, C3=1).
 * Same C2 C1 C0 selector layout. cfg=$18 selector 000 must give
 * RAM upper bank 0/1, NOT ROM. */
#define UPPER_LB2_EXPECT(NAME, BL, BH) \
    static const struct expect NAME[] = { \
        EXPECT_RAM(0x2000, 2,    "lower=bank 2"), \
        EXPECT_RAM(0x6000, 0,    "fixed=bank 0"), \
        EXPECT_RAM(0xA000, (BL), "upper L"), \
        EXPECT_RAM(0xE000, (BH), "upper H"), \
        EXPECT_VIA(0xF000,       "VIA"), \
        EXPECT_RAM(0xF800, 1,    "top=bank 1"), \
    }
UPPER_LB2_EXPECT(cfg18,  0,  1);   /* THE FIX: cfg=$18 must be RAM */
UPPER_LB2_EXPECT(cfg19,  2,  3);
UPPER_LB2_EXPECT(cfg1A,  4,  5);
UPPER_LB2_EXPECT(cfg1B,  6,  7);
UPPER_LB2_EXPECT(cfg1C,  8,  9);
UPPER_LB2_EXPECT(cfg1D, 10, 11);
UPPER_LB2_EXPECT(cfg1E, 12, 13);
UPPER_LB2_EXPECT(cfg1F, 14, 15);

#define C(name, sum)  { 0, sum, name, sizeof(name)/sizeof(name[0]) }
static struct cfg_expect ALL[] = {
    C(cfg00, "$00: startup -- ROM upper, ROM top"),
    C(cfg01, "$01: lower=bank 1, upper RAM bank 0/1"),
    C(cfg02, "$02: lower=bank 2"),
    C(cfg03, "$03: lower=bank 3"),
    C(cfg04, "$04: lower=bank 4"),
    C(cfg05, "$05: lower=bank 5"),
    C(cfg06, "$06: lower=bank 6"),
    C(cfg07, "$07: lower=bank 7"),
    C(cfg08, "$08: lower=bank 8"),
    C(cfg09, "$09: lower=bank 9"),
    C(cfg0A, "$0A: lower=bank 10"),
    C(cfg0B, "$0B: lower=bank 11"),
    C(cfg0C, "$0C: lower=bank 12"),
    C(cfg0D, "$0D: lower=bank 13"),
    C(cfg0E, "$0E: lower=bank 14"),
    C(cfg0F, "$0F: lower=bank 15"),
    C(cfg10, "$10: ROM upper + RAM top, lower bank 1"),
    C(cfg11, "$11: upper banks (2,3),  lower bank 1"),
    C(cfg12, "$12: upper banks (4,5),  lower bank 1"),
    C(cfg13, "$13: upper banks (6,7),  lower bank 1"),
    C(cfg14, "$14: upper banks (8,9),  lower bank 1"),
    C(cfg15, "$15: upper banks (10,11),lower bank 1"),
    C(cfg16, "$16: upper banks (12,13),lower bank 1"),
    C(cfg17, "$17: upper banks (14,15),lower bank 1"),
    C(cfg18, "$18: upper banks (0,1),  lower bank 2  [post-fix]"),
    C(cfg19, "$19: upper banks (2,3),  lower bank 2"),
    C(cfg1A, "$1A: upper banks (4,5),  lower bank 2"),
    C(cfg1B, "$1B: upper banks (6,7),  lower bank 2"),
    C(cfg1C, "$1C: upper banks (8,9),  lower bank 2"),
    C(cfg1D, "$1D: upper banks (10,11),lower bank 2"),
    C(cfg1E, "$1E: upper banks (12,13),lower bank 2"),
    C(cfg1F, "$1F: upper banks (14,15),lower bank 2"),
};
#undef C

TEST all_32_configs_match_design(void) {
    bus_init(&bus_);
    clock_22v10_init(&clk_ch, &clk_state);
    bus_add_chip(&bus_, &clk_ch);

    int errors = 0;
    for (int i = 0; i < 32; i++) {
        ALL[i].cfg = (uint8_t)i;
        for (int k = 0; k < ALL[i].n; k++) {
            const struct expect *e = &ALL[i].checks[k];
            emu_set(e->addr, ALL[i].cfg);
            char got_cs = bus_.romcs ? 'R' : bus_.viacs ? 'V' : bus_.ramcs ? 'M' : '-';
            if (got_cs != e->cs) {
                fprintf(stderr, "cfg=$%02X addr=$%04X: expected cs=%c (%s), got cs=%c\n",
                        ALL[i].cfg, e->addr, e->cs, e->what, got_cs);
                errors++;
                continue;
            }
            if (e->cs == 'M' && bus_.r_bits != e->r_bits) {
                fprintf(stderr, "cfg=$%02X addr=$%04X: expected RAM bank %u (%s), got bank %u\n",
                        ALL[i].cfg, e->addr, e->r_bits, e->what, bus_.r_bits);
                errors++;
            }
        }
    }
    ASSERT_EQ_FMT(0, errors, "%d");
    PASS();
}

/* For every cfg, walk a set of CPU addresses that includes the
 * boundaries of every chip-select window ($0000, $3FFF, $4000, $7FFF,
 * $8000, $BFFF, $C000, $DFFF, $E000, $EFFF, $F000, $F7FF, $F800,
 * $FFFF) and check the invariant that EXACTLY ONE of romcs / ramcs /
 * viacs is asserted -- never zero (open bus would be unspecified at
 * boot), never two (would put two chips on the same bus and burn out
 * an output driver). */
TEST exactly_one_cs_at_every_boundary_for_all_configs(void) {
    bus_init(&bus_);
    clock_22v10_init(&clk_ch, &clk_state);
    bus_add_chip(&bus_, &clk_ch);

    /* Boundary addresses spanning every chip-select region transition. */
    static const uint16_t boundaries[] = {
        0x0000, 0x3FFF, 0x4000, 0x7FFF,
        0x8000, 0xBFFF, 0xC000, 0xDFFF,
        0xE000, 0xEFFF, 0xF000, 0xF7FF,
        0xF800, 0xFFFF,
    };
    int errors = 0;
    for (int cfg = 0; cfg < 32; cfg++) {
        for (size_t k = 0; k < sizeof(boundaries)/sizeof(boundaries[0]); k++) {
            emu_set(boundaries[k], (uint8_t)cfg);
            int n = (bus_.romcs ? 1 : 0) + (bus_.ramcs ? 1 : 0) + (bus_.viacs ? 1 : 0);
            if (n != 1) {
                fprintf(stderr, "cfg=$%02X addr=$%04X: %d chip-selects asserted "
                                "(romcs=%u ramcs=%u viacs=%u); expected exactly 1\n",
                        cfg, boundaries[k], n,
                        bus_.romcs, bus_.ramcs, bus_.viacs);
                errors++;
            }
        }
    }
    ASSERT_EQ_FMT(0, errors, "%d");
    PASS();
}

/* Spot-check the window boundaries explicitly per config: in cfg=$01
 * the lower window flips from RAM (bank 1) to RAM (bank 0, fixed)
 * across $3FFF -> $4000. In cfg=$10 the upper window flips from RAM
 * to ROM at $7FFF -> $8000 and back to RAM at $F7FF -> $F800. These
 * are the address bits the on-target code relies on, so an off-by-one
 * in the PLD would be caught here even if the all-32-configs table
 * test missed it. */
TEST window_transitions_in_canonical_configs(void) {
    bus_init(&bus_);
    clock_22v10_init(&clk_ch, &clk_state);
    bus_add_chip(&bus_, &clk_ch);

    /* cfg=$01: lower banked, upper RAM */
    emu_set(0x3FFF, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 1);  /* lower bank 1, last byte */
    emu_set(0x4000, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 0);  /* fixed, first byte */
    emu_set(0x7FFF, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 0);  /* fixed, last byte */
    emu_set(0x8000, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 0);  /* upper-L, first byte (bank 0) */
    emu_set(0xBFFF, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 0);  /* upper-L, last byte */
    emu_set(0xC000, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 1);  /* upper-H, first byte (bank 1) */
    emu_set(0xEFFF, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 1);  /* upper-H, last RAM byte */
    emu_set(0xF000, 0x01); ASSERT(bus_.viacs);                       /* VIA */
    emu_set(0xF7FF, 0x01); ASSERT(bus_.viacs);                       /* VIA, last byte */
    emu_set(0xF800, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 1);  /* top RAM */
    emu_set(0xFFFF, 0x01); ASSERT(bus_.ramcs && bus_.r_bits == 1);

    /* cfg=$10: ROM upper, RAM top */
    emu_set(0x8000, 0x10); ASSERT(bus_.romcs);                      /* ROM, first byte */
    emu_set(0xBFFF, 0x10); ASSERT(bus_.romcs);
    emu_set(0xC000, 0x10); ASSERT(bus_.romcs);
    emu_set(0xEFFF, 0x10); ASSERT(bus_.romcs);                      /* ROM, last byte */
    emu_set(0xF000, 0x10); ASSERT(bus_.viacs);
    emu_set(0xF7FF, 0x10); ASSERT(bus_.viacs);
    emu_set(0xF800, 0x10); ASSERT(bus_.ramcs && bus_.r_bits == 1);  /* top RAM (not ROM!) */

    /* cfg=$18: post-fix should be RAM upper bank 0/1, NOT ROM */
    emu_set(0x8000, 0x18); ASSERT(bus_.ramcs && bus_.r_bits == 0);
    emu_set(0xBFFF, 0x18); ASSERT(bus_.ramcs && bus_.r_bits == 0);
    emu_set(0xC000, 0x18); ASSERT(bus_.ramcs && bus_.r_bits == 1);
    emu_set(0xEFFF, 0x18); ASSERT(bus_.ramcs && bus_.r_bits == 1);
    emu_set(0xF000, 0x18); ASSERT(bus_.viacs);
    emu_set(0xF800, 0x18); ASSERT(bus_.ramcs && bus_.r_bits == 1);

    /* cfg=$00 startup: ROM at $8000-$EFFF AND $F800-$FFFF, VIA at $F000-$F7FF */
    emu_set(0x8000, 0x00); ASSERT(bus_.romcs);
    emu_set(0xEFFF, 0x00); ASSERT(bus_.romcs);
    emu_set(0xF000, 0x00); ASSERT(bus_.viacs);
    emu_set(0xF7FF, 0x00); ASSERT(bus_.viacs);
    emu_set(0xF800, 0x00); ASSERT(bus_.romcs);                      /* startup top = ROM */
    emu_set(0xFFFF, 0x00); ASSERT(bus_.romcs);
    PASS();
}

SUITE(pld_config_map_suite) {
    RUN_TEST(all_32_configs_match_design);
    RUN_TEST(exactly_one_cs_at_every_boundary_for_all_configs);
    RUN_TEST(window_transitions_in_canonical_configs);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(pld_config_map_suite);
    GREATEST_MAIN_END();
}

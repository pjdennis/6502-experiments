#include "greatest.h"
#include "../bus.h"

struct dummy_state {
    int reset_count;
    int read_count;
    int write_count;
    int tick_count;
    uint16_t claim_lo;
    uint16_t claim_hi;
    uint8_t  claim_byte;
};

static void dummy_tick(struct chip *self, struct bus *bus) {
    (void)bus;
    struct dummy_state *s = (struct dummy_state *)self->state;
    s->tick_count++;
}

static bool dummy_read(struct chip *self, struct bus *bus,
                       uint16_t addr, uint8_t *data_out) {
    (void)bus;
    struct dummy_state *s = (struct dummy_state *)self->state;
    if (addr >= s->claim_lo && addr <= s->claim_hi) {
        *data_out = s->claim_byte;
        s->read_count++;
        return true;
    }
    return false;
}

static bool dummy_write(struct chip *self, struct bus *bus,
                        uint16_t addr, uint8_t data) {
    (void)bus;
    (void)data;
    struct dummy_state *s = (struct dummy_state *)self->state;
    if (addr >= s->claim_lo && addr <= s->claim_hi) {
        s->write_count++;
        return true;
    }
    return false;
}

static void dummy_reset(struct chip *self) {
    struct dummy_state *s = (struct dummy_state *)self->state;
    s->reset_count++;
}

static const struct chip_ops dummy_ops = {
    .tick  = dummy_tick,
    .read  = dummy_read,
    .write = dummy_write,
    .reset = dummy_reset,
};

TEST first_claim_wins_for_overlapping_reads(void) {
    struct dummy_state s_lo = {0, 0, 0, 0, 0x8000, 0x8FFF, 0xAA};
    struct dummy_state s_hi = {0, 0, 0, 0, 0x8800, 0x8FFF, 0xBB};
    struct chip chip_lo = {.ops = &dummy_ops, .name = "lo", .state = &s_lo};
    struct chip chip_hi = {.ops = &dummy_ops, .name = "hi", .state = &s_hi};

    struct bus b;
    bus_init(&b);
    ASSERT_EQ_FMT(0, bus_add_chip(&b, &chip_lo), "%d");
    ASSERT_EQ_FMT(0, bus_add_chip(&b, &chip_hi), "%d");

    /* Overlap zone $8800..$8FFF: lo registered first wins. */
    uint8_t data = 0;
    int claimed = bus_read(&b, 0x8800, &data);
    ASSERT_EQ_FMT(1, claimed, "%d");
    ASSERT_EQ_FMT((uint8_t)0xAA, data, "%u");
    ASSERT_EQ_FMT(1, s_lo.read_count, "%d");
    ASSERT_EQ_FMT(0, s_hi.read_count, "%d");

    /* Outside any claim: unclaimed. */
    data = 0xCC;
    claimed = bus_read(&b, 0x0100, &data);
    ASSERT_EQ_FMT(0, claimed, "%d");
    /* data_out left untouched on unclaimed read. */
    ASSERT_EQ_FMT((uint8_t)0xCC, data, "%u");

    PASS();
}

TEST first_claim_wins_for_overlapping_writes(void) {
    struct dummy_state s1 = {0, 0, 0, 0, 0x4000, 0x4FFF, 0};
    struct dummy_state s2 = {0, 0, 0, 0, 0x4800, 0x4FFF, 0};
    struct chip c1 = {.ops = &dummy_ops, .name = "c1", .state = &s1};
    struct chip c2 = {.ops = &dummy_ops, .name = "c2", .state = &s2};

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &c1);
    bus_add_chip(&b, &c2);

    int claimed = bus_write(&b, 0x4800, 0x55);
    ASSERT_EQ_FMT(1, claimed, "%d");
    ASSERT_EQ_FMT(1, s1.write_count, "%d");
    ASSERT_EQ_FMT(0, s2.write_count, "%d");
    PASS();
}

TEST reset_broadcasts_to_all_chips(void) {
    struct dummy_state s1 = {0, 0, 0, 0, 0, 0, 0};
    struct dummy_state s2 = {0, 0, 0, 0, 0, 0, 0};
    struct chip c1 = {.ops = &dummy_ops, .name = "c1", .state = &s1};
    struct chip c2 = {.ops = &dummy_ops, .name = "c2", .state = &s2};

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &c1);
    bus_add_chip(&b, &c2);
    bus_reset(&b);
    ASSERT_EQ_FMT(1, s1.reset_count, "%d");
    ASSERT_EQ_FMT(1, s2.reset_count, "%d");
    bus_reset(&b);
    ASSERT_EQ_FMT(2, s1.reset_count, "%d");
    ASSERT_EQ_FMT(2, s2.reset_count, "%d");
    PASS();
}

TEST reset_skips_chips_without_reset_method(void) {
    /* A chip that provides .tick but not .reset must not crash bus_reset. */
    struct chip_ops tick_only_ops = {.tick = dummy_tick};
    struct dummy_state s = {0};
    struct chip c = {.ops = &tick_only_ops, .name = "tick-only", .state = &s};

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &c);
    bus_reset(&b);  /* should be a no-op for this chip, not a crash */
    ASSERT_EQ_FMT(0, s.reset_count, "%d");
    PASS();
}

TEST bus_step_advances_tick_count(void) {
    struct bus b;
    bus_init(&b);
    ASSERT_EQ_FMT((unsigned long long)0, (unsigned long long)b.osc_ticks, "%llu");
    bus_step(&b);
    bus_step(&b);
    bus_step(&b);
    ASSERT_EQ_FMT((unsigned long long)3, (unsigned long long)b.osc_ticks, "%llu");
    PASS();
}

TEST bus_full_capacity_rejects_new_adds(void) {
    struct bus b;
    bus_init(&b);
    struct chip c = {.ops = NULL, .name = "x", .state = NULL};
    for (int i = 0; i < BUS_MAX_CHIPS; i++) {
        ASSERT_EQ_FMT(0, bus_add_chip(&b, &c), "%d");
    }
    ASSERT_EQ_FMT(-1, bus_add_chip(&b, &c), "%d");
    PASS();
}

TEST bus_init_leaves_lines_in_idle_state(void) {
    struct bus b;
    bus_init(&b);
    ASSERT_EQ_FMT(1, (int)b.rwb, "%d");
    ASSERT_EQ_FMT(0, (int)b.romcs, "%d");
    ASSERT_EQ_FMT(0, (int)b.ramcs, "%d");
    ASSERT_EQ_FMT(0, (int)b.viacs, "%d");
    ASSERT_EQ_FMT(0, (int)b.wr, "%d");
    ASSERT_EQ_FMT(0, (int)b.irq, "%d");
    ASSERT_EQ_FMT(0, (int)b.nmi, "%d");
    ASSERT_EQ_FMT(0, (int)b.res, "%d");
    ASSERT_EQ_FMT(0, b.chip_count, "%d");
    ASSERT_EQ_FMT((unsigned long long)0, (unsigned long long)b.osc_ticks, "%llu");
    PASS();
}

SUITE(bus_suite) {
    RUN_TEST(bus_init_leaves_lines_in_idle_state);
    RUN_TEST(first_claim_wins_for_overlapping_reads);
    RUN_TEST(first_claim_wins_for_overlapping_writes);
    RUN_TEST(reset_broadcasts_to_all_chips);
    RUN_TEST(reset_skips_chips_without_reset_method);
    RUN_TEST(bus_step_advances_tick_count);
    RUN_TEST(bus_full_capacity_rejects_new_adds);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(bus_suite);
    GREATEST_MAIN_END();
}

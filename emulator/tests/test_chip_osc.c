/* Phase 4c: OSC chip smoke test. */

#include <stdint.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/osc.h"

TEST osc_holds_frequency_and_bus_step_counts(void) {
    struct osc_state s;
    struct chip osc_chip;
    osc_init(&osc_chip, &s, 9720000ULL);

    struct bus b;
    bus_init(&b);
    bus_add_chip(&b, &osc_chip);

    for (int i = 0; i < 1000; i++) {
        bus_step(&b);
    }
    ASSERT_EQ_FMT((unsigned long long)1000, (unsigned long long)b.osc_ticks, "%llu");
    ASSERT_EQ_FMT((unsigned long long)9720000ULL, (unsigned long long)s.frequency_hz, "%llu");
    PASS();
}

SUITE(osc_suite) {
    RUN_TEST(osc_holds_frequency_and_bus_step_counts);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(osc_suite);
    GREATEST_MAIN_END();
}

#include <stdlib.h>

#include "greatest.h"
#include "../trace.h"

TEST trace_off_records_nothing(void) {
    trace_reset();
    trace_set_mode(0);
    for (int i = 0; i < 100; i++) {
        trace_record((uint16_t)i);
    }
    ASSERT_EQ_FMT((unsigned long long)0, (unsigned long long)trace_ring_position(), "%llu");
    ASSERT_EQ_FMT((uint32_t)0, trace_hist_count(50), "%u");
    PASS();
}

TEST trace_ring_wraps_correctly(void) {
    trace_reset();
    trace_set_mode(1);
    uint32_t total = TRACE_RING_SIZE + 2048;
    for (uint32_t i = 0; i < total; i++) {
        trace_record((uint16_t)i);
    }
    ASSERT_EQ_FMT((unsigned long long)total, (unsigned long long)trace_ring_position(), "%llu");
    /* Oldest evicted, newest preserved: ring at logical index i (for the most
     * recent TRACE_RING_SIZE entries) should return value i. */
    for (uint64_t i = total - TRACE_RING_SIZE; i < total; i++) {
        uint16_t expected = (uint16_t)i;
        uint16_t got = trace_ring_at(i);
        ASSERT_EQ_FMT(expected, got, "%u");
    }
    PASS();
}

TEST trace_hist_counts_per_pc(void) {
    trace_reset();
    trace_set_mode(2);
    for (int i = 0; i < 100; i++) trace_record(0x1234);
    for (int i = 0; i < 50;  i++) trace_record(0x5678);
    for (int i = 0; i < 200; i++) trace_record(0xABCD);
    ASSERT_EQ_FMT((uint32_t)100, trace_hist_count(0x1234), "%u");
    ASSERT_EQ_FMT((uint32_t)50,  trace_hist_count(0x5678), "%u");
    ASSERT_EQ_FMT((uint32_t)200, trace_hist_count(0xABCD), "%u");
    ASSERT_EQ_FMT((uint32_t)0,   trace_hist_count(0x0001), "%u");
    PASS();
}

TEST trace_both_modes_independent(void) {
    trace_reset();
    trace_set_mode(3);
    for (int i = 0; i < 10; i++) trace_record(0x4000);
    ASSERT_EQ_FMT((unsigned long long)10, (unsigned long long)trace_ring_position(), "%llu");
    ASSERT_EQ_FMT((uint32_t)10,  trace_hist_count(0x4000), "%u");
    ASSERT_EQ_FMT((uint16_t)0x4000, trace_ring_at(0), "%u");
    PASS();
}

TEST trace_env_parsing(void) {
    trace_reset();
    setenv("E6502_TRACE", "ring", 1);
    trace_init_from_env();
    ASSERT_EQ_FMT(1, trace_mode, "%d");

    trace_reset();
    setenv("E6502_TRACE", "hist", 1);
    trace_init_from_env();
    ASSERT_EQ_FMT(2, trace_mode, "%d");

    trace_reset();
    setenv("E6502_TRACE", "both", 1);
    trace_init_from_env();
    ASSERT_EQ_FMT(3, trace_mode, "%d");

    /* "ring hist" should map to both (3). */
    trace_reset();
    setenv("E6502_TRACE", "ring hist", 1);
    trace_init_from_env();
    ASSERT_EQ_FMT(3, trace_mode, "%d");

    trace_reset();
    unsetenv("E6502_TRACE");
    trace_init_from_env();
    ASSERT_EQ_FMT(0, trace_mode, "%d");

    PASS();
}

SUITE(trace_suite) {
    RUN_TEST(trace_off_records_nothing);
    RUN_TEST(trace_ring_wraps_correctly);
    RUN_TEST(trace_hist_counts_per_pc);
    RUN_TEST(trace_both_modes_independent);
    RUN_TEST(trace_env_parsing);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(trace_suite);
    GREATEST_MAIN_END();
}

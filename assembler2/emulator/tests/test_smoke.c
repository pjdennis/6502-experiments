#include "greatest.h"

TEST trivial_pass(void) {
    ASSERT_EQ(1 + 1, 2);
    PASS();
}

SUITE(smoke_suite) {
    RUN_TEST(trivial_pass);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(smoke_suite);
    GREATEST_MAIN_END();
}

/* Phase 4b smoke test: emu_run_wendy2c returns 0 when invoked, and
 * the default emu_run path is reachable independently. Doesn't run
 * actual emulator binaries (those need globals from emulator.c); just
 * verifies the wendy2c shell links and exits cleanly. */

#include <stdint.h>
#include <stdio.h>

#include "greatest.h"
#include "../cli.h"
#include "../emu_wendy2c.h"
#include "../cpu_core.h"

/* Provide stubs for cpu_core.h externs that the wendy2c shell pulls in
 * transitively. */
uint8_t read6502(uint16_t address) { (void)address; return 0; }
void    write6502(uint16_t address, uint8_t value) { (void)address; (void)value; }

TEST wendy2c_shell_returns_zero(void) {
    struct emu_opts opts;
    emu_opts_init(&opts);
    opts.machine = MACHINE_WENDY2C;
    opts.cpu_variant_opt = CPU_65C02;
    int rc = emu_run_wendy2c(&opts);
    ASSERT_EQ_FMT(0, rc, "%d");
    /* The shell sets cpu_variant from opts. */
    ASSERT_EQ_FMT(CPU_65C02, cpu_variant, "%d");
    cpu_variant = CPU_NMOS;
    PASS();
}

SUITE(machine_dispatch_suite) {
    RUN_TEST(wendy2c_shell_returns_zero);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(machine_dispatch_suite);
    GREATEST_MAIN_END();
}

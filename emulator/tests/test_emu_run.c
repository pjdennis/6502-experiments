/* Smoke test for emu_run.c.
 *
 * emu_run_default depends on a large amount of global state (CPU core,
 * memory, file descriptors, signal handlers). End-to-end behavior is
 * covered by the asm bootstrap and editor integration suites. This
 * file only verifies that:
 *   - emu_run_default exits immediately when `done` is already set
 *     (i.e., the early-exit path is reachable without crashing).
 *   - it links cleanly with the extern declarations in emu_run.h. */

#include <stdio.h>
#include <stdint.h>
#include <signal.h>
#include <time.h>

#include "greatest.h"
#include "../emu_run.h"
#include "../cli.h"

/* Provide minimal definitions of all the externs the linker pulls in
 * via emu_run.o. In the real emulator these live in emulator.c /
 * console.c / cpu_core.c; here we redefine them locally so the test
 * binary doesn't have to pull the whole emulator in. */
int done = 0;
int exitcode_set = -1;
int console_mode = 0;
int terminal_mode = 0;
double target_mhz = 0.0;
struct timespec start_time;
uint16_t *arg_addresses = NULL;
FILE *output_file_ptr = NULL;
FILE *input_file_ptr = NULL;
volatile sig_atomic_t sigint_requested = 0;
volatile sig_atomic_t sigtstp_requested = 0;
volatile sig_atomic_t sigcont_requested = 0;
struct timespec last_repaint_check;

void handle_sigtstp(int sig) { (void)sig; }
void restore_terminal(void) {}
void enter_console(void) {}

/* Stubs for cpu_core.h and console.h symbols used by emu_run.c. */
uint64_t clockticks6502 = 0;
uint16_t pc = 0;
void step6502(void) {}
int show_repaints = 0;
void console_redraw(void) {}
void repaint_overlay_update(struct timespec *now) { (void)now; }

TEST emu_run_returns_immediately_when_done(void) {
    done = 1;
    struct emu_opts opts;
    emu_opts_init(&opts);
    int rc = emu_run_default(&opts);
    ASSERT_EQ_FMT(0, rc, "%d");
    PASS();
}

TEST emu_run_returns_on_sigint(void) {
    done = 0;
    exitcode_set = -1;
    sigint_requested = 1;
    struct emu_opts opts;
    emu_opts_init(&opts);
    int rc = emu_run_default(&opts);
    ASSERT_EQ_FMT(0, rc, "%d");
    ASSERT_EQ_FMT(1, done, "%d");
    ASSERT_EQ_FMT(130, exitcode_set, "%d");
    PASS();
}

SUITE(emu_run_suite) {
    RUN_TEST(emu_run_returns_immediately_when_done);
    RUN_TEST(emu_run_returns_on_sigint);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(emu_run_suite);
    GREATEST_MAIN_END();
}

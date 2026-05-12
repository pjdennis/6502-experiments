#ifndef EMULATOR_EMU_RUN_H
#define EMULATOR_EMU_RUN_H

#include <stdio.h>
#include <stdint.h>
#include <signal.h>
#include <time.h>

#include "cli.h"

/* Shared run-loop state. Defined in emulator.c; emu_run_default reads
 * and writes these. */
extern int done;
extern int exitcode_set;
extern int console_mode;
extern int terminal_mode;
extern double target_mhz;
extern struct timespec start_time;
extern uint16_t *arg_addresses;
extern FILE *output_file_ptr;
extern FILE *input_file_ptr;
extern volatile sig_atomic_t sigint_requested;
extern volatile sig_atomic_t sigtstp_requested;
extern volatile sig_atomic_t sigcont_requested;
extern struct timespec last_repaint_check;

/* Helpers defined in emulator.c. */
void handle_sigtstp(int sig);
void restore_terminal(void);
void enter_console(void);

/* Run the default emulation loop until `done` becomes non-zero or the
 * hardcoded cycle cap is hit. Returns 0 on normal exit, 1 on timeout
 * (in which case the function has already printed "did not terminate
 * within N cycles", dumped trace, and closed/freed the file handles
 * and arg_addresses). */
int emu_run_default(const struct emu_opts *opts);

#endif

#ifndef EMULATOR_TRACE_H
#define EMULATOR_TRACE_H

#include <stdint.h>

/* Diagnostic facility (opt-in via E6502_TRACE env var):
 *   ring   = dump last N PCs on timeout
 *   hist   = dump top hottest PCs on timeout
 *   both   = both
 * Always-on cost is one comparison per step plus (if active) one
 * histogram-bucket increment + one ring-buffer write. */

#define TRACE_RING_SIZE 4096

/* Mode bitmask: 0=off, 1=ring, 2=hist, 3=both. Exported so the
 * hot path can do `if (trace_mode) trace_record(pc);` without a call. */
extern int trace_mode;

void trace_init_from_env(void);
void trace_set_mode(int mode);
void trace_reset(void);
void trace_record(uint16_t pc);
void trace_dump(const char *why);

/* Inspection accessors (used by tests). */
uint64_t trace_ring_position(void);
uint16_t trace_ring_at(uint64_t logical_pos);
uint32_t trace_hist_count(uint16_t pc);

#endif

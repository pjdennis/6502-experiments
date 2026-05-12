#ifndef CPU_CORE_H
#define CPU_CORE_H

#include <stdint.h>

// CPU variant selection. NMOS is the default; 65C02 picks an
// alternate dispatch table (currently initialized identically to NMOS;
// phases 3b..3f add the actual differences).
#define CPU_NMOS  0
#define CPU_65C02 1
extern int cpu_variant;

// 6502 CPU registers
extern uint16_t pc;
extern uint8_t sp, a, x, y, status;

// Helper variables
extern uint32_t instructions;
extern uint64_t clockticks6502, clockgoal6502;

// CPU interface
void reset6502(void);
void exec6502(uint64_t tickcount);
void step6502(void);
void nmi6502(void);
void irq6502(void);
void hookexternal(void *funcptr);

// These must be provided by the host
extern uint8_t read6502(uint16_t address);
extern void write6502(uint16_t address, uint8_t value);

#endif

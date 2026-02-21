#ifndef STUBS_H
#define STUBS_H

#include <stdint.h>
#include <stddef.h>

// I/O port addresses
#define port_read_b  0xf004
#define port_write_b 0xf001
#define port_write_d 0xf002
#define port_exit    0xf003
#define port_open    0xf005
#define port_close   0xf000
#define port_read    0xfe85
#define port_argc    0xfe80
#define port_argv_l  0xfe81
#define port_argv_h  0xfe82
#define port_openout 0xfe83
#define port_write   0xfe84
#define port_con_read  0xfe90
#define port_con_flush 0xfe91
#define port_term_rows 0xfe92
#define port_term_cols 0xfe93
#define port_con_ready 0xfe94
#define port_serial_ready       0xfe95
#define port_serial_data        0xfe96
#define port_serial_write       0xfe97
#define port_serial_write_ready 0xfe98
#define port_eof_b   0xfe99
#define port_eof     0xfe9a
#define port_opendir 0xfe9b

// Generate I/O stubs at $F006+ in memory, returns address after last stub byte
size_t generate_stubs(uint8_t *memory, int terminal_mode);

#endif

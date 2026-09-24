/* Phase 3i: CPU bus-transaction taps. Default behaviour: taps are
 * NULL and step6502 runs the same path as before. When installed, the
 * tap is called once per bus transaction with (addr, data). */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../cpu_core.h"

static uint8_t test_memory[0x10000];
uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

#define MAX_LOG 64
struct entry {
    uint16_t addr;
    uint8_t  data;
    char     rw;
};
static struct entry log_entries[MAX_LOG];
static int log_len = 0;

static void on_read(uint16_t addr, uint8_t data) {
    if (log_len < MAX_LOG) {
        log_entries[log_len].addr = addr;
        log_entries[log_len].data = data;
        log_entries[log_len].rw = 'R';
        log_len++;
    }
}

static void on_write(uint16_t addr, uint8_t data) {
    if (log_len < MAX_LOG) {
        log_entries[log_len].addr = addr;
        log_entries[log_len].data = data;
        log_entries[log_len].rw = 'W';
        log_len++;
    }
}

static void setup(uint16_t entry, const uint8_t *bytes, size_t n) {
    memset(test_memory, 0, sizeof(test_memory));
    memcpy(test_memory + entry, bytes, n);
    test_memory[0xFFFC] = (uint8_t)(entry & 0xFF);
    test_memory[0xFFFD] = (uint8_t)(entry >> 8);
    test_memory[0xFFFE] = 0x00;
    test_memory[0xFFFF] = 0x90;
    cpu_variant = CPU_NMOS;
    log_len = 0;
    cpu_bus_read_tap = NULL;
    cpu_bus_write_tap = NULL;
    reset6502();
}

TEST taps_default_null(void) {
    ASSERT_EQ((void *)NULL, (void *)cpu_bus_read_tap);
    ASSERT_EQ((void *)NULL, (void *)cpu_bus_write_tap);
    PASS();
}

TEST taps_record_read_and_write(void) {
    /* LDA #$42 ; STA $0200 ; BRK */
    uint8_t prog[] = { 0xA9, 0x42, 0x8D, 0x00, 0x02, 0x00 };
    setup(0x0300, prog, sizeof(prog));
    cpu_bus_read_tap = on_read;
    cpu_bus_write_tap = on_write;

    step6502();  /* LDA #$42 */
    step6502();  /* STA $0200 */

    /* Expect at least: read of opcode $A9, read of immediate $42, read
     * of opcode $8D, read of operand $00, read of operand $02, write
     * of $42 to $0200. Order matters. */
    ASSERT(log_len >= 6);
    /* opcode fetch */
    ASSERT_EQ_FMT('R', log_entries[0].rw, "%c");
    ASSERT_EQ_FMT((uint16_t)0x0300, log_entries[0].addr, "%04X");
    ASSERT_EQ_FMT((uint8_t)0xA9, log_entries[0].data, "%02X");
    /* operand fetch */
    ASSERT_EQ_FMT('R', log_entries[1].rw, "%c");
    ASSERT_EQ_FMT((uint16_t)0x0301, log_entries[1].addr, "%04X");
    ASSERT_EQ_FMT((uint8_t)0x42, log_entries[1].data, "%02X");
    /* The write should be in the log */
    int write_found = 0;
    for (int i = 0; i < log_len; i++) {
        if (log_entries[i].rw == 'W' &&
            log_entries[i].addr == 0x0200 &&
            log_entries[i].data == 0x42) {
            write_found = 1;
            break;
        }
    }
    ASSERT_EQ_FMT(1, write_found, "%d");

    cpu_bus_read_tap = NULL;
    cpu_bus_write_tap = NULL;
    PASS();
}

SUITE(bus_tap_suite) {
    RUN_TEST(taps_default_null);
    RUN_TEST(taps_record_read_and_write);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(bus_tap_suite);
    GREATEST_MAIN_END();
}

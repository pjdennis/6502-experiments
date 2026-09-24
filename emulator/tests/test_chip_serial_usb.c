/* Phase 13a: SERIAL_USB chip smoke test.
 *
 * Drive a known byte pattern into the chip's queue, simulate the
 * wendy2c ISR sequence by hand (set ACR=SR_IN_T2, read SR, tick T2
 * underflows), and verify the assembled SR matches. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/via_6522.h"
#include "../chips/serial_usb.h"

static struct via_6522_state vs;
static struct serial_usb_state ss;
static struct chip vch, sch;
static struct bus bus_;

static void setup(void) {
    via_6522_init(&vch, &vs);
    serial_usb_init(&sch, &ss, &vs);
    bus_init(&bus_);
    bus_add_chip(&bus_, &vch);
    bus_add_chip(&bus_, &sch);
    bus_.viacs = 1;

    /* Wendy2c init: PCR = CB2 IND NEG E, ACR = SR IN T2, IER enables
     * CB2+SR (so the SERIAL_USB chip sees the on-target as ready),
     * T2 latch = 1. */
    bus_write(&bus_, 0xF00C, VIA_PCR_CB2_IND_NEG_E);  /* PCR */
    bus_write(&bus_, 0xF00B, VIA_ACR_SR_IN_T2);        /* ACR */
    bus_write(&bus_, 0xF00E, 0x80 | VIA_INT_CB2 | VIA_INT_SR);  /* IER */
    bus_write(&bus_, 0xF008, 0x01);                    /* T2CL latch */
    bus_write(&bus_, 0xF009, 0x00);                    /* T2CH arms T2 with 0x0001 */
}

/* Drive enough ticks to shift one queued byte through. With T2 latch=1
 * each underflow takes ~2 bus_steps. */
static void shift_one_byte(void) {
    /* Wait for SERIAL_USB to drive CB2 low (start). */
    int safety = 100;
    while (safety-- > 0) {
        bus_.cpu_cycle_due = 1;
        bus_step(&bus_);
        /* Once VIA's IFR has CB2 set, the wendy2c ISR would re-enable
         * SR_IN_T2 and read SR (we already set ACR=SR_IN_T2 above so
         * we just need to read SR to arm the shift). */
        uint8_t ifr = 0;
        bus_read(&bus_, 0xF00D, &ifr);
        if (ifr & VIA_INT_CB2) {
            /* Clear CB2 IFR by writing 1; read SR to arm the shift. */
            bus_write(&bus_, 0xF00D, VIA_INT_CB2);
            uint8_t junk;
            bus_read(&bus_, 0xF00A, &junk);  /* SR read arms shift */
            break;
        }
    }
    /* Now run enough ticks to shift 8 bits. T2=1, each shift takes ~2
     * bus_steps; budget plenty of margin. */
    for (int i = 0; i < 200; i++) {
        bus_.cpu_cycle_due = 1;
        bus_step(&bus_);
        uint8_t ifr = 0;
        bus_read(&bus_, 0xF00D, &ifr);
        if (ifr & VIA_INT_SR) break;  /* byte completed */
    }
}

TEST send_one_byte_round_trip(void) {
    setup();
    serial_usb_queue_byte(&ss, 0xAA);
    shift_one_byte();
    /* LSB-first into VIA's SR (left-shift, OR into bit 0) leaves SR
     * holding the byte bit-reversed: 0xAA -> 0x55. The wendy2c
     * TRANSLATE table reverses again on receive to recover 0xAA. */
    uint8_t sr = 0;
    bus_read(&bus_, 0xF00A, &sr);
    ASSERT_EQ_FMT((uint8_t)0x55, sr, "%02X");
    PASS();
}

TEST asymmetric_byte_round_trip(void) {
    setup();
    /* 0x47 = 0100 0111 -> bit-reversed 1110 0010 = 0xE2. */
    serial_usb_queue_byte(&ss, 0x47);
    shift_one_byte();
    uint8_t sr = 0;
    bus_read(&bus_, 0xF00A, &sr);
    ASSERT_EQ_FMT((uint8_t)0xE2, sr, "%02X");
    PASS();
}

TEST queue_empty_serial_chip_does_nothing(void) {
    setup();
    /* Don't queue any byte. Tick a bit, expect no CB2 IFR fired. */
    for (int i = 0; i < 20; i++) { bus_.cpu_cycle_due = 1; bus_step(&bus_); }
    uint8_t ifr = 0;
    bus_read(&bus_, 0xF00D, &ifr);
    ASSERT_EQ_FMT((uint8_t)0, (uint8_t)(ifr & VIA_INT_CB2), "%02X");
    PASS();
}

TEST queue_count_tracks_pending_bytes(void) {
    setup();
    ASSERT_EQ_FMT(0, serial_usb_queue_count(&ss), "%d");
    serial_usb_queue_byte(&ss, 0x12);
    serial_usb_queue_byte(&ss, 0x34);
    serial_usb_queue_byte(&ss, 0x56);
    ASSERT_EQ_FMT(3, serial_usb_queue_count(&ss), "%d");
    PASS();
}

SUITE(serial_usb_suite) {
    RUN_TEST(send_one_byte_round_trip);
    RUN_TEST(asymmetric_byte_round_trip);
    RUN_TEST(queue_empty_serial_chip_does_nothing);
    RUN_TEST(queue_count_tracks_pending_bytes);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(serial_usb_suite);
    GREATEST_MAIN_END();
}

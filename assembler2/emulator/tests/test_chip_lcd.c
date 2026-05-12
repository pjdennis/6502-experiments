/* Phase 10: HD44780 LCD chip tests.
 *
 * Drives the LCD by writing through the VIA's PORTA + PORTB and
 * pulsing the E line, exactly as the wendy2c on-target code does. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/via_6522.h"
#include "../chips/lcd_hd44780.h"

static struct via_6522_state vs;
static struct lcd_hd44780_state ls;
static struct chip vch, lch;
static struct bus bus_;

static void setup(void) {
    via_6522_init(&vch, &vs);
    lcd_hd44780_init(&lch, &ls, &vs);
    bus_init(&bus_);
    bus_add_chip(&bus_, &vch);
    bus_add_chip(&bus_, &lch);

    /* DDRA = 0xF9 -- bits 0 (RS), 3 (RW), 4..7 (data); DDRB = 0x20 (E). */
    bus_.viacs = 1;
    bus_write(&bus_, 0xF002, 0x20);  /* DDRB */
    bus_write(&bus_, 0xF003, 0xF9);  /* DDRA */
}

/* Write one nibble of one byte through the VIA: data nibble in bits
 * 7..4 of PORTA, RS in bit 0, RW=0 in bit 3, E pulses high then low
 * via PORTB bit 5. */
static void send_nibble(uint8_t nibble, uint8_t rs) {
    uint8_t porta = (uint8_t)((nibble & 0x0F) << 4) | (rs ? 0x01 : 0x00);
    bus_write(&bus_, 0xF001, porta);  /* ORA */
    /* E high. */
    bus_write(&bus_, 0xF000, 0x20);   /* ORB: E=1 */
    bus_step(&bus_);                   /* let chips see it */
    /* E low (latches). */
    bus_write(&bus_, 0xF000, 0x00);
    bus_step(&bus_);                   /* falling edge captured */
}

/* Send a full byte = high nibble then low nibble (4-bit mode). */
static void send_byte(uint8_t byte, uint8_t rs) {
    send_nibble((uint8_t)((byte >> 4) & 0x0F), rs);
    send_nibble((uint8_t)(byte & 0x0F), rs);
}

/* Send an 8-bit-mode command (one nibble of upper bits only). The
 * function-set for the 4-bit init dance is sent this way once. */
static void send_cmd_8bit(uint8_t upper_nibble) {
    send_nibble(upper_nibble, 0);
}

TEST init_4bit_then_write_hello(void) {
    setup();

    /* 4-bit init: send function-set with DL=0 in 8-bit mode. */
    send_cmd_8bit(0x2);  /* FUNCTION_SET (0x20) with DL=0, N=0 */

    /* Now in 4-bit mode. Set up: 2-line, 5x8 -> $28. */
    send_byte(0x28, 0);
    /* Display on + cursor off + blink off -> $0C. */
    send_byte(0x0C, 0);
    /* Entry mode: increment, no shift -> $06. */
    send_byte(0x06, 0);
    /* Clear display -> $01. */
    send_byte(0x01, 0);

    /* Set DDRAM addr to $00 (already there but be explicit). */
    send_byte(0x80, 0);

    /* Write "Hello". */
    send_byte('H', 1);
    send_byte('e', 1);
    send_byte('l', 1);
    send_byte('l', 1);
    send_byte('o', 1);

    char buf[40];
    lcd_hd44780_render(&ls, buf);
    /* Buffer is 16x2 = 32 chars (no separator). First 5 chars = "Hello". */
    ASSERT_STRN_EQ("Hello", buf, 5);
    /* DDRAM at $00..$04 directly. */
    ASSERT_EQ_FMT((uint8_t)'H', ls.ddram[0], "%c");
    ASSERT_EQ_FMT((uint8_t)'e', ls.ddram[1], "%c");
    ASSERT_EQ_FMT((uint8_t)'l', ls.ddram[2], "%c");
    ASSERT_EQ_FMT((uint8_t)'l', ls.ddram[3], "%c");
    ASSERT_EQ_FMT((uint8_t)'o', ls.ddram[4], "%c");
    PASS();
}

TEST cgram_slot_6_renders_as_tilde(void) {
    setup();
    send_cmd_8bit(0x2);  /* enter 4-bit mode */
    send_byte(0x28, 0);
    send_byte(0x80, 0);
    send_byte(0x06, 1);  /* CGRAM slot 6 byte */

    char buf[40];
    lcd_hd44780_render(&ls, buf);
    ASSERT_EQ_FMT((char)'~', buf[0], "%c");
    PASS();
}

TEST line2_address_starts_at_40(void) {
    setup();
    send_cmd_8bit(0x2);
    send_byte(0x28, 0);
    /* Set DDRAM to $40 (start of line 2 in 16x2). */
    send_byte(0xC0, 0);
    send_byte('X', 1);
    send_byte('Y', 1);

    char buf[40];
    lcd_hd44780_render(&ls, buf);
    /* row 0: 16 chars of $20, row 1: "XY..." */
    ASSERT_EQ_FMT((char)'X', buf[16], "%c");
    ASSERT_EQ_FMT((char)'Y', buf[17], "%c");
    PASS();
}

SUITE(lcd_hd44780_suite) {
    RUN_TEST(init_4bit_then_write_hello);
    RUN_TEST(cgram_slot_6_renders_as_tilde);
    RUN_TEST(line2_address_starts_at_40);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(lcd_hd44780_suite);
    GREATEST_MAIN_END();
}

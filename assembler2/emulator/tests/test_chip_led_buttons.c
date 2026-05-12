/* Phase 11: led_buttons chip tests.
 *
 * The chip taps PORTB pins for the LED bit (PB6) and pushes a
 * configurable button bit into the VIA's PORTA input drive. */

#include <stdint.h>
#include "greatest.h"
#include "../bus.h"
#include "../chips/via_6522.h"
#include "../chips/led_buttons.h"

static struct via_6522_state vs;
static struct led_buttons_state ls;
static struct chip vch, lch;
static struct bus bus_;

static void setup(void) {
    via_6522_init(&vch, &vs);
    led_buttons_init(&lch, &ls, &vs);
    bus_init(&bus_);
    bus_add_chip(&bus_, &vch);
    bus_add_chip(&bus_, &lch);
    bus_.viacs = 1;
}

TEST led_follows_pb6(void) {
    setup();
    /* DDRB bit 6 = output. */
    bus_write(&bus_, 0xF002, 0x40);

    /* ORB = 0: LED off. */
    bus_write(&bus_, 0xF000, 0x00);
    bus_step(&bus_);
    ASSERT_EQ_FMT(0, led_buttons_led(&ls), "%d");

    /* ORB bit 6 set: LED on. */
    bus_write(&bus_, 0xF000, 0x40);
    bus_step(&bus_);
    ASSERT_EQ_FMT(1, led_buttons_led(&ls), "%d");

    /* Clear again. */
    bus_write(&bus_, 0xF000, 0x00);
    bus_step(&bus_);
    ASSERT_EQ_FMT(0, led_buttons_led(&ls), "%d");
    PASS();
}

TEST press_appears_on_porta_input(void) {
    setup();
    /* DDRA bit 5 = input (0). */
    bus_write(&bus_, 0xF003, 0x00);

    uint8_t porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x20, "%d");

    led_buttons_press(&ls, 1);
    porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0x20, porta & 0x20, "%d");
    ASSERT_EQ_FMT(1, led_buttons_button(&ls), "%d");

    led_buttons_press(&ls, 0);
    porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x20, "%d");
    ASSERT_EQ_FMT(0, led_buttons_button(&ls), "%d");
    PASS();
}

TEST press_masked_when_ddra_drives_output(void) {
    /* If the program flips PA5 to output (DDRA bit 5 = 1), the
     * external input drive is masked at the pin -- the program's own
     * ORA value wins. */
    setup();
    bus_write(&bus_, 0xF003, 0x20);  /* DDRA = PA5 output */
    bus_write(&bus_, 0xF001, 0x00);  /* ORA = 0 */
    led_buttons_press(&ls, 1);
    uint8_t porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x20, "%d");
    PASS();
}

SUITE(led_buttons_suite) {
    RUN_TEST(led_follows_pb6);
    RUN_TEST(press_appears_on_porta_input);
    RUN_TEST(press_masked_when_ddra_drives_output);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(led_buttons_suite);
    GREATEST_MAIN_END();
}

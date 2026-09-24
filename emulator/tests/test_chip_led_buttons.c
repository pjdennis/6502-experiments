/* Phase 11: led_buttons chip tests.
 *
 * The chip taps PORTB pins for the morse LED bit (PB6) and PORTA pins
 * for the control-LED bit (PA2), and pushes a configurable button bit
 * (default PA1) into the VIA's PORTA input drive. */

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

TEST control_led_follows_pa2(void) {
    /* The control LED on PA2 tracks the program's ORA bit 2 when the
     * program has set DDRA bit 2 = output (which it must do to drive
     * the LED). prg_led_control.inc toggles it on each button press. */
    setup();
    /* DDRA bit 2 = output. */
    bus_write(&bus_, 0xF003, 0x04);

    /* ORA = 0: control LED off. */
    bus_write(&bus_, 0xF001, 0x00);
    bus_step(&bus_);
    ASSERT_EQ_FMT(0, led_buttons_control_led(&ls), "%d");

    /* ORA bit 2 set: control LED on. */
    bus_write(&bus_, 0xF001, 0x04);
    bus_step(&bus_);
    ASSERT_EQ_FMT(1, led_buttons_control_led(&ls), "%d");

    /* Clear again. */
    bus_write(&bus_, 0xF001, 0x00);
    bus_step(&bus_);
    ASSERT_EQ_FMT(0, led_buttons_control_led(&ls), "%d");
    PASS();
}

TEST press_appears_on_porta_input(void) {
    /* Default button pin is PA1 (mask 0x02), matching
     * CONTROL_BUTTON = %00000010 in multitasking_test_wendy2c.s.
     * Active-low: pressed -> bit LOW, released -> bit HIGH. */
    setup();
    /* DDRA bit 1 = input (0). */
    bus_write(&bus_, 0xF003, 0x00);

    /* Init left the pin HIGH (pull-up); confirm. */
    uint8_t porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0x02, porta & 0x02, "%d");

    led_buttons_press(&ls, 1);
    porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x02, "%d");        /* pressed -> LOW */
    ASSERT_EQ_FMT(1, led_buttons_button(&ls), "%d");

    led_buttons_press(&ls, 0);
    porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0x02, porta & 0x02, "%d");     /* released -> HIGH */
    ASSERT_EQ_FMT(0, led_buttons_button(&ls), "%d");
    PASS();
}

TEST press_masked_when_ddra_drives_output(void) {
    /* If the program flips PA1 to output (DDRA bit 1 = 1), the
     * external input drive is masked at the pin -- the program's own
     * ORA value wins. */
    setup();
    bus_write(&bus_, 0xF003, 0x02);  /* DDRA = PA1 output */
    bus_write(&bus_, 0xF001, 0x00);  /* ORA = 0 */
    led_buttons_press(&ls, 1);       /* would drive LOW if input */
    uint8_t porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x02, "%d");
    PASS();
}

TEST button_mask_configurable(void) {
    /* The button pin is configurable; we verify the legacy PA5 mask
     * still works if a caller overrides it. */
    setup();
    ls.button_pa_mask = 0x20;
    bus_write(&bus_, 0xF003, 0x00);  /* DDRA all inputs */
    led_buttons_press(&ls, 1);       /* pressed -> PA5 LOW */
    uint8_t porta = via_6522_porta_pins(&vs);
    ASSERT_EQ_FMT(0, porta & 0x20, "%d");
    PASS();
}

SUITE(led_buttons_suite) {
    RUN_TEST(led_follows_pb6);
    RUN_TEST(control_led_follows_pa2);
    RUN_TEST(press_appears_on_porta_input);
    RUN_TEST(press_masked_when_ddra_drives_output);
    RUN_TEST(button_mask_configurable);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(led_buttons_suite);
    GREATEST_MAIN_END();
}

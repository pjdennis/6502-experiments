#ifndef EMULATOR_CHIPS_LED_BUTTONS_H
#define EMULATOR_CHIPS_LED_BUTTONS_H

#include <stdint.h>
#include "../bus.h"

struct via_6522_state;

/* led_buttons: taps the wendy2c VIA's port pins to surface the two
 * LED states, and injects a control-button level on PORTA so the
 * live-render keyboard handler (or a test) can simulate a press.
 *
 * Pin mapping for wendy2c (see base_config_wendy2c.inc and
 * multitasking_test_wendy2c.s):
 *
 *   Morse LED on PB6     (LED_MASK = %01000000, LED_PORT = PORTB).
 *   Control button on PA1 (CONTROL_BUTTON  = %00000010, PORTA input).
 *   Control LED on PA2    (CONTROL_LED     = %00000100, PORTA output).
 *
 * PA1 and PA2 are repurposed from the (disabled) graphic-display
 * GD_RSTB / GD_CSB pins; see base_config_wendy2c.inc.
 *
 * This chip claims no MMIO. Each tick it samples PORTB / PORTA pins
 * to refresh `led_on` (PB6) and `control_led_on` (PA2), so the
 * live-render code can read them without polling raw VIA registers. */

struct led_buttons_state {
    struct via_6522_state *via;
    uint8_t led_pb_mask;          /* default 0x40 = PB6 (morse LED) */
    uint8_t control_led_pa_mask;  /* default 0x04 = PA2 (toggled by button) */
    uint8_t button_pa_mask;       /* default 0x02 = PA1; configurable */
    uint8_t led_on;               /* refreshed each tick from PORTB pins */
    uint8_t control_led_on;       /* refreshed each tick from PORTA pins */
    uint8_t button_pressed;       /* 0 = released, 1 = held */
};

void led_buttons_init(struct chip *chip, struct led_buttons_state *state,
                      struct via_6522_state *via);

/* Press (down=1) or release (down=0) the control button. Drives the
 * VIA's PORTA input bit ACTIVE-LOW (down -> bit low, up -> bit high),
 * modeling a typical pull-up + switch-to-ground topology. The
 * `button_pressed` field still tracks the logical state for renderers
 * (1 = held). */
void led_buttons_press(struct led_buttons_state *state, int down);

/* Snapshot accessors for renderers / tests. */
int led_buttons_led(const struct led_buttons_state *state);
int led_buttons_control_led(const struct led_buttons_state *state);
int led_buttons_button(const struct led_buttons_state *state);

#endif

#ifndef EMULATOR_CHIPS_LED_BUTTONS_H
#define EMULATOR_CHIPS_LED_BUTTONS_H

#include <stdint.h>
#include "../bus.h"

struct via_6522_state;

/* led_buttons: taps the wendy2c VIA's PORTB to surface the LED state,
 * and injects a control-button level on PORTA so the live-render
 * keyboard handler (or a test) can simulate a press.
 *
 * Pin mapping for wendy2c (see wendy2c_led_test.s and the LED_MASK /
 * LED_PORT defines in *_wendy2c.s programs):
 *
 *   LED on PB6 (LED_MASK = %01000000, LED_PORT = PORTB).
 *   Control button on PA5 -- TODO: confirm. No program currently in
 *     the repo reads it (multitasking_test_wendy2c.s has CONTROL_BUTTON
 *     = %00100000 commented out). Treating PA5 as the placeholder; the
 *     led_buttons.button_pa_mask field is configurable for whatever the
 *     first reader turns out to want.
 *
 * This chip claims no MMIO. Its only bus interaction is the per-tick
 * sample of via_6522_portb_pins() to update `led_on`, so the
 * live-render code can read it without polling raw VIA registers. */

struct led_buttons_state {
    struct via_6522_state *via;
    uint8_t led_pb_mask;          /* default 0x40 = PB6 */
    uint8_t button_pa_mask;       /* default 0x20 = PA5; configurable */
    uint8_t led_on;               /* refreshed each tick from PORTB pins */
    uint8_t button_pressed;       /* 0 = released, 1 = held */
};

void led_buttons_init(struct chip *chip, struct led_buttons_state *state,
                      struct via_6522_state *via);

/* Press (down=1) or release (down=0) the control button. Pushes the
 * level through to the VIA's PORTA input drive. */
void led_buttons_press(struct led_buttons_state *state, int down);

/* Snapshot accessors for renderers / tests. */
int led_buttons_led(const struct led_buttons_state *state);
int led_buttons_button(const struct led_buttons_state *state);

#endif

#include "led_buttons.h"

#include <stddef.h>
#include "via_6522.h"

static void led_buttons_tick(struct chip *self, struct bus *bus) {
    (void)bus;
    struct led_buttons_state *s = (struct led_buttons_state *)self->state;
    uint8_t portb = via_6522_portb_pins(s->via);
    s->led_on = (portb & s->led_pb_mask) ? 1 : 0;
}

static void led_buttons_reset(struct chip *self) {
    struct led_buttons_state *s = (struct led_buttons_state *)self->state;
    s->led_on = 0;
    s->button_pressed = 0;
    if (s->via) {
        via_6522_set_porta_input_bit(s->via, s->button_pa_mask, 0);
    }
}

static const struct chip_ops led_buttons_ops = {
    .tick  = led_buttons_tick,
    .read  = NULL,
    .write = NULL,
    .reset = led_buttons_reset,
};

void led_buttons_init(struct chip *chip, struct led_buttons_state *state,
                      struct via_6522_state *via) {
    state->via = via;
    state->led_pb_mask = 0x40;     /* PB6 */
    state->button_pa_mask = 0x20;  /* PA5 (placeholder; see header) */
    state->led_on = 0;
    state->button_pressed = 0;
    chip->ops = &led_buttons_ops;
    chip->name = "led_buttons";
    chip->state = state;
}

void led_buttons_press(struct led_buttons_state *state, int down) {
    state->button_pressed = down ? 1 : 0;
    if (state->via) {
        via_6522_set_porta_input_bit(state->via, state->button_pa_mask, down ? 1 : 0);
    }
}

int led_buttons_led(const struct led_buttons_state *state)    { return state->led_on; }
int led_buttons_button(const struct led_buttons_state *state) { return state->button_pressed; }

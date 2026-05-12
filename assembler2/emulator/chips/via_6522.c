#include "via_6522.h"

#include <stddef.h>
#include <string.h>

/* Recompute the bank-config bits PB0..PB4 drive to the PLD. PB pin
 * value = (orb & ddrb) | (input & ~ddrb); the input side is pulled
 * down on the wendy2c, so floats read as 0. */
static void update_bank_config(struct via_6522_state *s, struct bus *bus) {
    bus->bank_config = (uint8_t)((s->orb & s->ddrb) & 0x1F);
}

/* Update the IRQ output line based on (IFR & IER). IFR bit 7 is set
 * when any other (IFR & IER) bit is set. */
static void update_irq(struct via_6522_state *s, struct bus *bus) {
    uint8_t pending = s->ifr & s->ier & 0x7F;
    if (pending) s->ifr |= 0x80;
    else         s->ifr &= 0x7F;
    bus->irq = pending ? 1 : 0;
}

/* Set or clear an IFR bit and refresh IRQ. */
static void via_set_ifr(struct via_6522_state *s, struct bus *bus, uint8_t mask) {
    s->ifr |= mask;
    update_irq(s, bus);
}
static void via_clear_ifr(struct via_6522_state *s, struct bus *bus, uint8_t mask) {
    s->ifr &= (uint8_t)~mask;
    update_irq(s, bus);
}

/* PORTB pin value: bits driven by output (DDR=1) come from ORB; bits
 * with DDR=0 read as 0 (pull-downs on PB0..4; PB6/7 are LED/T1 with
 * no pull). PB7 is overridden by T1 squarewave when ACR_T1_OUT set. */
static uint8_t portb_pin_value(const struct via_6522_state *s) {
    uint8_t v = s->orb & s->ddrb;
    if (s->acr & VIA_ACR_T1_OUT) {
        v = (uint8_t)((v & 0x7F) | (s->pb7 ? 0x80 : 0));
    }
    return v;
}

/* PORTA pin value: same model. */
static uint8_t porta_pin_value(const struct via_6522_state *s) {
    return (uint8_t)(s->ora & s->ddra);
}

static bool via_6522_read(struct chip *self, struct bus *bus,
                          uint16_t addr, uint8_t *out) {
    if (!bus->viacs) return false;
    struct via_6522_state *s = (struct via_6522_state *)self->state;
    uint8_t reg = (uint8_t)(addr & 0xF);
    switch (reg) {
        case VIA_REG_ORB:
            *out = portb_pin_value(s);
            /* Reading ORB clears CB1/CB2 IFR (when in interrupt
             * input mode); for our wendy2c usage we leave them be -- the
             * upload-and-run code clears CB2 explicitly via IFR write. */
            return true;
        case VIA_REG_ORA:
        case VIA_REG_ORANH:
            *out = porta_pin_value(s);
            return true;
        case VIA_REG_DDRB: *out = s->ddrb; return true;
        case VIA_REG_DDRA: *out = s->ddra; return true;
        case VIA_REG_T1CL:
            *out = (uint8_t)(s->t1c & 0xFF);
            via_clear_ifr(s, bus, VIA_INT_T1);
            return true;
        case VIA_REG_T1CH:
            *out = (uint8_t)((s->t1c >> 8) & 0xFF);
            return true;
        case VIA_REG_T1LL: *out = (uint8_t)(s->t1l & 0xFF); return true;
        case VIA_REG_T1LH: *out = (uint8_t)((s->t1l >> 8) & 0xFF); return true;
        case VIA_REG_T2CL:
            *out = (uint8_t)(s->t2c & 0xFF);
            via_clear_ifr(s, bus, VIA_INT_T2);
            return true;
        case VIA_REG_T2CH:
            *out = (uint8_t)((s->t2c >> 8) & 0xFF);
            return true;
        case VIA_REG_SR:
            *out = s->sr;
            via_clear_ifr(s, bus, VIA_INT_SR);
            /* Reading SR while in shift-in-T2 mode primes the shift
             * register for the next 8 bits. The wendy2c ISR reads SR
             * right after enabling SR_IN_T2 to start each byte. */
            if ((s->acr & VIA_ACR_SR_MODE) == VIA_ACR_SR_IN_T2) {
                s->sr_bits_remaining = 8;
            }
            return true;
        case VIA_REG_ACR: *out = s->acr; return true;
        case VIA_REG_PCR: *out = s->pcr; return true;
        case VIA_REG_IFR: *out = s->ifr; return true;
        case VIA_REG_IER: *out = (uint8_t)(s->ier | 0x80); return true;
    }
    return true;
}

static bool via_6522_write(struct chip *self, struct bus *bus,
                           uint16_t addr, uint8_t data) {
    if (!bus->viacs) return false;
    struct via_6522_state *s = (struct via_6522_state *)self->state;
    uint8_t reg = (uint8_t)(addr & 0xF);
    switch (reg) {
        case VIA_REG_ORB:
            s->orb = data;
            update_bank_config(s, bus);
            return true;
        case VIA_REG_ORA:
        case VIA_REG_ORANH:
            s->ora = data;
            return true;
        case VIA_REG_DDRB:
            s->ddrb = data;
            update_bank_config(s, bus);
            return true;
        case VIA_REG_DDRA:
            s->ddra = data;
            return true;
        case VIA_REG_T1CL:
        case VIA_REG_T1LL:
            s->t1l = (uint16_t)((s->t1l & 0xFF00) | data);
            return true;
        case VIA_REG_T1CH:
            s->t1l = (uint16_t)((s->t1l & 0x00FF) | ((uint16_t)data << 8));
            s->t1c = s->t1l;
            s->t1_running = 1;
            via_clear_ifr(s, bus, VIA_INT_T1);
            if (s->acr & VIA_ACR_T1_OUT) s->pb7 = 0;  /* PB7 starts low */
            return true;
        case VIA_REG_T1LH:
            s->t1l = (uint16_t)((s->t1l & 0x00FF) | ((uint16_t)data << 8));
            via_clear_ifr(s, bus, VIA_INT_T1);
            return true;
        case VIA_REG_T2CL:
            s->t2l_lo = data;
            return true;
        case VIA_REG_T2CH:
            s->t2c = (uint16_t)(s->t2l_lo | ((uint16_t)data << 8));
            s->t2_running = 1;
            via_clear_ifr(s, bus, VIA_INT_T2);
            return true;
        case VIA_REG_SR:
            s->sr = data;
            via_clear_ifr(s, bus, VIA_INT_SR);
            return true;
        case VIA_REG_ACR: s->acr = data; return true;
        case VIA_REG_PCR: s->pcr = data; return true;
        case VIA_REG_IFR:
            /* Writing 1 to a bit clears that IFR bit. */
            s->ifr &= (uint8_t)~(data & 0x7F);
            update_irq(s, bus);
            return true;
        case VIA_REG_IER:
            if (data & 0x80) s->ier |= (uint8_t)(data & 0x7F);
            else             s->ier &= (uint8_t)~(data & 0x7F);
            update_irq(s, bus);
            return true;
    }
    return true;
}

static void via_6522_tick(struct chip *self, struct bus *bus) {
    struct via_6522_state *s = (struct via_6522_state *)self->state;

    /* T1/T2 count on phi2 cycles, not OSC ticks. The clock_22v10
     * sets bus->cpu_cycle_due on each CK falling edge (= phi2 edge);
     * we gate the timer decrements on that signal so the on-target
     * bit-timing matches the real wendy2c boot ROM's T2 expectations.
     * (We do NOT clear cpu_cycle_due here -- the CPU chip ticks
     * after us and consumes it.) */
    if (!bus->cpu_cycle_due) return;
    if (s->t1_running) {
        if (s->t1c == 0) {
            via_set_ifr(s, bus, VIA_INT_T1);
            if (s->acr & VIA_ACR_T1_CONT) {
                s->t1c = s->t1l;
                if (s->acr & VIA_ACR_T1_OUT) s->pb7 ^= 1;
            } else {
                s->t1_running = 0;
            }
        } else {
            s->t1c--;
        }
    }

    /* T2: one-shot timer that keeps counting after underflow (per
     * 6522 datasheet -- "after the timer has reached zero, it will
     * continue to decrement"). In SR-IN-T2 mode, each underflow also
     * shifts cb2_in into SR (when sr_bits_remaining > 0) and reloads
     * T2 from the low-byte latch for the next bit-time. */
    if (s->t2_running) {
        if (s->t2c == 0) {
            via_set_ifr(s, bus, VIA_INT_T2);
            if ((s->acr & VIA_ACR_SR_MODE) == VIA_ACR_SR_IN_T2 &&
                s->sr_bits_remaining > 0) {
                s->sr = (uint8_t)((s->sr << 1) | (s->cb2_in & 1));
                s->sr_bits_remaining--;
                if (s->sr_bits_remaining == 0) {
                    via_set_ifr(s, bus, VIA_INT_SR);
                }
                s->t2c = s->t2l_lo;  /* reload for next bit */
            } else {
                s->t2c = 0xFFFF;  /* free-run wrap */
            }
        } else {
            s->t2c--;
        }
    }
}

static void via_6522_reset(struct chip *self) {
    struct via_6522_state *s = (struct via_6522_state *)self->state;
    memset(s, 0, sizeof(*s));
}

void via_6522_init(struct chip *chip, struct via_6522_state *state) {
    static const struct chip_ops ops = {
        .tick  = via_6522_tick,
        .read  = via_6522_read,
        .write = via_6522_write,
        .reset = via_6522_reset,
    };
    memset(state, 0, sizeof(*state));
    chip->ops = &ops;
    chip->name = "via_6522";
    chip->state = state;
}

void via_6522_set_cb2(struct via_6522_state *s, struct bus *bus, uint8_t bit) {
    uint8_t prev = s->cb2_in;
    s->cb2_in = bit ? 1 : 0;

    /* CB2 edge detection per PCR bits 5-7. */
    uint8_t cb2_mode = s->pcr & VIA_PCR_CB2_MASK;
    if (cb2_mode == VIA_PCR_CB2_IND_NEG_E ||
        (s->pcr & 0xC0) == 0x00 /* CB2 input neg edge non-independent */) {
        if (prev && !s->cb2_in) {
            via_set_ifr(s, bus, VIA_INT_CB2);
            /* Arm the SR for an 8-bit read on next T2 underflows. */
            if ((s->acr & VIA_ACR_SR_MODE) == VIA_ACR_SR_IN_T2) {
                s->sr_bits_remaining = 8;
            }
        }
    }
    /* Positive edges, handshake/pulse modes -- not modeled (not used
     * by the wendy2c upload path). */
}

void via_6522_set_cb2_quiet(struct via_6522_state *s, uint8_t bit) {
    s->cb2_in = bit ? 1 : 0;
}

uint8_t via_6522_get_pb7(const struct via_6522_state *s) { return s->pb7; }
uint16_t via_6522_get_t1c(const struct via_6522_state *s) { return s->t1c; }
uint8_t via_6522_porta_pins(const struct via_6522_state *s) { return porta_pin_value(s); }
uint8_t via_6522_portb_pins(const struct via_6522_state *s) { return portb_pin_value(s); }
uint8_t via_6522_sr_bits_remaining(const struct via_6522_state *s) { return s->sr_bits_remaining; }
uint8_t via_6522_ifr(const struct via_6522_state *s) { return s->ifr; }
uint8_t via_6522_ier(const struct via_6522_state *s) { return s->ier; }

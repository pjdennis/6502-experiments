#include "syscall_ports.h"

#include "../file_io.h"

#include <stdio.h>
#include <string.h>

/* The chip claims $F800-$F80F and is registered ahead of the RAM chip, so a
 * read/write to those addresses is handled here and never reaches RAM. All
 * other addresses fall through (read/write return false). */

static void name_reset(struct syscall_ports_state *s) {
    s->namelen = 0;
    s->namebuf[0] = '\0';
}

static bool syscall_ports_read(struct chip *self, struct bus *bus,
                               uint16_t addr, uint8_t *data_out) {
    (void)bus;
    if (addr < SYSCALL_PORTS_BASE || addr > SYSCALL_PORTS_TOP) return false;
    struct syscall_ports_state *s = (struct syscall_ports_state *)self->state;
    switch (addr) {
    case 0xF802: {                          /* open-for-read -> handle */
        s->namebuf[s->namelen] = '\0';
        uint8_t h = file_open(s->namebuf);
        name_reset(s);
        s->current_handle = h;
        *data_out = h;
        return true;
    }
    case 0xF803: {                          /* open-for-write -> handle */
        s->namebuf[s->namelen] = '\0';
        uint8_t h = file_open_for_write(s->namebuf);
        name_reset(s);
        s->current_handle = h;
        *data_out = h;
        return true;
    }
    case 0xF805: {                          /* read byte from current handle */
        if (s->current_handle < 2) { *data_out = 0; return true; }
        int b = file_read(s->current_handle);
        *data_out = (b == EOF) ? 0 : (uint8_t)b;
        return true;
    }
    case 0xF806: {                          /* EOF of current handle */
        *data_out = 0;
        if (s->current_handle >= 2) {
            FILE *f = file_handle(s->current_handle);
            if (f) {
                int b = fgetc(f);
                if (b == EOF) *data_out = 0x80;
                else ungetc(b, f);
            }
        }
        return true;
    }
    default:
        *data_out = 0;                      /* unused read ports read as 0 */
        return true;
    }
}

static bool syscall_ports_write(struct chip *self, struct bus *bus,
                                uint16_t addr, uint8_t data) {
    (void)bus;
    if (addr < SYSCALL_PORTS_BASE || addr > SYSCALL_PORTS_TOP) return false;
    struct syscall_ports_state *s = (struct syscall_ports_state *)self->state;
    switch (addr) {
    case 0xF800:                            /* append filename byte */
        if (s->namelen < (int)sizeof(s->namebuf) - 1)
            s->namebuf[s->namelen++] = (char)data;
        return true;
    case 0xF801:                            /* clear filename buffer */
        name_reset(s);
        return true;
    case 0xF804:                            /* select current handle */
        s->current_handle = data;
        return true;
    case 0xF807:                            /* write byte to current handle */
        if (s->current_handle >= 2)
            file_write(s->current_handle, data);
        return true;
    case 0xF808:                            /* close current handle */
        if (s->current_handle >= 2)
            file_close(s->current_handle);
        s->current_handle = 0;
        return true;
    case 0xF80F:                            /* power off / halt */
        s->poweroff = 1;
        s->poweroff_code = data;
        return true;
    default:
        return true;                        /* swallow unused write ports */
    }
}

void syscall_ports_init(struct chip *chip, struct syscall_ports_state *state) {
    static const struct chip_ops ops = {
        .tick  = NULL,
        .read  = syscall_ports_read,
        .write = syscall_ports_write,
        .reset = NULL,
    };
    memset(state, 0, sizeof(*state));
    chip->ops = &ops;
    chip->name = "syscall_ports";
    chip->state = state;
}

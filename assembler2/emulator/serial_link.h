#ifndef EMULATOR_SERIAL_LINK_H
#define EMULATOR_SERIAL_LINK_H

#include <stdint.h>

/* Host-driven wire-level serial link for wendy2c.
 *
 * The emulator opens a Unix-domain socket; a Python client connects
 * and drives CB2 (the wendy2c serial RX line) at bit-level resolution.
 * The wire protocol has no notion of UART framing: it just specifies
 * line transitions and emulated-time waits. The client decides what
 * baud / start / stop bits / parity to use.
 *
 * Why the emulator stays dumb:
 *   - Any framing decision (baud, parity, lsb-first vs msb-first,
 *     deliberate glitches) lives entirely on the client side.
 *   - The emulator can be tested for framing-error tolerance without
 *     ever changing its code.
 *
 * Wire protocol (binary, little-endian; client -> emulator):
 *   0x01 + u64 ns     CB2 LOW,  then consume N ns of emulated time
 *   0x02 + u64 ns     CB2 HIGH, then consume N ns of emulated time
 *   0x03 + u64 ns     no line change, consume N ns
 *   0x10              RESET assert  (set bus->res=1; pulse stays asserted
 *                                    until matching deassert)
 *   0x11              RESET deassert
 *   0x20              PING (emulator echoes 0x20 back)
 *   0x30              TX START -- begin a timing-locked region. The
 *                                 run loop must NOT advance OSC past
 *                                 the current command's expiration if
 *                                 no follow-up command is queued.
 *   0x31              TX END -- back to free-running.
 *
 * Server -> client: only echoes 0x20 (pong). All other side effects
 * happen on the emulated bus.
 */

#define SERIAL_LINK_OP_LOW          0x01
#define SERIAL_LINK_OP_HIGH         0x02
#define SERIAL_LINK_OP_DELAY        0x03
#define SERIAL_LINK_OP_RESET_ON     0x10
#define SERIAL_LINK_OP_RESET_OFF    0x11
#define SERIAL_LINK_OP_PING         0x20
#define SERIAL_LINK_OP_TX_START     0x30
#define SERIAL_LINK_OP_TX_END       0x31

struct via_6522_state;
struct bus;

struct serial_link;

/* Open the listening socket at `path` (Unix domain). Caches `osc_per_us`
 * (typically 19.44 for wendy2c) for ns -> OSC-tick conversion. Returns
 * NULL on error (diagnostic printed to stderr). */
struct serial_link *serial_link_start(const char *path, double osc_per_us);

/* Accept any new connections, parse pending commands from the client,
 * apply line-level / reset side effects. `osc_now` is b->osc_ticks at
 * call time -- the link uses it to figure out when the current
 * command's duration has expired (and the next command can be read).
 * Idempotent / cheap on the fast path (no client connected). */
void serial_link_poll(struct serial_link *l,
                     uint64_t osc_now,
                     struct bus *bus,
                     struct via_6522_state *via);

/* Returns 1 if the run loop must stall: a TX is active, the current
 * commanded duration has expired, and no follow-up command is in the
 * recv buffer. In stall the caller should break out of the bus_step
 * batch, do a brief select() on serial_link_fd(), then re-poll. */
int serial_link_should_stall(const struct serial_link *l, uint64_t osc_now);

/* Returns 1 if the bus_step inner loop should pause to re-poll the
 * link: a TX is active and we've crossed the current commanded
 * duration boundary. Cheaper than serial_link_should_stall (just a
 * comparison) so it's safe to call every bus_step. The caller polls
 * the link, and then if should_stall is true, does the select-wait
 * dance; otherwise the next command's duration has been loaded and
 * the run loop resumes. */
int serial_link_needs_repoll(const struct serial_link *l, uint64_t osc_now);

/* fd to select() on while stalled. -1 if no client / no link. */
int serial_link_client_fd(const struct serial_link *l);

/* Returns 1 if a client is connected, 0 otherwise. */
int serial_link_has_client(const struct serial_link *l);

/* Tear down: close client (if any), close listening socket, unlink the
 * socket path. Idempotent. */
void serial_link_stop(struct serial_link *l);

#endif

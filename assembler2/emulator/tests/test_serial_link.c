/* serial_link.c unit tests.
 *
 * Spin up the link on a Unix socket, connect a client, send wire-
 * protocol commands, and verify the link's effects on the emulated
 * bus + VIA. Each test uses a fresh socket path so parallel runs
 * don't collide. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#include "greatest.h"
#include "../bus.h"
#include "../chips/via_6522.h"
#include "../serial_link.h"

static struct via_6522_state vs;
static struct chip vch;
static struct bus bus_;

static const double OSC_PER_US = 19.44;  /* wendy2c default */

static void setup(void) {
    via_6522_init(&vch, &vs);
    bus_init(&bus_);
    bus_add_chip(&bus_, &vch);
    bus_.viacs = 1;
    /* Match the wendy2c boot ROM's CB2-edge config so falling edges
     * arm the SR (when ACR is SR_IN_T2). */
    bus_write(&bus_, 0xF00C, VIA_PCR_CB2_IND_NEG_E);
}

/* Pick a unique-enough socket path for this test process. */
static void make_sock_path(char *out, size_t n, const char *tag) {
    snprintf(out, n, "/tmp/test_serial_link_%d_%s.sock", (int)getpid(), tag);
    unlink(out);
}

/* Connect a client to the link's listening socket. Returns the
 * client-side fd, or -1 on failure. */
static int client_connect(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    return fd;
}

/* Send raw bytes to the link. Returns 0 on success. */
static int send_bytes(int fd, const void *p, size_t n) {
    ssize_t w = send(fd, p, n, 0);
    return (w == (ssize_t)n) ? 0 : -1;
}

/* Build an OP_LOW/OP_HIGH/OP_DELAY command (9 bytes). */
static void build_timed(uint8_t *out, uint8_t op, uint64_t ns) {
    out[0] = op;
    for (int i = 0; i < 8; i++) out[1 + i] = (uint8_t)((ns >> (i * 8)) & 0xFF);
}

TEST start_creates_socket_and_stop_cleans_up(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "lifecycle");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    ASSERT(l != NULL);
    ASSERT_EQ_FMT(-1, serial_link_client_fd(l), "%d");
    ASSERT_EQ_FMT(0, serial_link_has_client(l), "%d");
    /* Path should exist after start. */
    ASSERT_EQ_FMT(0, access(path, F_OK), "%d");
    serial_link_stop(l);
    /* And be cleaned up. */
    ASSERT(access(path, F_OK) != 0);
    PASS();
}

TEST start_rejects_zero_osc(void) {
    char path[128];
    make_sock_path(path, sizeof(path), "badosc");
    ASSERT(serial_link_start(path, 0.0) == NULL);
    ASSERT(serial_link_start(path, -1.0) == NULL);
    PASS();
}

TEST accepts_client_on_poll(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "accept");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT(1, serial_link_has_client(l), "%d");
    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST reset_on_off_drives_bus_res(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "reset");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    uint8_t ops[2] = { SERIAL_LINK_OP_RESET_ON, SERIAL_LINK_OP_RESET_OFF };
    ASSERT_EQ_FMT(0, send_bytes(cfd, ops, 1), "%d");
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)1, bus_.res, "%u");

    ASSERT_EQ_FMT(0, send_bytes(cfd, ops + 1, 1), "%d");
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)0, bus_.res, "%u");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST low_high_set_cb2_immediately(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "cb2");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    uint8_t cmd[9];
    build_timed(cmd, SERIAL_LINK_OP_HIGH, 0);
    ASSERT_EQ_FMT(0, send_bytes(cfd, cmd, 9), "%d");
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)1, vs.cb2_in, "%u");
    /* Falling edge fires IFR.CB2 in the PCR_CB2_IND_NEG_E mode set by
     * setup(). */
    build_timed(cmd, SERIAL_LINK_OP_LOW, 0);
    ASSERT_EQ_FMT(0, send_bytes(cfd, cmd, 9), "%d");
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)0, vs.cb2_in, "%u");
    ASSERT(vs.ifr & VIA_INT_CB2);

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST delay_blocks_next_command_until_unblock(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "delay");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    /* HIGH @ 0 ns + DELAY 1000 ns + LOW @ 0 ns. With osc_per_us=19.44,
     * 1000 ns = 19.44 OSC ticks -> rounds to 19. */
    uint8_t buf[27];
    build_timed(buf + 0,  SERIAL_LINK_OP_HIGH,  0);
    build_timed(buf + 9,  SERIAL_LINK_OP_DELAY, 1000);
    build_timed(buf + 18, SERIAL_LINK_OP_LOW,   0);
    ASSERT_EQ_FMT(0, send_bytes(cfd, buf, sizeof(buf)), "%d");

    /* Poll at t=0: HIGH applies (CB2=1), DELAY arms unblock=19. */
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)1, vs.cb2_in, "%u");

    /* Poll at t=10 (< 19): the LOW should NOT yet apply -- still inside
     * the delay window. */
    serial_link_poll(l, 10, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)1, vs.cb2_in, "%u");

    /* Poll at t=25 (>= 19): now the LOW applies. */
    serial_link_poll(l, 25, &bus_, &vs);
    ASSERT_EQ_FMT((uint8_t)0, vs.cb2_in, "%u");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST ping_echoes_pong(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "ping");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    uint8_t op = SERIAL_LINK_OP_PING;
    ASSERT_EQ_FMT(0, send_bytes(cfd, &op, 1), "%d");
    serial_link_poll(l, 0, &bus_, &vs);

    /* Drain the pong. */
    uint8_t pong = 0;
    ssize_t r = recv(cfd, &pong, 1, 0);
    ASSERT_EQ_FMT((ssize_t)1, r, "%zd");
    ASSERT_EQ_FMT((uint8_t)SERIAL_LINK_OP_PING, pong, "%02X");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST tx_brackets_control_should_stall(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "tx");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    /* Outside TX: never stalls regardless of buffer state. */
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT(0, serial_link_should_stall(l, 0), "%d");

    /* Enter TX with a 100-ns LOW pulse + TX_END (no follow-up). */
    uint8_t buf[19];
    buf[0] = SERIAL_LINK_OP_TX_START;
    build_timed(buf + 1,  SERIAL_LINK_OP_LOW, 100);
    buf[10] = SERIAL_LINK_OP_TX_END;
    ASSERT_EQ_FMT(0, send_bytes(cfd, buf, 11), "%d");

    /* Poll at t=0: TX_START + LOW (arms unblock at ~1.94 ticks).
     * Buffer drains to TX_END. After TX_END, in_tx clears. */
    serial_link_poll(l, 0, &bus_, &vs);
    /* No stall now -- TX_END consumed in_tx. */
    ASSERT_EQ_FMT(0, serial_link_should_stall(l, 0), "%d");

    /* Try a sequence where TX is still active and buffer empty after
     * delay expires. Send TX_START + DELAY 100 + (no end). */
    uint8_t buf2[10];
    buf2[0] = SERIAL_LINK_OP_TX_START;
    build_timed(buf2 + 1, SERIAL_LINK_OP_DELAY, 100);
    ASSERT_EQ_FMT(0, send_bytes(cfd, buf2, 10), "%d");
    serial_link_poll(l, 100, &bus_, &vs);  /* osc_now = 100 to consume both ops */
    /* Now in_tx=1, has_unblock=1, unblock at ~100+1.94=~102, osc_now=100. */
    /* Advance osc_now past unblock; buffer empty; should stall. */
    int stall = serial_link_should_stall(l, 200);
    ASSERT_EQ_FMT(1, stall, "%d");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST needs_repoll_triggers_when_command_expires(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "repoll");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    /* TX_START + HIGH 100ns + LOW 100ns: two timed commands. The first
     * pulls CB2 high and arms an unblock at osc_now + ~1.94 ticks. */
    uint8_t buf[19];
    buf[0] = SERIAL_LINK_OP_TX_START;
    build_timed(buf + 1,  SERIAL_LINK_OP_HIGH, 100);
    build_timed(buf + 10, SERIAL_LINK_OP_LOW, 100);
    ASSERT_EQ_FMT(0, send_bytes(cfd, buf, sizeof(buf)), "%d");

    /* Poll at t=0: TX_START + HIGH apply. unblock_at_osc ~= 2.
     * needs_repoll(0) should be false (haven't crossed it yet). */
    serial_link_poll(l, 0, &bus_, &vs);
    ASSERT_EQ_FMT(0, serial_link_needs_repoll(l, 0), "%d");

    /* needs_repoll(100): crossed. Should fire. */
    ASSERT_EQ_FMT(1, serial_link_needs_repoll(l, 100), "%d");
    /* But should_stall(100) is false because the next command (LOW) is
     * already queued. */
    ASSERT_EQ_FMT(0, serial_link_should_stall(l, 100), "%d");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

TEST disconnect_clears_in_tx_and_unblock(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "disco");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    /* Enter TX, send a long-delay LOW, then drop the client. */
    uint8_t buf[10];
    buf[0] = SERIAL_LINK_OP_TX_START;
    build_timed(buf + 1, SERIAL_LINK_OP_LOW, 1000000);  /* 1 ms = ~19440 ticks */
    ASSERT_EQ_FMT(0, send_bytes(cfd, buf, sizeof(buf)), "%d");
    serial_link_poll(l, 0, &bus_, &vs);
    /* During the 1 ms LOW, well before unblock: not stalled. */
    ASSERT_EQ_FMT(0, serial_link_should_stall(l, 0), "%d");
    /* Past unblock with no follow-up: would stall (if client still
     * connected). */
    ASSERT_EQ_FMT(1, serial_link_should_stall(l, 100000000), "%d");

    close(cfd);
    /* Drive another poll so the link notices the client is gone. */
    serial_link_poll(l, 0, &bus_, &vs);
    /* No client now: should_stall and needs_repoll must both return 0
     * so the emulator doesn't stall waiting on a dead socket. */
    ASSERT_EQ_FMT(0, serial_link_should_stall(l, 100000000), "%d");
    ASSERT_EQ_FMT(0, serial_link_needs_repoll(l, 100000000), "%d");
    ASSERT_EQ_FMT(0, serial_link_has_client(l), "%d");

    serial_link_stop(l);
    PASS();
}

TEST unknown_opcode_drops_client(void) {
    setup();
    char path[128];
    make_sock_path(path, sizeof(path), "unknown");
    struct serial_link *l = serial_link_start(path, OSC_PER_US);
    int cfd = client_connect(path);
    ASSERT(cfd >= 0);

    uint8_t junk = 0x7F;
    ASSERT_EQ_FMT(0, send_bytes(cfd, &junk, 1), "%d");
    serial_link_poll(l, 0, &bus_, &vs);

    /* Client should be dropped. */
    ASSERT_EQ_FMT(0, serial_link_has_client(l), "%d");

    close(cfd);
    serial_link_stop(l);
    PASS();
}

SUITE(serial_link_suite) {
    RUN_TEST(start_creates_socket_and_stop_cleans_up);
    RUN_TEST(start_rejects_zero_osc);
    RUN_TEST(accepts_client_on_poll);
    RUN_TEST(reset_on_off_drives_bus_res);
    RUN_TEST(low_high_set_cb2_immediately);
    RUN_TEST(delay_blocks_next_command_until_unblock);
    RUN_TEST(ping_echoes_pong);
    RUN_TEST(tx_brackets_control_should_stall);
    RUN_TEST(needs_repoll_triggers_when_command_expires);
    RUN_TEST(disconnect_clears_in_tx_and_unblock);
    RUN_TEST(unknown_opcode_drops_client);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(serial_link_suite);
    GREATEST_MAIN_END();
}

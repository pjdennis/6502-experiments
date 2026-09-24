/* wendy2c_web lifecycle smoke test.
 *
 * Primary purpose: give AddressSanitizer something to chew on. Walks
 * the start -> broadcast -> audio-tap -> stop paths repeatedly, plus
 * one shape of an error path (bind-of-a-pinned-port collision). All
 * assertions run under regular `make test`; the leak-detection happens
 * automatically when this is rebuilt under `make sanitizers`. */

#include <stdint.h>
#include <string.h>

#include "greatest.h"
#include "../wendy2c_web.h"

static void fill_snapshot(struct wendy2c_web_snapshot *s) {
    memset(s, 0, sizeof(*s));
    s->lcd_rows = 2;
    s->lcd_cols = 16;
    for (int i = 0; i < s->lcd_rows * s->lcd_cols; i++) s->ddram_visible[i] = 0x20;
    /* Some CGRAM content so the JSON encoder visits the array fully. */
    for (int i = 0; i < 64; i++) s->cgram[i] = (uint8_t)(i & 0x1F);
    s->cursor_row = 0; s->cursor_col = 0;
    s->display_on = 1;
    s->ddra = 0xFF; s->ddrb = 0x3F;
    s->osc_ticks = 12345; s->cpu_cycles = 6172; s->pc = 0x402E;
}

TEST start_stop_cycle_releases_resources(void) {
    /* Bind to an ephemeral port, push a snapshot, queue some audio,
     * shut down. Repeat. The default `make test` only checks that the
     * sequence runs cleanly; the ASan version turns any leaked
     * server-struct allocation into a hard failure at process exit. */
    struct wendy2c_web_snapshot snap;
    fill_snapshot(&snap);

    for (int i = 0; i < 5; i++) {
        struct wendy2c_web_server *srv =
            wendy2c_web_start(0, "127.0.0.1", "emulator/web");
        ASSERT(srv != NULL);
        ASSERT(wendy2c_web_port(srv) > 0);
        ASSERT_EQ_FMT(0, wendy2c_web_client_count(srv), "%d");

        /* No clients connected; broadcasts should be inexpensive
         * no-ops but still walk every code path that touches the
         * JSON buffer. */
        for (int j = 0; j < 4; j++) wendy2c_web_broadcast(srv, &snap);

        /* Audio tap with no clients should also be a no-op and reset
         * the ring. */
        wendy2c_web_send_audio_rate(srv, 22050);
        for (int j = 0; j < 100; j++) {
            wendy2c_web_audio_tap(srv, (int16_t)(j * 100));
        }
        wendy2c_web_flush_audio(srv);

        /* Drain one poll cycle (no events expected). */
        struct wendy2c_web_event evt;
        ASSERT_EQ_FMT(0, wendy2c_web_poll(srv, &evt), "%d");
        ASSERT_EQ_FMT((int)WENDY2C_WEB_EVT_NONE, (int)evt.type, "%d");

        wendy2c_web_stop(srv);
    }
    PASS();
}

TEST stop_null_is_safe(void) {
    /* wendy2c_web_stop and poll guard against NULL so dispatch code
     * can call them unconditionally on the failure path. */
    wendy2c_web_stop(NULL);
    struct wendy2c_web_event evt = { (enum wendy2c_web_event_type)999, 7 };
    ASSERT_EQ_FMT(0, wendy2c_web_poll(NULL, &evt), "%d");
    ASSERT_EQ_FMT((int)WENDY2C_WEB_EVT_NONE, (int)evt.type, "%d");
    PASS();
}

TEST broadcast_without_clients_is_noop(void) {
    /* Edge case: building the JSON snapshot needs to handle the
     * largest LCD geometry (20x4) so the inner sj_printf loop reaches
     * the high end of the ddram_visible array. */
    struct wendy2c_web_server *srv = wendy2c_web_start(0, "127.0.0.1", "emulator/web");
    ASSERT(srv != NULL);

    struct wendy2c_web_snapshot snap;
    fill_snapshot(&snap);
    snap.lcd_rows = 4;
    snap.lcd_cols = 20;
    for (int i = 0; i < 4 * 20; i++) snap.ddram_visible[i] = (uint8_t)('A' + (i % 26));
    wendy2c_web_broadcast(srv, &snap);

    /* And audio_tap with the ring forced to wrap: AUDIO_RING_CAPACITY
     * is 8192 in the implementation; push 10000 samples to exercise
     * the overflow-drops-oldest branch. */
    for (int i = 0; i < 10000; i++) wendy2c_web_audio_tap(srv, (int16_t)i);
    wendy2c_web_flush_audio(srv);  /* no clients -> drops the queue */

    wendy2c_web_stop(srv);
    PASS();
}

SUITE(web_smoke_suite) {
    RUN_TEST(stop_null_is_safe);
    RUN_TEST(start_stop_cycle_releases_resources);
    RUN_TEST(broadcast_without_clients_is_noop);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(web_smoke_suite);
    GREATEST_MAIN_END();
}

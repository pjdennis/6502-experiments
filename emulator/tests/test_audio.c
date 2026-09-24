/* Tests for emulator/audio.c.
 *
 * Covers:
 *   - WAV header is well-formed and the byte-size fields are
 *     fixed up on close so a Ctrl-C'd capture is still a valid file.
 *   - audio_step actually samples PB7 across each audio-sample period
 *     and writes a sample per period.
 *   - The piezo HP filter removes DC: a constant PB7 = 1 settles to
 *     near-zero in the output after a short ramp.
 *   - audio_step is a near-no-op when audio is disabled (no WAV,
 *     no live).
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "greatest.h"
#include "../audio.h"

#define TMP_WAV "emulator/tests/out/audio_test.wav"

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) |
           ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static uint16_t le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1]<<8);
}

static long file_size(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fclose(f);
    return n;
}

static int read_all(const char *path, uint8_t **out, long *n_out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = (uint8_t *)malloc((size_t)n);
    if (!buf) { fclose(f); return -1; }
    if (fread(buf, 1, n, f) != (size_t)n) { fclose(f); free(buf); return -1; }
    fclose(f);
    *out = buf;
    *n_out = n;
    return 0;
}

/* Step audio for a synthetic PB7 trace. `level_fn(t_osc)` returns the
 * PB7 bit at oscillator-tick t_osc. We march osc_ticks by one each
 * call. */
static void run_synth(struct audio_state *a, uint64_t ticks,
                      int (*level_fn)(uint64_t)) {
    for (uint64_t t = 1; t <= ticks; t++) {
        uint8_t pb = (uint8_t)((level_fn(t) & 1) << 7);
        audio_step(a, t, pb);
    }
}

static int level_const_high(uint64_t t) { (void)t; return 1; }
static int level_const_low(uint64_t t)  { (void)t; return 0; }

/* 1 kHz square wave at osc rate of 20 ticks/us:
 *   period = 1000 us = 20000 ticks; half-period = 10000 ticks. */
static int level_1khz(uint64_t t) {
    return ((t / 10000) & 1) ? 1 : 0;
}

TEST wav_header_is_pcm_mono_s16_at_sample_rate(void) {
    struct audio_state a;
    ASSERT_EQ(0, audio_init(&a, 22050, TMP_WAV, 0, 20.0));
    audio_close(&a);

    uint8_t *buf = NULL;
    long n = 0;
    ASSERT_EQ(0, read_all(TMP_WAV, &buf, &n));
    ASSERT(n >= 44);

    /* RIFF header */
    ASSERT_EQ_FMT(0, memcmp(buf, "RIFF", 4), "%d");
    ASSERT_EQ_FMT(0, memcmp(buf + 8, "WAVE", 4), "%d");
    ASSERT_EQ_FMT(0, memcmp(buf + 12, "fmt ", 4), "%d");
    ASSERT_EQ_FMT(16u, le32(buf + 16), "%u");          /* fmt chunk size */
    ASSERT_EQ_FMT(1u,  le16(buf + 20), "%u");          /* PCM */
    ASSERT_EQ_FMT(1u,  le16(buf + 22), "%u");          /* mono */
    ASSERT_EQ_FMT(22050u, le32(buf + 24), "%u");
    ASSERT_EQ_FMT(22050u * 2, le32(buf + 28), "%u");   /* byte rate */
    ASSERT_EQ_FMT(2u,  le16(buf + 32), "%u");          /* block align */
    ASSERT_EQ_FMT(16u, le16(buf + 34), "%u");          /* bits/sample */
    ASSERT_EQ_FMT(0, memcmp(buf + 36, "data", 4), "%d");
    /* No samples written: data size 0, RIFF size 36. */
    ASSERT_EQ_FMT(0u,  le32(buf + 40), "%u");
    ASSERT_EQ_FMT(36u, le32(buf + 4),  "%u");

    free(buf);
    PASS();
}

TEST sample_count_matches_emission_rate(void) {
    /* Run 1 second of emulated time at 20 osc/us. At 22050 Hz audio
     * we should get ~22050 samples (off-by-one ok due to integration). */
    struct audio_state a;
    ASSERT_EQ(0, audio_init(&a, 22050, TMP_WAV, 0, 20.0));
    uint64_t ticks_per_second = 20ull * 1000ull * 1000ull;  /* 20 Mtick */
    run_synth(&a, ticks_per_second, level_1khz);
    uint32_t got = a.wav_samples_written;
    audio_close(&a);

    long n = file_size(TMP_WAV);
    ASSERT(n >= 44);
    long data_bytes = n - 44;
    ASSERT_EQ_FMT((long)got * 2, data_bytes, "%ld");

    /* Allow a wider window since the integrator may carry a few
     * fractional ticks. We expect right around 22050. */
    int delta = (int)got - 22050;
    if (delta < 0) delta = -delta;
    ASSERT(delta <= 2);
    PASS();
}

TEST hp_filter_kills_dc(void) {
    /* PB7 held high forever: integrator yields a constant 1.0 average.
     * After the HP filter, samples should decay toward 0. */
    struct audio_state a;
    ASSERT_EQ(0, audio_init(&a, 22050, TMP_WAV, 0, 20.0));
    /* 1 sec of constant high. */
    run_synth(&a, 20ull * 1000ull * 1000ull, level_const_high);
    audio_close(&a);

    uint8_t *buf = NULL;
    long n = 0;
    ASSERT_EQ(0, read_all(TMP_WAV, &buf, &n));
    ASSERT(n >= 44 + 2);
    long n_samples = (n - 44) / 2;
    ASSERT(n_samples > 100);

    /* First sample: HP filter output for x=1, x_prev=0, y_prev=0:
     * y = alpha * (0 + 1 - 0) = alpha ~ 0.876, scaled by 16384 -> ~14352.
     * Last sample: after a second of constant input, y should have
     * decayed to essentially 0. */
    int16_t first = (int16_t)((uint16_t)buf[44] | ((uint16_t)buf[45] << 8));
    int16_t last  = (int16_t)((uint16_t)buf[n - 2] | ((uint16_t)buf[n - 1] << 8));

    ASSERT(first > 10000);          /* initial step gives a big positive */
    int abs_last = last < 0 ? -last : last;
    ASSERT(abs_last < 50);          /* DC fully suppressed */

    free(buf);
    PASS();
}

TEST disabled_is_noop(void) {
    /* No WAV, no live: enabled stays 0 and audio_step does nothing. */
    struct audio_state a;
    int rc = audio_init(&a, 22050, NULL, 0, 20.0);
    ASSERT_EQ_FMT(0, rc, "%d");
    ASSERT_EQ_FMT(0, a.enabled, "%d");
    run_synth(&a, 100000, level_1khz);
    ASSERT_EQ_FMT(0u, a.wav_samples_written, "%u");
    audio_close(&a);
    PASS();
}

TEST low_pb7_writes_only_dc_signal(void) {
    /* PB7 held LOW: integrator yields constant 0.0. After HP, output
     * should be essentially 0 (no step at startup since input = 0). */
    struct audio_state a;
    ASSERT_EQ(0, audio_init(&a, 22050, TMP_WAV, 0, 20.0));
    run_synth(&a, 200000, level_const_low);  /* ~10 ms of zeros */
    audio_close(&a);

    uint8_t *buf = NULL;
    long n = 0;
    ASSERT_EQ(0, read_all(TMP_WAV, &buf, &n));
    int max_abs = 0;
    for (long i = 44; i + 1 < n; i += 2) {
        int16_t s = (int16_t)((uint16_t)buf[i] | ((uint16_t)buf[i+1] << 8));
        int a_ = s < 0 ? -s : s;
        if (a_ > max_abs) max_abs = a_;
    }
    ASSERT_EQ_FMT(0, max_abs, "%d");
    free(buf);
    PASS();
}

SUITE(audio_suite) {
    RUN_TEST(wav_header_is_pcm_mono_s16_at_sample_rate);
    RUN_TEST(sample_count_matches_emission_rate);
    RUN_TEST(hp_filter_kills_dc);
    RUN_TEST(disabled_is_noop);
    RUN_TEST(low_pb7_writes_only_dc_signal);
}

GREATEST_MAIN_DEFS();
int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(audio_suite);
    GREATEST_MAIN_END();
}

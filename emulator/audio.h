#ifndef EMULATOR_AUDIO_H
#define EMULATOR_AUDIO_H

#include <stdint.h>
#include <stdio.h>

/* Audio output for wendy2c PB7 (T1 squarewave -> piezo speaker).
 *
 * Samples PB7 each bus tick, averages across each audio-sample period
 * (anti-aliasing), passes through a 1st-order high-pass at ~500 Hz
 * that approximates the frequency response of a small piezo (poor
 * low-frequency response, characteristic "tinny" sound), then writes
 * to a WAV file and/or pushes to a miniaudio live-playback device.
 *
 * All output is signed 16-bit PCM mono. Default sample rate 22050 Hz
 * (more than enough for piezo content; halves the cost vs 44.1 kHz). */

#define AUDIO_DEFAULT_SAMPLE_RATE 22050

struct audio_state {
    /* Static config. */
    int sample_rate;
    int enabled;                  /* 1 if at least one of wav/live is on */
    double osc_per_sample;        /* fp ratio: oscillator ticks per audio sample */

    /* PB7 sampling. Each bus tick advances `osc_ticks` by 1; we
     * accumulate level * dt and emit a sample every osc_per_sample
     * ticks worth, then carry over the fractional remainder. */
    uint64_t last_osc;
    double level_accum;
    double time_accum;

    /* Piezo HP filter: y[n] = alpha * (y[n-1] + x[n] - x[n-1]). */
    double hp_alpha;
    double hp_x_prev;
    double hp_y_prev;

    /* WAV file output (NULL if --wav not given). */
    FILE *wav_file;
    uint32_t wav_samples_written;

    /* Live playback state (opaque ma_device + ringbuffer wrapper).
     * NULL if --audio not enabled or init failed. */
    void *live;

    /* Optional sample tap. Installed via audio_set_tap(); fires for
     * every emit_sample() with the post-HP int16. The wendy2c web
     * server uses this to forward samples to connected browsers.
     * NULL = disabled (no per-sample call). */
    void (*tap_cb)(void *user, int16_t sample);
    void *tap_user;
};

/* Initialize audio.
 *   wav_path:    NULL or path; non-NULL opens a WAV file for writing.
 *   enable_live: if non-zero, start a miniaudio device for playback.
 *   osc_per_us:  oscillator ticks per microsecond (20.0 for wendy2c).
 * Returns 0 on success. On any error opening WAV or starting the
 * audio device, prints to stderr and returns non-zero -- the caller
 * may choose to continue with the other output. If both wav_path is
 * NULL and enable_live is 0, `enabled` is left at 0 and audio_step
 * is a no-op (single branch). */
int audio_init(struct audio_state *a,
               int sample_rate,
               const char *wav_path,
               int enable_live,
               double osc_per_us);

/* Install a per-sample tap. Calling this with non-NULL cb forces the
 * audio module's `enabled` flag on, so samples flow through emit_sample
 * even when --wav / --audio were both off (the wendy2c web runner uses
 * this to forward audio to browsers without writing to disk or the host
 * device). Pass cb=NULL to detach. */
void audio_set_tap(struct audio_state *a,
                   void (*cb)(void *user, int16_t sample),
                   void *user);

/* Per-bus-tick hot path. `portb_pins` is via_6522_portb_pins(...),
 * we just need bit 7 (T1 squarewave / piezo line). Designed to be
 * cheap when audio is disabled and amortized-cheap when enabled
 * (most calls are just two adds + a compare). */
void audio_step(struct audio_state *a, uint64_t osc_ticks, uint8_t portb_pins);

/* Tear down: flush the WAV header, stop the audio device, close
 * everything. Idempotent. */
void audio_close(struct audio_state *a);

#endif

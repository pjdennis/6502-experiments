#ifndef EMULATOR_TTY_ALT_SCREEN_H
#define EMULATOR_TTY_ALT_SCREEN_H

/* Save the current terminal mode, switch stdout to the alternate
 * screen buffer, and put stdin into raw mode (cfmakeraw + ISIG so
 * Ctrl-C still raises SIGINT). Idempotent: calling twice without an
 * intervening leave() is a no-op for the second call.
 *
 * Used by --console, --terminal, and the wendy2c --live render mode. */
void tty_alt_screen_enter(void);

/* Restore the original termios (as captured on the first enter()),
 * leave the alternate screen, show the cursor, and reset SGR. After
 * this, a subsequent enter() captures whatever termios is current.
 * Idempotent. */
void tty_alt_screen_leave(void);

/* Returns nonzero between an enter() and the matching leave(). */
int  tty_alt_screen_active(void);

#endif

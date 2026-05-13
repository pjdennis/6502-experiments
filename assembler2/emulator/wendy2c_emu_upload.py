#!/usr/bin/env python3
"""Upload-and-run a payload to a running wendy2c emulator.

Companion to the real-hardware transfer_115200_wendy.py: this version
talks to the emulator's --serial-link Unix socket instead of a tty.
The wire protocol is line-level (CB2 high/low + emulated-time deltas);
this script generates the same UART bit sequence a real serial cable
would produce at 115200 8N1.

Typical flow:

    1. emulator/emulator.out wendy2c_boot.bin --machine wendy2c \\
         --serial-link /tmp/wendy2c-link.sock --cycle-cap 0   # or --live / --web
    2. wendy2c_emu_upload.py /tmp/wendy2c-link.sock payload.bin

The default baud is 230400, not the real-hardware 115200. The emulated
VIA's SR-in-T2 mode shifts on every T2 underflow (T2L+2 CPU cycles =
half a bit-time at 115200 with the wendy2c's 9.72 MHz CPU clock), so to
land one shift per data bit we have to transmit at twice the nominal
rate. Real hardware presumably shifts at the slower full-bit cadence
via CB1 clock cycles. The on-target boot ROM doesn't care either way:
each byte is read out of SR once and bit-reversed via TRANSLATE.

Steps the script runs:
  - Connect to the link socket.
  - Pulse reset (DTR equivalent) so the boot ROM starts clean.
  - Wait for the boot ROM's init to complete (a fixed emulated-time pad
    matching ~50 ms; the real hardware does the same after DTR releases).
  - Frame the payload (little-endian length + payload + BSD checksum,
    same as wendy2_upload.py).
  - Send the framed bytes at 115200 8N1, LSB-first, idle high, with
    the whole burst wrapped in a TX_START/TX_END so the emulator
    holds OSC in lockstep with the bit stream even if it's running
    free.
"""

import argparse
import os
import sys
from pathlib import Path

# Importable as `from wendy2c_emu_link import ...` when this file is
# run from the emulator/ directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wendy2c_emu_link import EmuLink
from wendy2_upload import frame


def upload(sock_path: str,
           payload: bytes,
           baud: int = 230400,
           reset_ns: int = 1_000_000,            # 1 ms reset hold
           post_reset_pad_ns: int = 50_000_000,  # 50 ms boot-ROM init pad
           inter_byte_pad_ns: int = 0,
           verbose: bool = False) -> None:
    framed = frame(payload)
    if verbose:
        print(f"payload={len(payload)} bytes, framed={len(framed)} bytes "
              f"(length + payload + BSD checksum)", file=sys.stderr)

    with EmuLink(sock_path) as link:
        # Make sure both sides see a defined idle level before we
        # touch reset. cb2_high with 0 delay is a one-shot transition.
        link.cb2_high(0)

        # Reset pulse with TX_START/TX_END so the duration is exact
        # even in free-running mode.
        if verbose:
            print(f"reset pulse: {reset_ns} ns", file=sys.stderr)
        link.reset_pulse(reset_ns)

        # Wait for the boot ROM's init to land it in "read CB2 start
        # bit" state. The wendy2c init is a few hundred cycles
        # (display setup, ACR/PCR for SR-in-T2, IER) -- 50 ms of
        # emulated time is comfortably more than that.
        if verbose:
            print(f"post-reset settle: {post_reset_pad_ns} ns",
                  file=sys.stderr)
        with link.transmission():
            link.idle_high(post_reset_pad_ns)

        # Send the framed bytes at the configured baud, wrapped in a
        # transmission so timing is bit-exact regardless of the
        # emulator's clock mode.
        if verbose:
            print(f"sending {len(framed)} bytes at {baud} 8N1",
                  file=sys.stderr)
        with link.transmission():
            for b in framed:
                link.send_uart_byte(b, baud=baud)
                if inter_byte_pad_ns > 0:
                    link.idle_high(inter_byte_pad_ns)
            # Final idle so the LAST stop bit's HIGH level has time
            # to be sampled (an extra bit-time of margin).
            bit_ns = round(1_000_000_000 / baud)
            link.idle_high(bit_ns * 2)

        # Sync: emulator processes everything we sent and pongs back.
        link.ping()
        if verbose:
            print("upload complete", file=sys.stderr)


def main() -> int:
    p = argparse.ArgumentParser(
        description="Upload a payload to a running wendy2c emulator "
                    "via its --serial-link socket.")
    p.add_argument("sock_path", help="path to the emulator's --serial-link "
                                      "Unix socket")
    p.add_argument("payload", help="payload binary to upload")
    p.add_argument("--baud", type=int, default=230400,
                   help="serial baud rate (default 230400; see module "
                        "docstring for why this is 2x the real-hardware "
                        "rate)")
    p.add_argument("--reset-ns", type=int, default=1_000_000,
                   help="reset hold duration in ns (default 1 ms)")
    p.add_argument("--post-reset-ns", type=int, default=50_000_000,
                   help="emulated-time settling delay after reset "
                        "(default 50 ms)")
    p.add_argument("--inter-byte-ns", type=int, default=0,
                   help="optional idle gap between bytes (default 0; "
                        "matches real-hardware pyserial behavior)")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    payload = Path(args.payload).read_bytes()
    upload(args.sock_path, payload,
           baud=args.baud,
           reset_ns=args.reset_ns,
           post_reset_pad_ns=args.post_reset_ns,
           inter_byte_pad_ns=args.inter_byte_ns,
           verbose=args.verbose)
    return 0


if __name__ == "__main__":
    sys.exit(main())

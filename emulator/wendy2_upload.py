#!/usr/bin/env python3
"""Frame a payload binary for the wendy2c upload-and-run protocol.

The wire format the on-target boot ROM (upload_and_run_eeprom_wendy2c.s
+ upload_and_run.inc) expects:

    little-endian 2-byte length
  + payload bytes (length count of them)
  + little-endian 2-byte BSD checksum of the payload

This script writes that framed sequence to a file (or stdout). The
framed file feeds the emulator's --serial-input flag.

In real wendy2 hardware, the equivalent flow is the live serial port
write done by transfer_115200_wendy.py. The on-target code's
TRANSLATE table un-bit-reverses each byte the SR captures, so the
bytes we emit here are interpreted directly (no host-side bit
reversal needed).

Usage:
    python3 wendy2_upload.py PAYLOAD.bin [-o FRAMED.bin]
"""

import argparse
import sys


def bsd_checksum(data: bytes) -> int:
    s = 0
    for b in data:
        s = ((s >> 1) | (s << 15)) & 0xFFFF
        s = (s + b) & 0xFFFF
    return s


def frame(payload: bytes) -> bytes:
    n = len(payload)
    if n > 0xFFFF:
        raise ValueError("payload too large (>= 64 KiB)")
    length = bytes([n & 0xFF, (n >> 8) & 0xFF])
    ck = bsd_checksum(payload)
    ck_b = bytes([ck & 0xFF, (ck >> 8) & 0xFF])
    return length + payload + ck_b


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("payload", help="payload binary to frame")
    p.add_argument("-o", "--output", default=None,
                   help="output framed file (default: PAYLOAD.framed)")
    args = p.parse_args()

    with open(args.payload, "rb") as f:
        payload = f.read()
    framed = frame(payload)

    out = args.output or (args.payload + ".framed")
    with open(out, "wb") as f:
        f.write(framed)

    sys.stderr.write(
        f"wrote {out}: payload={len(payload)} bytes, "
        f"framed={len(framed)} bytes, "
        f"checksum=0x{bsd_checksum(payload):04X}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

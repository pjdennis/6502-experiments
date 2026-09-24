"""Python client for the wendy2c emulator's --serial-link transport.

The emulator opens a Unix-domain socket; this module connects to it
and drives CB2 (the serial RX line) at the bit level, in emulated
time. Time deltas are nanoseconds; the emulator converts to its
oscillator-tick timebase using the wendy2c's 19.44 MHz OSC (or the
--mhz override).

Why nanoseconds and not "send byte X at baud Y": the emulator stays
out of the framing business. This module decides what bits to put on
the wire and when -- the wendy2c boot ROM sees an electrical signal
indistinguishable from a real serial cable. To exercise a different
baud / parity / framing, you change this file; the emulator never
needs to know.

Usage:
    with EmuLink('/tmp/wendy2c-link.sock') as link:
        link.reset_pulse(50_000_000)              # 50 ms reset
        with link.transmission():
            for b in framed_payload:
                link.send_uart_byte(b, baud=115200)
"""

from __future__ import annotations

import socket
import struct
import time
from contextlib import contextmanager
from typing import Iterator


# ===== Wire protocol =====

OP_LOW         = 0x01   # + uint64 ns
OP_HIGH        = 0x02   # + uint64 ns
OP_DELAY       = 0x03   # + uint64 ns
OP_RESET_ON    = 0x10
OP_RESET_OFF   = 0x11
OP_PING        = 0x20
OP_TX_START    = 0x30
OP_TX_END      = 0x31


class EmuLink:
    """A connection to the emulator's --serial-link Unix socket."""

    def __init__(self, sock_path: str, connect_timeout_s: float = 5.0):
        self.sock_path = sock_path
        self.connect_timeout_s = connect_timeout_s
        self._sock: socket.socket | None = None
        # Local-side buffer so a long burst of bits goes out as one
        # send() instead of one syscall per command.
        self._tx: bytearray = bytearray()

    # ----- lifecycle -----

    def connect(self) -> None:
        if self._sock is not None:
            return
        # Wait for the listening socket to appear (the emulator may
        # still be starting). Up to connect_timeout_s.
        deadline = time.monotonic() + self.connect_timeout_s
        last_err = None
        while time.monotonic() < deadline:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(self.sock_path)
                self._sock = s
                return
            except (FileNotFoundError, ConnectionRefusedError) as e:
                last_err = e
                try:
                    s.close()  # type: ignore[has-type]
                except Exception:
                    pass
                time.sleep(0.02)
        raise TimeoutError(
            f"could not connect to {self.sock_path} within "
            f"{self.connect_timeout_s}s: {last_err}"
        )

    def close(self) -> None:
        if self._sock is not None:
            try:
                self.flush()
            except Exception:
                pass
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None

    def __enter__(self) -> "EmuLink":
        self.connect()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # ----- raw send helpers -----

    def _queue(self, data: bytes) -> None:
        self._tx.extend(data)
        # Flush opportunistically so the emulator doesn't starve while
        # we're queuing a long byte sequence. 16 KiB is large enough
        # that the syscall amortizes and small enough that a typical
        # 100-byte upload doesn't fill it.
        if len(self._tx) >= 16384:
            self.flush()

    def flush(self) -> None:
        if not self._tx:
            return
        if self._sock is None:
            raise RuntimeError("EmuLink: not connected")
        self._sock.sendall(bytes(self._tx))
        self._tx.clear()

    # ----- primitive ops -----

    def cb2_low(self, ns: int) -> None:
        """Drive CB2 LOW, then consume `ns` of emulated time."""
        if ns < 0:
            raise ValueError("ns must be non-negative")
        self._queue(bytes([OP_LOW]) + struct.pack("<Q", ns))

    def cb2_high(self, ns: int) -> None:
        """Drive CB2 HIGH, then consume `ns` of emulated time."""
        if ns < 0:
            raise ValueError("ns must be non-negative")
        self._queue(bytes([OP_HIGH]) + struct.pack("<Q", ns))

    def delay(self, ns: int) -> None:
        """Consume `ns` of emulated time without changing the line."""
        if ns < 0:
            raise ValueError("ns must be non-negative")
        self._queue(bytes([OP_DELAY]) + struct.pack("<Q", ns))

    def reset_assert(self) -> None:
        """Pull the emulated reset line low (RES asserted on the bus)."""
        self._queue(bytes([OP_RESET_ON]))

    def reset_deassert(self) -> None:
        """Release the reset line."""
        self._queue(bytes([OP_RESET_OFF]))

    def reset_pulse(self, hold_ns: int) -> None:
        """Bracketed reset pulse: TX_START -> assert -> hold -> deassert -> TX_END.

        The TX brackets ensure the emulator does not advance OSC past
        the hold duration even in free-running mode (important for
        automated tests). hold_ns is measured in emulated time."""
        self.tx_start()
        self.reset_assert()
        self.delay(hold_ns)
        self.reset_deassert()
        self.tx_end()

    def ping(self) -> None:
        """Send PING, wait for the 0x20 pong, returns once it arrives.

        Flushes the pending queue first so any prior commands have
        been applied by the time the pong comes back."""
        if self._sock is None:
            raise RuntimeError("EmuLink: not connected")
        self._queue(bytes([OP_PING]))
        self.flush()
        b = self._sock.recv(1)
        if b != bytes([OP_PING]):
            raise IOError(f"expected pong 0x20, got {b!r}")

    def tx_start(self) -> None:
        """Enter a timing-locked region. The emulator will not advance
        OSC past the current commanded duration while no follow-up
        command is queued."""
        self._queue(bytes([OP_TX_START]))

    def tx_end(self) -> None:
        """Exit the timing-locked region; emulator resumes free pace."""
        self._queue(bytes([OP_TX_END]))

    @contextmanager
    def transmission(self) -> Iterator[None]:
        """Context manager: TX_START/TX_END bracket. Use this around
        timing-critical sequences (e.g. a UART byte stream)."""
        self.tx_start()
        try:
            yield
        finally:
            self.tx_end()
            self.flush()

    # ----- higher-level UART helper -----

    def send_uart_byte(self,
                       byte: int,
                       baud: int,
                       *,
                       start_bits: int = 1,
                       stop_bits: int = 1,
                       lsb_first: bool = True,
                       data_bits: int = 8) -> None:
        """Decompose `byte` into the right cb2_low/cb2_high sequence
        for the given UART framing. Idle is high; start bits are low
        (active-low UART, the universal convention)."""
        if not 0 <= byte <= 0xFF:
            raise ValueError(f"byte out of range: {byte}")
        if data_bits not in (5, 6, 7, 8):
            raise ValueError("data_bits must be 5..8")
        if start_bits < 1 or stop_bits < 1:
            raise ValueError("start_bits / stop_bits must be >= 1")
        if baud <= 0:
            raise ValueError("baud must be positive")

        bit_ns = round(1_000_000_000 / baud)

        # Start bits: LOW for start_bits bit-times.
        self.cb2_low(bit_ns * start_bits)

        # Data bits: LSB-first by default. HIGH for 1, LOW for 0.
        order = range(data_bits) if lsb_first else range(data_bits - 1, -1, -1)
        for i in order:
            if (byte >> i) & 1:
                self.cb2_high(bit_ns)
            else:
                self.cb2_low(bit_ns)

        # Stop bits: HIGH for stop_bits bit-times.
        self.cb2_high(bit_ns * stop_bits)

    def idle_high(self, ns: int) -> None:
        """Park the line high for a span of emulated time (useful for
        inter-byte gaps or post-frame settling). Equivalent to
        cb2_high(ns)."""
        self.cb2_high(ns)


__all__ = ["EmuLink",
           "OP_LOW", "OP_HIGH", "OP_DELAY",
           "OP_RESET_ON", "OP_RESET_OFF",
           "OP_PING", "OP_TX_START", "OP_TX_END"]

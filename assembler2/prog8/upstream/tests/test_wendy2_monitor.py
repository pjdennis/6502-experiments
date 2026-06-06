#!/usr/bin/env python3
"""End-to-end test for the wendy2c MONITOR ROM + simulated SPI disk.

Compiles demos/<name>.p8, stages it on a temp disk with an 'autoexec' that
names it, boots the monitor ROM with --disk (no serial upload), and diffs the
final LCD frame against tests/goldens/<name>.expected.lcd. The monitor loads
the program from disk over the $F800+ file-I/O OS calls.

Skips cleanly if prog8c.jar / 64tass / vasm6502_oldstyle / emulator missing.
"""
from __future__ import annotations
import os, shutil, subprocess, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
UP = HERE.parent
ASM2 = UP.parents[1]
EMU = ASM2 / "emulator" / "emulator.out"
JAR = Path(os.environ.get("PROG8C", "/tmp/prog8c.jar"))
GOLDENS = HERE / "goldens"

CASES = ["d2_autoexec"]   # monitor-loaded demos


def _have():
    if not JAR.exists(): return False, f"prog8c jar not found at {JAR}"
    for t in ("64tass", "vasm6502_oldstyle"):
        if shutil.which(t) is None: return False, f"{t} not on PATH"
    if not EMU.exists(): return False, f"emulator not built at {EMU}"
    return True, ""


def _run(name):
    r = subprocess.run(["bash", str(UP / "wendy2_monitor_run.sh"), f"demos/{name}.p8"],
                       cwd=str(UP), capture_output=True, text=True)
    rows = [ln for ln in r.stdout.splitlines() if ln.startswith("  |") and ln.endswith("|")]
    if not rows:
        raise AssertionError(f"no LCD frame:\n{r.stdout}\n{r.stderr}")
    return "\n".join(rows) + "\n"


_ok, _why = _have()


@unittest.skipUnless(_ok, _why)
class Wendy2MonitorGoldens(unittest.TestCase):
    pass


def _make(name, golden):
    def t(self):
        self.assertEqual(_run(name), golden.read_text(), msg=f"LCD mismatch for {name}")
    return t


for _n in CASES:
    _g = GOLDENS / f"{_n}.expected.lcd"
    if _g.exists() and (UP / "demos" / f"{_n}.p8").exists():
        setattr(Wendy2MonitorGoldens, f"test_{_n}", _make(_n, _g))

if __name__ == "__main__":
    unittest.main(verbosity=2)

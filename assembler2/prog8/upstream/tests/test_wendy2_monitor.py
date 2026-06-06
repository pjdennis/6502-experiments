#!/usr/bin/env python3
"""End-to-end tests for the wendy2c MONITOR ROM + simulated SPI disk.

Compiles program(s) with prog8c (-target wendy2.properties), stages them on a
temp disk alongside an 'autoexec' file, boots the monitor ROM with --disk (no
serial upload), and diffs the final LCD frame against a golden. The monitor
loads each autoexec line's program from disk over the $F800+ file-I/O OS
calls; programs return to the monitor on exit so multiple lines run in turn.

Skips cleanly if prog8c.jar / 64tass / vasm6502_oldstyle / emulator missing.
"""
from __future__ import annotations
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
UP = HERE.parent
ASM2 = UP.parents[1]
REPO = ASM2.parent
EMU = ASM2 / "emulator" / "emulator.out"
JAR = Path(os.environ.get("PROG8C", "/tmp/prog8c.jar"))
MON_SRC = REPO / "wendy2c_monitor.s"
GOLDENS = HERE / "goldens"
OUT = UP / "out"

# golden name -> (autoexec text, {disk filename: demo basename})
CASES = {
    "d2_autoexec": ("d2_autoexec\n", {"d2_autoexec": "d2_autoexec"}),
    "d4_multi":    ("first\nsecond\n", {"first": "d4_first", "second": "d4_second"}),
}


def _have():
    if not JAR.exists():
        return False, f"prog8c jar not found at {JAR}"
    for t in ("64tass", "vasm6502_oldstyle"):
        if shutil.which(t) is None:
            return False, f"{t} not on PATH"
    if not EMU.exists():
        return False, f"emulator not built at {EMU}"
    return True, ""


def _compile(demo: str) -> Path:
    d = OUT / demo
    d.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        ["java", "-jar", str(JAR), "-target", "wendy2.properties", "-out", str(d),
         str(UP / "demos" / f"{demo}.p8")],
        cwd=str(UP), capture_output=True, text=True)
    binp = d / f"{demo}.bin"
    if r.returncode != 0 or not binp.exists():
        raise AssertionError(f"compile {demo} failed:\n{r.stdout}\n{r.stderr}")
    return binp


def _monitor_rom() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    rom = OUT / "wendy2c_monitor.bin"
    r = subprocess.run(
        ["vasm6502_oldstyle", "-wdc02", "-wfail", "-Fbin", "-dotdir",
         "-ignore-mult-inc", "-esc", "-o", str(rom), str(MON_SRC)],
        cwd=str(REPO), capture_output=True, text=True)
    if r.returncode != 0:
        raise AssertionError(f"monitor build failed:\n{r.stdout}\n{r.stderr}")
    return rom


def _run(autoexec: str, files: dict) -> str:
    rom = _monitor_rom()
    disk = Path(tempfile.mkdtemp(prefix="wdisk_mon_"))
    try:
        for diskname, demo in files.items():
            shutil.copy(_compile(demo), disk / diskname)
        (disk / "autoexec").write_text(autoexec)
        r = subprocess.run(
            [str(EMU), str(rom), "--machine", "wendy2c", "--disk", str(disk),
             "--cycle-cap", "6000000"], capture_output=True, text=True)
        rows = [ln for ln in r.stderr.splitlines()
                if ln.startswith("  |") and ln.endswith("|")]
        if not rows:
            raise AssertionError(f"no LCD frame:\n{r.stdout}\n{r.stderr}")
        return "\n".join(rows) + "\n"
    finally:
        shutil.rmtree(disk, ignore_errors=True)


_ok, _why = _have()


@unittest.skipUnless(_ok, _why)
class Wendy2MonitorGoldens(unittest.TestCase):
    pass


def _make(autoexec, files, golden):
    def t(self):
        self.assertEqual(_run(autoexec, files), golden.read_text())
    return t


for _name, (_ax, _files) in CASES.items():
    _g = GOLDENS / f"{_name}.expected.lcd"
    if _g.exists():
        setattr(Wendy2MonitorGoldens, f"test_{_name}", _make(_ax, _files, _g))

if __name__ == "__main__":
    unittest.main(verbosity=2)

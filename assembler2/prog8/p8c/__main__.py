"""p8c command-line driver.

Usage:
    python3 -m p8c source.p8 -o source.s
    python3 -m p8c source.p8 --run [--cycle-cap N] [--show-lcd]

`--run` chains:
    1. compile  source.p8 -> source.s
    2. vasm     source.s   -> source.bin     (assembler -- vasm for Phase 1)
    3. wendy2_upload.py    -> source.framed  (serial-upload framing)
    4. emulator + boot ROM + --serial-input source.framed --cycle-cap N
       (prints the final LCD frame on exit)

Wired against the existing wendy2c boot ROM (upload_and_run_eeprom_wendy2c.s)
so any Prog8 program with %address $4000 lands at the same place as the
hand-written demos.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from .codegen import CodeGenError, generate
from .lex import LexError, lex
from .parse import ParseError, parse
from .sema import SemaError, analyze
from .serialize import serialize


REPO_ROOT = Path(__file__).resolve().parents[3]
ASM2 = REPO_ROOT / "assembler2"
EMULATOR = ASM2 / "emulator" / "emulator.out"
WENDY2_UPLOAD = ASM2 / "emulator" / "wendy2_upload.py"
BOOT_SRC = REPO_ROOT / "upload_and_run_eeprom_wendy2c.s"


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def run_vasm(src: Path, out_bin: Path) -> None:
    """Assemble src -> out_bin using vasm6502_oldstyle.

    Run from REPO_ROOT so the .include paths in the prologue
    (base_config_wendy2c.inc, display_routines_4bit.inc, etc.) resolve.
    """
    r = subprocess.run(
        ["vasm6502_oldstyle", "-wdc02", "-wfail", "-Fbin", "-dotdir",
         "-ignore-mult-inc", "-esc",
         "-o", str(out_bin), str(src)],
        cwd=str(REPO_ROOT), capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.stderr.write(r.stdout)
        sys.stderr.write(r.stderr)
        raise SystemExit(f"vasm failed assembling {src}")


def build_boot_rom(out_dir: Path) -> Path:
    boot_bin = out_dir / "wendy2c_boot.bin"
    if boot_bin.exists():
        return boot_bin
    run_vasm(BOOT_SRC, boot_bin)
    return boot_bin


def frame_payload(payload_bin: Path, framed: Path) -> None:
    r = subprocess.run(
        ["python3", str(WENDY2_UPLOAD), str(payload_bin), "-o", str(framed)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.stderr.write(r.stdout); sys.stderr.write(r.stderr)
        raise SystemExit("framing failed")


def run_on_emulator(boot: Path, framed: Path, cycle_cap: int) -> str:
    r = subprocess.run(
        [str(EMULATOR), str(boot),
         "--machine", "wendy2c",
         "--serial-input", str(framed),
         "--cycle-cap", str(cycle_cap)],
        capture_output=True, text=True,
    )
    # Emulator prints the final LCD frame on stderr.
    return r.stderr


def compile_source(src_path: Path) -> str:
    text = src_path.read_text()
    toks = lex(text, str(src_path))
    prog = parse(toks, str(src_path))
    analyze(prog)
    return generate(prog, str(src_path))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="p8c", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source", help="path to .p8 source")
    p.add_argument("-o", "--output", help="output .s path (default: <source>.s)")
    p.add_argument("--dump-ast", action="store_true",
                   help="parse only and print the canonical AST "
                        "S-expression serialization to stdout (the golden "
                        "the Prog8 on-target parser is diffed against); "
                        "skips sema/codegen")
    p.add_argument("--run", action="store_true",
                   help="compile, assemble, and run on the emulator")
    p.add_argument("--cycle-cap", type=int, default=3_000_000,
                   help="cycle cap when --run (default 3,000,000 osc ticks)")
    p.add_argument("--keep", action="store_true",
                   help="keep intermediate files under /tmp/p8c-out/")
    args = p.parse_args(argv)

    src = Path(args.source).resolve()

    if args.dump_ast:
        # Parser-only path: serialize exactly what parsing yields (no
        # sema, no codegen), matching what the on-target p1 parser emits.
        try:
            prog = parse(lex(src.read_text(), str(src)), str(src))
        except (LexError, ParseError) as e:
            sys.stderr.write(f"p8c: {e}\n")
            return 1
        sys.stdout.write(serialize(prog))
        return 0

    try:
        s_text = compile_source(src)
    except (LexError, ParseError, SemaError, CodeGenError) as e:
        sys.stderr.write(f"p8c: {e}\n")
        return 1

    out_s = Path(args.output).resolve() if args.output else src.with_suffix(".s")
    out_s.write_text(s_text)

    if not args.run:
        return 0

    if not have("vasm6502_oldstyle"):
        sys.stderr.write("p8c: --run needs vasm6502_oldstyle on PATH\n")
        return 1
    if not EMULATOR.exists():
        sys.stderr.write(f"p8c: emulator not built at {EMULATOR}\n")
        return 1

    work = Path("/tmp/p8c-out") / src.stem
    work.mkdir(parents=True, exist_ok=True)
    payload_bin = work / "payload.bin"
    framed = work / "payload.framed"

    run_vasm(out_s, payload_bin)
    boot = build_boot_rom(work)
    frame_payload(payload_bin, framed)
    lcd_text = run_on_emulator(boot, framed, args.cycle_cap)

    sys.stdout.write(lcd_text)
    if not args.keep:
        # Leave the .s file (the user explicitly wrote -o), but clean
        # the intermediates.
        for f in (payload_bin, framed):
            f.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

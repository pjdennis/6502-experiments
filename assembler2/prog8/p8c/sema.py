"""Sema for the Prog8 subset.

Phase 1 jobs:
  * Validate that exactly one `sub main` exists.
  * Resolve dotted call paths (e.g. `txt.print`) against the stdlib
    symbol table; flag unknown calls.
  * Assign string-literal labels and collect them on Program.strings
    so codegen can emit a single .data block.
  * Mangle subroutine names to `p8s_<sub>` (Phase 1: no blocks-as-namespaces
    yet, so `p8s_main` is enough).
"""
from __future__ import annotations

from .ast import (
    Block, BoolLit, Call, ExprStmt, Ident, InlineAsm, IntLit, Program,
    StrLit, Sub, Symbol, UBYTE, UWORD, STR, VOID,
)
from .stdlib_decls import STDLIB_SYMBOLS


class SemaError(Exception):
    pass


class Sema:
    def __init__(self, prog: Program):
        self.prog = prog
        self.globals: dict[str, Symbol] = {}
        self.dotted: dict[tuple[str, ...], Symbol] = {}
        self._next_str_id = 0

    def run(self) -> None:
        # 1. Pull in stdlib declarations for every module that the program
        #    imports. Phase 1 imports are flat: %import txt, %import lcd.
        for mod in self.prog.imports:
            if mod not in STDLIB_SYMBOLS:
                raise SemaError(f"unknown import {mod!r}")
            for sym in STDLIB_SYMBOLS[mod]:
                self.dotted[(mod, sym.name)] = sym

        # 2. Mangle sub names and add to globals.
        seen_main = False
        for s in self.prog.subs:
            s.mangled = f"p8s_{s.name}"
            if s.name in self.globals:
                raise SemaError(f"duplicate sub {s.name!r}")
            self.globals[s.name] = Symbol(
                name=s.name, mangled=s.mangled, type=VOID, kind="sub",
            )
            if s.is_main:
                seen_main = True
        if not seen_main:
            raise SemaError("program has no `main { ... }` or `sub main()`")

        # 3. Walk each sub's body.
        for s in self.prog.subs:
            self._walk_block(s.body)

    def _walk_block(self, blk: Block) -> None:
        for st in blk.stmts:
            self._walk_stmt(st)

    def _walk_stmt(self, st) -> None:
        if isinstance(st, ExprStmt):
            self._walk_expr(st.expr)
        elif isinstance(st, InlineAsm):
            pass
        else:
            raise SemaError(f"sema: unhandled statement {type(st).__name__}")

    def _walk_expr(self, e) -> None:
        if isinstance(e, IntLit):
            # Phase 1: <= 0xFF stays ubyte, otherwise uword.
            e.type = UBYTE if 0 <= e.value <= 0xFF else UWORD
        elif isinstance(e, BoolLit):
            pass
        elif isinstance(e, StrLit):
            e.label = f"p8c_str_{self._next_str_id}"
            self._next_str_id += 1
            self.prog.strings.append(e)
            e.type = STR
        elif isinstance(e, Ident):
            sym = self.globals.get(e.name)
            if sym is None:
                raise SemaError(
                    f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                    f"unknown identifier {e.name!r}"
                )
            e.sym = sym
            e.type = sym.type
        elif isinstance(e, Call):
            key = tuple(e.path)
            sym = self.dotted.get(key)
            if sym is None and len(e.path) == 1:
                sym = self.globals.get(e.path[0])
            if sym is None:
                raise SemaError(
                    f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                    f"unknown call target {'.'.join(e.path)!r}"
                )
            if sym.kind not in ("sub", "asmsub", "extsub", "builtin"):
                raise SemaError(
                    f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                    f"{'.'.join(e.path)!r} is not callable"
                )
            e.sym = sym
            e.type = sym.type
            for a in e.args:
                self._walk_expr(a)
        else:
            raise SemaError(f"sema: unhandled expr {type(e).__name__}")


def analyze(prog: Program) -> None:
    Sema(prog).run()

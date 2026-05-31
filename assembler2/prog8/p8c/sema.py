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
    Assign, BinOp, Block, BoolLit, Break, Call, Continue, ExprStmt, For,
    Ident, If, InlineAsm, IntLit, Param, Program, Repeat, Return, StrLit,
    Sub, Symbol, Type, UnaryOp, VarDecl, While, BOOL, STR, UBYTE, UWORD,
    VOID, type_from_name,
)
from .stdlib_decls import STDLIB_SYMBOLS, get_builtin


class SemaError(Exception):
    pass


# Zero-page reservations:
#   $00..$01  DISPLAY_STRING_PARAM (display_string ABI -- already used by
#             the existing .inc routines, see display_string.inc)
#   $02..$03  COUNTER scratch borrowed by some demos; we leave it alone
#   $04..$1F  spare (room for the existing display_hex_indirect helpers,
#             multi-byte arithmetic temps, etc.)
#   $20..$3F  __p8c_temp0..__p8c_tempN -- compiler-managed scratch
#   $40..$7F  Prog8 user variables (the next 64 bytes)
# The variable allocator starts at $40; codegen reserves three fixed
# scratch bytes at $20/$21/$22 for nested expression temps and loop
# counters.
ZP_VAR_BASE = 0x40
ZP_VAR_TOP = 0x80


class Sema:
    def __init__(self, prog: Program):
        self.prog = prog
        self.globals: dict[str, Symbol] = {}
        self.dotted: dict[tuple[str, ...], Symbol] = {}
        self._next_str_id = 0
        self._zp_next = ZP_VAR_BASE
        # Per-block locals stack -- index 0 is module scope, then per
        # sub. Phase 2 doesn't have nested blocks-as-scopes, so the
        # stack reflects only [module] or [module, sub].
        self._scope_stack: list[dict[str, Symbol]] = []
        # repeat-counter id allocator: each Repeat gets a unique label
        # suffix so nested loops don't collide.
        self._next_repeat_id = 0

    def run(self) -> None:
        # 1. stdlib imports.
        for mod in self.prog.imports:
            if mod not in STDLIB_SYMBOLS:
                raise SemaError(f"unknown import {mod!r}")
            for sym in STDLIB_SYMBOLS[mod]:
                self.dotted[(mod, sym.name)] = sym

        # 2. Module-scope: register sub names + allocate module-var slots.
        seen_main = False
        for s in self.prog.subs:
            s.mangled = f"p8s_{s.name}"
            if s.name in self.globals:
                raise SemaError(f"duplicate sub {s.name!r}")
            ret_t = type_from_name(s.return_type_name)
            if ret_t is None:
                raise SemaError(f"sub {s.name!r}: bad return type "
                                f"{s.return_type_name!r}")
            kind = "asmsub" if s.is_asmsub else "sub"
            asm_target = s.asm_target if s.is_asmsub else None
            self.globals[s.name] = Symbol(
                name=s.name, mangled=s.mangled, type=ret_t, kind=kind,
                asm_target=asm_target,
            )
            if s.is_main:
                seen_main = True
        if not seen_main:
            raise SemaError("program has no `main { ... }` or `sub main()`")

        # Module-level vars (visible to every sub).
        self._scope_stack.append(self.globals)
        for vd in self.prog.module_vars:
            self._declare_var(vd, mangled_prefix="p8v_", scope=self.globals)

        # 3. Per-sub: push a sub-scope, declare params + sub-locals.
        for s in self.prog.subs:
            if s.is_asmsub:
                # asmsubs are pure declarations -- no body to walk.
                continue
            sub_scope: dict[str, Symbol] = {}
            self._scope_stack.append(sub_scope)
            # Params first: each becomes a ZP byte/word that the caller
            # populates before JSR.
            for p in s.params:
                pt = type_from_name(p.type_name)
                if pt is None or pt not in (UBYTE, UWORD):
                    raise SemaError(
                        f"{p.loc.file}:{p.loc.line}:{p.loc.col}: "
                        f"param type {p.type_name!r} not supported"
                    )
                size = 1 if pt is UBYTE else 2
                mangled = f"p8v_{s.name}_arg_{p.name}"
                sym = Symbol(name=p.name, mangled=mangled, type=pt,
                             kind="var", address=self._zp_next)
                self._zp_next += size
                sub_scope[p.name] = sym
                p.sym = sym
                self.prog.all_vars.append(sym)
            # Remember current sub for `return` typechecking.
            self._current_sub = s
            self._walk_block(s.body, sub_name=s.name)
            self._current_sub = None
            self._scope_stack.pop()

        self._scope_stack.pop()

    # ---- declaration / scope ----

    def _lookup(self, name: str) -> Symbol | None:
        for scope in reversed(self._scope_stack):
            if name in scope:
                return scope[name]
        return None

    def _declare_var(self, vd: VarDecl, mangled_prefix: str,
                     scope: dict[str, Symbol]) -> Symbol:
        if vd.name in scope:
            raise SemaError(
                f"{vd.loc.file}:{vd.loc.line}:{vd.loc.col}: "
                f"variable {vd.name!r} already declared in this scope"
            )
        t = type_from_name(vd.type_name)
        if t is None or t not in (UBYTE, UWORD):
            raise SemaError(
                f"{vd.loc.file}:{vd.loc.line}:{vd.loc.col}: "
                f"type {vd.type_name!r} not supported yet "
                f"(Phase 2 = ubyte | uword)"
            )
        size = 1 if t is UBYTE else 2
        if self._zp_next + size > ZP_VAR_TOP:
            raise SemaError(
                f"{vd.loc.file}:{vd.loc.line}:{vd.loc.col}: out of ZP variable space"
            )
        mangled = f"{mangled_prefix}{vd.name}"
        sym = Symbol(name=vd.name, mangled=mangled, type=t, kind="var",
                     address=self._zp_next)
        self._zp_next += size
        scope[vd.name] = sym
        vd.sym = sym
        self.prog.all_vars.append(sym)
        if vd.init is not None:
            self._walk_expr(vd.init)
            if t is UBYTE and vd.init.type is not UBYTE:
                raise SemaError(
                    f"{vd.loc.file}:{vd.loc.line}:{vd.loc.col}: "
                    f"initializer type mismatch for ubyte {vd.name!r}"
                )
            if t is UWORD and vd.init.type not in (UBYTE, UWORD):
                # ubyte literal auto-widens to uword on assignment.
                raise SemaError(
                    f"{vd.loc.file}:{vd.loc.line}:{vd.loc.col}: "
                    f"initializer type mismatch for uword {vd.name!r}"
                )
        return sym

    # ---- statement / expression walks ----

    def _walk_block(self, blk: Block, sub_name: str) -> None:
        for st in blk.stmts:
            self._walk_stmt(st, sub_name=sub_name)

    def _walk_stmt(self, st, sub_name: str) -> None:
        if isinstance(st, ExprStmt):
            self._walk_expr(st.expr)
            return
        if isinstance(st, InlineAsm):
            return
        if isinstance(st, VarDecl):
            self._declare_var(st, mangled_prefix=f"p8v_{sub_name}_",
                              scope=self._scope_stack[-1])
            return
        if isinstance(st, Assign):
            # Phase 2 assigns: target is Ident only.
            assert isinstance(st.target, Ident)
            self._walk_expr(st.target)
            self._walk_expr(st.rhs)
            if st.target.sym is None or st.target.sym.kind != "var":
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"assignment target must be a variable"
                )
            tgt_t = st.target.sym.type
            rhs_t = st.rhs.type
            if tgt_t is UBYTE and rhs_t not in (UBYTE, BOOL):
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"RHS type {rhs_t!r} not assignable to ubyte"
                )
            if tgt_t is UWORD and rhs_t not in (UBYTE, UWORD):
                # ubyte -> uword widens; bigger types are caught above.
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"RHS type {rhs_t!r} not assignable to uword"
                )
            return
        if isinstance(st, If):
            self._walk_expr(st.cond)
            if st.cond.type is not BOOL and st.cond.type is not UBYTE:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"if condition must be bool or ubyte"
                )
            self._walk_block(st.then_block, sub_name=sub_name)
            if st.else_block is not None:
                self._walk_block(st.else_block, sub_name=sub_name)
            return
        if isinstance(st, While):
            self._walk_expr(st.cond)
            if st.cond.type is not BOOL and st.cond.type is not UBYTE:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"while condition must be bool or ubyte"
                )
            self._walk_block(st.body, sub_name=sub_name)
            return
        if isinstance(st, Repeat):
            if st.count is not None:
                self._walk_expr(st.count)
                if st.count.type is not UBYTE:
                    raise SemaError(
                        f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                        f"repeat count must be a ubyte expression"
                    )
            self._walk_block(st.body, sub_name=sub_name)
            # Assign a unique id so codegen can label this loop's branch
            # targets without collisions across nested repeats.
            st_id = self._next_repeat_id
            self._next_repeat_id += 1
            st.id = st_id  # type: ignore[attr-defined]
            return
        if isinstance(st, For):
            # The loop variable must be declared in scope (Phase 2; the
            # `for ubyte i in ...` shorthand comes later).
            sym = self._lookup(st.var_name)
            if sym is None:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"for-loop variable {st.var_name!r} must be declared "
                    f"before the loop"
                )
            if sym.kind != "var" or sym.type is not UBYTE:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"for-loop variable {st.var_name!r} must be a ubyte var"
                )
            st.sym = sym
            self._walk_expr(st.lo)
            self._walk_expr(st.hi)
            if st.lo.type is not UBYTE or st.hi.type is not UBYTE:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"for-loop range must be ubyte"
                )
            self._walk_block(st.body, sub_name=sub_name)
            return
        if isinstance(st, (Break, Continue)):
            # Validity (must be inside a loop) checked at codegen time.
            return
        if isinstance(st, Return):
            cur = getattr(self, "_current_sub", None)
            assert cur is not None
            ret_t = type_from_name(cur.return_type_name)
            if ret_t is VOID:
                if st.value is not None:
                    raise SemaError(
                        f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                        f"sub {cur.name!r} returns void; can't return a value"
                    )
                return
            if st.value is None:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"sub {cur.name!r} declares -> {cur.return_type_name}; "
                    f"must return a value"
                )
            self._walk_expr(st.value)
            vt = st.value.type
            if ret_t is UBYTE and vt is not UBYTE:
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"return type mismatch: want ubyte, got {vt!r}"
                )
            if ret_t is UWORD and vt not in (UBYTE, UWORD):
                raise SemaError(
                    f"{st.loc.file}:{st.loc.line}:{st.loc.col}: "
                    f"return type mismatch: want uword, got {vt!r}"
                )
            return
        raise SemaError(f"sema: unhandled statement {type(st).__name__}")

    def _walk_expr(self, e) -> None:
        if isinstance(e, IntLit):
            e.type = UBYTE if 0 <= e.value <= 0xFF else UWORD
        elif isinstance(e, BoolLit):
            e.type = BOOL
        elif isinstance(e, StrLit):
            e.label = f"p8c_str_{self._next_str_id}"
            self._next_str_id += 1
            self.prog.strings.append(e)
            e.type = STR
        elif isinstance(e, Ident):
            sym = self._lookup(e.name)
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
            if sym is None and len(e.path) == 1:
                sym = get_builtin(e.path[0])
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
            # For user-defined subs / asmsubs we can type-check arg count
            # + arg types against the declared params.
            if sym.kind in ("sub", "asmsub") and len(e.path) == 1:
                target = next((s for s in self.prog.subs if s.name == sym.name), None)
                if target is not None:
                    if len(e.args) != len(target.params):
                        raise SemaError(
                            f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                            f"{sym.name!r} takes {len(target.params)} args, "
                            f"got {len(e.args)}"
                        )
                    for arg, p in zip(e.args, target.params):
                        pt = type_from_name(p.type_name)
                        if pt is UBYTE and arg.type is not UBYTE:
                            raise SemaError(
                                f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                                f"arg {p.name!r} wants ubyte, got {arg.type!r}"
                            )
                        if pt is UWORD and arg.type not in (UBYTE, UWORD):
                            raise SemaError(
                                f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                                f"arg {p.name!r} wants uword, got {arg.type!r}"
                            )
        elif isinstance(e, BinOp):
            self._walk_expr(e.lhs)
            self._walk_expr(e.rhs)
            cmp_ops = {"==", "!=", "<", "<=", ">", ">="}
            logical_ops = {"and", "or", "xor"}
            if e.op in cmp_ops:
                # Both ubyte, both uword, or ubyte vs uword (auto-widen ubyte).
                ok = ({e.lhs.type, e.rhs.type} <= {UBYTE, UWORD})
                if not ok:
                    raise SemaError(
                        f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                        f"comparison operands must both be ubyte or uword"
                    )
                e.type = BOOL
            elif e.op in logical_ops:
                if e.lhs.type is not BOOL or e.rhs.type is not BOOL:
                    raise SemaError(
                        f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                        f"logical operands must both be bool"
                    )
                e.type = BOOL
            else:
                # Arithmetic / bitwise / shift: ubyte or uword. Mixed
                # produces uword (ubyte auto-widens).
                lt, rt = e.lhs.type, e.rhs.type
                if {lt, rt} == {UBYTE}:
                    e.type = UBYTE
                elif {lt, rt} <= {UBYTE, UWORD}:
                    e.type = UWORD
                else:
                    raise SemaError(
                        f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                        f"binary op {e.op!r} needs ubyte/uword operands "
                        f"(got {lt!r} and {rt!r})"
                    )
        elif isinstance(e, UnaryOp):
            self._walk_expr(e.operand)
            if e.op == "not":
                if e.operand.type is not BOOL:
                    raise SemaError(
                        f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                        f"`not` operand must be bool"
                    )
                e.type = BOOL
            elif e.op in ("~", "-"):
                if e.operand.type is not UBYTE:
                    raise SemaError(
                        f"{e.loc.file}:{e.loc.line}:{e.loc.col}: "
                        f"unary {e.op!r} operand must be ubyte"
                    )
                e.type = UBYTE
            else:
                raise SemaError(f"unknown unary {e.op!r}")
        else:
            raise SemaError(f"sema: unhandled expr {type(e).__name__}")


def analyze(prog: Program) -> None:
    Sema(prog).run()

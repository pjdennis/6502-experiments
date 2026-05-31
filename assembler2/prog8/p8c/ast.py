"""Typed AST for the Prog8 subset.

Kept deliberately small for Phase 1. Each node carries a source
location (file, line, col) so diagnostics can pinpoint the user's
mistake even after many passes.

Type system here is Phase 1:
  * UBYTE, UWORD, BOOL, STR (literal only -- str values are emitted
    as zero-terminated byte arrays in the .data section).
  * VOID for sub returns.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


# ---- Types ----------------------------------------------------------------

class Type:
    pass


@dataclass(frozen=True)
class TUByte(Type):
    def __repr__(self) -> str: return "ubyte"


@dataclass(frozen=True)
class TUWord(Type):
    def __repr__(self) -> str: return "uword"


@dataclass(frozen=True)
class TBool(Type):
    def __repr__(self) -> str: return "bool"


@dataclass(frozen=True)
class TStr(Type):
    def __repr__(self) -> str: return "str"


@dataclass(frozen=True)
class TVoid(Type):
    def __repr__(self) -> str: return "void"


UBYTE = TUByte()
UWORD = TUWord()
BOOL = TBool()
STR = TStr()
VOID = TVoid()


def type_from_name(name: str) -> Optional[Type]:
    return {"ubyte": UBYTE, "uword": UWORD, "bool": BOOL, "str": STR, "void": VOID}.get(name)


# ---- Nodes ----------------------------------------------------------------

@dataclass
class Loc:
    file: str
    line: int
    col: int


@dataclass
class Node:
    loc: Loc


# Expressions

@dataclass
class IntLit(Node):
    value: int
    type: Type = UBYTE          # narrowed by sema


@dataclass
class StrLit(Node):
    value: str
    type: Type = STR
    # During codegen sema assigns a unique label that the .data section
    # will use to emit the bytes; the expression itself becomes a uword
    # value (the address of that label).
    label: str = ""


@dataclass
class BoolLit(Node):
    value: bool
    type: Type = BOOL


@dataclass
class Ident(Node):
    name: str
    # Resolved by sema:
    sym: Optional["Symbol"] = None
    type: Type = UBYTE


@dataclass
class Call(Node):
    # callee can be `a.b.c` -> we keep it as a dotted path list.
    path: list[str]
    args: list[Node]
    sym: Optional["Symbol"] = None
    type: Type = VOID


# Statements

@dataclass
class Block(Node):
    stmts: list[Node]


@dataclass
class ExprStmt(Node):
    expr: Node


@dataclass
class InlineAsm(Node):
    """%asm{{ raw assembly text }}; emitted verbatim into the output."""
    text: str


# Top-level

@dataclass
class Sub(Node):
    name: str
    body: Block
    # Phase 1: no params, no return. Just main() {}.
    mangled: str = ""           # filled by sema, e.g. "p8s_main_main"
    is_main: bool = False


@dataclass
class Program(Node):
    address: int = 0x4000       # default load address; %address overrides
    output_format: str = "raw"  # %output raw|prg|...
    subs: list[Sub] = field(default_factory=list)
    imports: list[str] = field(default_factory=list)
    # Filled by sema during string lifting:
    strings: list[StrLit] = field(default_factory=list)


# ---- Symbol table ---------------------------------------------------------

@dataclass
class Symbol:
    name: str            # source name
    mangled: str         # codegen name
    type: Type
    kind: str            # 'sub', 'asmsub', 'var', 'const', 'string', 'builtin'
    # For asmsub/extsub: the address or label to call:
    asm_target: Optional[str] = None
    # For builtins, the callable that lowers them:
    lower_call: Optional[object] = None

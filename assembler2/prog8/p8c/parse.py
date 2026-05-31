"""Recursive-descent parser for the Prog8 subset.

Phase 1 grammar (informal):
    program     := { directive | sub }*
    directive   := DIRECTIVE [value]
                 ; %address $XXXX, %output raw, %import name, %option ...
    sub         := 'sub' IDENT '(' ')' '->' typename block
                 | 'sub' IDENT '(' ')' block               ; void return
    typename    := 'ubyte' | 'uword' | 'bool' | 'str' | 'void'
    block       := '{' { stmt }* '}'
    stmt        := callstmt | inline_asm
    callstmt    := dotted_ident '(' arglist ')'
    dotted_ident:= IDENT { '.' IDENT }*
    arglist     := [ expr { ',' expr } ]
    expr        := strlit | intlit | bool_lit | dotted_ident_or_call
    inline_asm  := %asm '{{' ... '}}'

That's it for now -- enough for `sub main() { txt.print("hi") }`.
"""
from __future__ import annotations

from typing import Optional

from .ast import (
    Assign, BinOp, Block, BoolLit, Break, Call, Continue, ExprStmt, Ident,
    If, InlineAsm, IntLit, Loc, Node, Program, Repeat, StrLit, Sub, UnaryOp,
    VarDecl, While, type_from_name,
)
from .lex import Token


# Type keywords accepted by VarDecl in Phase 2 (just ubyte for now;
# Phase 3 widens this).
_TYPE_KWS = {"ubyte"}

# Binary-op precedence ladder, lowest precedence first. Each entry is
# (precedence-name, set-of-tokens-at-this-level). Higher index = higher
# precedence -- so we climb from the bottom of this list when parsing.
_OP_LEVELS = [
    ("logical_or",  {"or", "xor"}),
    ("logical_and", {"and"}),
    ("equality",    {"==", "!="}),
    ("comparison",  {"<", "<=", ">", ">="}),
    ("bitor",       {"|"}),
    ("bitxor",      {"^"}),
    ("bitand",      {"&"}),
    ("shift",       {"<<", ">>"}),
    ("additive",    {"+", "-"}),
]
# Build (token_kind -> level_index) for O(1) lookups.
_OP_PRECEDENCE: dict[str, int] = {}
for _idx, (_name, _tokens) in enumerate(_OP_LEVELS):
    for _t in _tokens:
        _OP_PRECEDENCE[_t] = _idx

_AUG_OPS = {"+=", "-=", "&=", "|=", "^=", "<<=", ">>="}


class ParseError(Exception):
    pass


class Parser:
    def __init__(self, tokens: list[Token], filename: str):
        self.toks = tokens
        self.pos = 0
        self.filename = filename

    # ---- token helpers ----

    def peek(self, ahead: int = 0) -> Token:
        return self.toks[self.pos + ahead]

    def eat(self, kind: str, value=None) -> Token:
        t = self.peek()
        if t.kind != kind or (value is not None and t.value != value):
            raise ParseError(
                f"{self.filename}:{t.line}:{t.col}: expected {kind}"
                f"{' ' + repr(value) if value is not None else ''}, got "
                f"{t.kind} {t.value!r}"
            )
        self.pos += 1
        return t

    def match(self, kind: str, value=None) -> Optional[Token]:
        t = self.peek()
        if t.kind == kind and (value is None or t.value == value):
            self.pos += 1
            return t
        return None

    def loc(self, t: Token) -> Loc:
        return Loc(self.filename, t.line, t.col)

    # ---- top-level ----

    def parse_program(self) -> Program:
        prog = Program(loc=self.loc(self.peek()))
        while self.peek().kind != "EOF":
            t = self.peek()
            if t.kind == "DIRECTIVE":
                self.parse_directive(prog)
            elif t.kind == "KW" and t.value == "sub":
                prog.subs.append(self.parse_sub())
            elif t.kind == "KW" and t.value == "main":
                # `main { ... }` is shorthand for `sub main() -> void { ... }`.
                self.pos += 1
                body = self.parse_block()
                sub = Sub(loc=self.loc(t), name="main", body=body, is_main=True)
                prog.subs.append(sub)
            elif t.kind == "KW" and t.value in _TYPE_KWS:
                # Module-level variable declaration.
                prog.module_vars.append(self.parse_var_decl())
            else:
                raise ParseError(
                    f"{self.filename}:{t.line}:{t.col}: expected sub, directive, "
                    f"or variable declaration, got {t.kind} {t.value!r}"
                )
        return prog

    def parse_directive(self, prog: Program) -> None:
        t = self.eat("DIRECTIVE")
        name = t.value
        if name == "address":
            v = self.eat("INT")
            prog.address = v.value
        elif name == "output":
            v = self.eat("IDENT")
            prog.output_format = v.value
        elif name == "import":
            v = self.eat("IDENT")
            prog.imports.append(v.value)
        elif name == "option":
            # bare list of options; we accept and ignore for now.
            while self.peek().kind == "IDENT":
                self.pos += 1
                if self.match(",") is None:
                    break
        else:
            raise ParseError(
                f"{self.filename}:{t.line}:{t.col}: unknown directive %{name}"
            )

    def parse_sub(self) -> Sub:
        kw = self.eat("KW", "sub")
        name_tok = self.eat("IDENT")
        self.eat("(")
        self.eat(")")
        # Optional `-> typename`
        if self.match("->"):
            self.eat("KW")  # consume the type keyword; we ignore it for Phase 1
        body = self.parse_block()
        return Sub(loc=self.loc(kw), name=name_tok.value, body=body,
                   is_main=(name_tok.value == "main"))

    def parse_block(self) -> Block:
        ob = self.eat("{")
        stmts: list[Node] = []
        while self.peek().kind != "}":
            stmts.append(self.parse_stmt())
        self.eat("}")
        return Block(loc=self.loc(ob), stmts=stmts)

    # ---- statements ----

    def parse_var_decl(self) -> VarDecl:
        t = self.eat("KW")
        if t.value not in _TYPE_KWS:
            raise ParseError(
                f"{self.filename}:{t.line}:{t.col}: expected type keyword, got {t.value!r}"
            )
        name = self.eat("IDENT")
        init = None
        if self.match("="):
            init = self.parse_expr()
        return VarDecl(loc=self.loc(t), type_name=t.value, name=name.value, init=init)

    def parse_stmt(self) -> Node:
        t = self.peek()
        if t.kind == "DIRECTIVE" and t.value == "asm":
            return self.parse_inline_asm()
        if t.kind == "KW":
            if t.value in _TYPE_KWS:
                return self.parse_var_decl()
            if t.value == "if":
                return self.parse_if()
            if t.value == "while":
                return self.parse_while()
            if t.value == "repeat":
                return self.parse_repeat()
            if t.value == "break":
                self.pos += 1
                return Break(loc=self.loc(t))
            if t.value == "continue":
                self.pos += 1
                return Continue(loc=self.loc(t))
        # Otherwise: assignment statement or expression statement.
        return self.parse_assign_or_expr()

    def parse_if(self) -> If:
        kw = self.eat("KW", "if")
        cond = self.parse_expr()
        then_blk = self.parse_block()
        else_blk = None
        if self.match("KW", "else"):
            else_blk = self.parse_block()
        return If(loc=self.loc(kw), cond=cond, then_block=then_blk, else_block=else_blk)

    def parse_while(self) -> While:
        kw = self.eat("KW", "while")
        cond = self.parse_expr()
        body = self.parse_block()
        return While(loc=self.loc(kw), cond=cond, body=body)

    def parse_repeat(self) -> Repeat:
        kw = self.eat("KW", "repeat")
        # `repeat { ... }` -- forever.
        # `repeat N { ... }` -- N times (N a ubyte expression or const).
        count = None
        if self.peek().kind != "{":
            count = self.parse_expr()
        body = self.parse_block()
        return Repeat(loc=self.loc(kw), count=count, body=body)

    def parse_assign_or_expr(self) -> Node:
        # Phase 2: only `IDENT = expr` and `IDENT <aug>= expr` are
        # assignments; everything else is an expression statement (e.g.
        # a call). We peek for "IDENT { '=' | aug-op }" and dispatch.
        if self.peek().kind == "IDENT":
            # Lookahead: peek past dotted path to see if we have an `=`.
            save = self.pos
            ident = self.eat("IDENT")
            # No dotted assigns in Phase 2; if we see one, fall back to call/expr.
            if self.peek().kind == "=":
                self.eat("=")
                rhs = self.parse_expr()
                target = Ident(loc=self.loc(ident), name=ident.value)
                return Assign(loc=self.loc(ident), target=target, op="=", rhs=rhs)
            if self.peek().kind in _AUG_OPS:
                op_tok = self.eat(self.peek().kind)
                rhs = self.parse_expr()
                target = Ident(loc=self.loc(ident), name=ident.value)
                return Assign(loc=self.loc(ident), target=target, op=op_tok.kind, rhs=rhs)
            # Rewind; fall through to expression parsing.
            self.pos = save
        return self.parse_call_stmt()

    def parse_inline_asm(self) -> InlineAsm:
        d = self.eat("DIRECTIVE", "asm")
        # Expect `{{ ... }}` -- but our lexer split { and { individually,
        # so peek for two consecutive `{` tokens.
        if self.peek(0).kind != "{" or self.peek(1).kind != "{":
            raise ParseError(
                f"{self.filename}:{d.line}:{d.col}: %asm must be followed by {{{{ ... }}}}"
            )
        # The %asm block contains raw assembly text. Our lexer already
        # consumed it as tokens, which loses whitespace. For Phase 1 we
        # demand the user write inline asm as plain text inside a string
        # literal: `%asm{{ "lda #1\nsta $f001" }}`. That keeps the lexer
        # simple. We'll switch to a raw-text scan in a later phase.
        self.eat("{"); self.eat("{")
        body = self.eat("STR").value
        self.eat("}"); self.eat("}")
        return InlineAsm(loc=self.loc(d), text=body)

    def parse_call_stmt(self) -> ExprStmt:
        e = self.parse_expr()
        return ExprStmt(loc=e.loc, expr=e)

    # ---- expressions ----

    def parse_expr(self) -> Node:
        """Top of the expression precedence ladder."""
        return self._parse_binop(level=0)

    def _parse_binop(self, level: int) -> Node:
        if level >= len(_OP_LEVELS):
            return self.parse_unary()
        left = self._parse_binop(level + 1)
        while True:
            t = self.peek()
            # Accept both punctuation tokens ('+', '<<', etc.) and
            # keyword operators ('and', 'or', 'xor') at this level.
            op = t.value if (t.kind == "KW" and t.value in _OP_PRECEDENCE) else (
                t.kind if t.kind in _OP_PRECEDENCE else None
            )
            if op is None or _OP_PRECEDENCE[op] != level:
                return left
            self.pos += 1
            right = self._parse_binop(level + 1)
            left = BinOp(loc=left.loc, op=op, lhs=left, rhs=right)

    def parse_unary(self) -> Node:
        t = self.peek()
        if t.kind == "KW" and t.value == "not":
            self.pos += 1
            return UnaryOp(loc=self.loc(t), op="not", operand=self.parse_unary())
        if t.kind == "~":
            self.pos += 1
            return UnaryOp(loc=self.loc(t), op="~", operand=self.parse_unary())
        if t.kind == "-":
            self.pos += 1
            return UnaryOp(loc=self.loc(t), op="-", operand=self.parse_unary())
        return self.parse_primary()

    def parse_primary(self) -> Node:
        t = self.peek()
        if t.kind == "(":
            self.pos += 1
            inner = self.parse_expr()
            self.eat(")")
            return inner
        if t.kind == "STR":
            self.pos += 1
            return StrLit(loc=self.loc(t), value=t.value)
        if t.kind == "INT":
            self.pos += 1
            return IntLit(loc=self.loc(t), value=t.value)
        if t.kind == "KW" and t.value in ("true", "false"):
            self.pos += 1
            return BoolLit(loc=self.loc(t), value=(t.value == "true"))
        if t.kind == "IDENT":
            return self.parse_dotted_or_call()
        raise ParseError(
            f"{self.filename}:{t.line}:{t.col}: expected expression, got "
            f"{t.kind} {t.value!r}"
        )

    def parse_dotted_or_call(self) -> Node:
        first = self.eat("IDENT")
        path = [first.value]
        while self.match("."):
            nxt = self.eat("IDENT")
            path.append(nxt.value)
        if self.match("("):
            args: list[Node] = []
            if self.peek().kind != ")":
                args.append(self.parse_expr())
                while self.match(","):
                    args.append(self.parse_expr())
            self.eat(")")
            return Call(loc=self.loc(first), path=path, args=args)
        # Bare identifier (rare in Phase 1; will be common later).
        if len(path) == 1:
            return Ident(loc=self.loc(first), name=path[0])
        # Dotted-but-not-called: treat as an Ident with the dotted name.
        return Ident(loc=self.loc(first), name=".".join(path))


def parse(tokens: list[Token], filename: str) -> Program:
    return Parser(tokens, filename).parse_program()

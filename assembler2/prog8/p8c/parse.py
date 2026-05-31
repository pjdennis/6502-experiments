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
    Block, BoolLit, Call, ExprStmt, Ident, InlineAsm, IntLit, Loc, Node,
    Program, StrLit, Sub, type_from_name,
)
from .lex import Token


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
            else:
                raise ParseError(
                    f"{self.filename}:{t.line}:{t.col}: expected sub or directive, "
                    f"got {t.kind} {t.value!r}"
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

    def parse_stmt(self) -> Node:
        t = self.peek()
        if t.kind == "DIRECTIVE" and t.value == "asm":
            return self.parse_inline_asm()
        # Otherwise: a call statement (the only stmt form in Phase 1).
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
        t = self.peek()
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

#!/usr/bin/env python3
"""Generate p1/p1.p8 -- the self-hosting Prog8 compiler (Phase 7).

p1.p8 is *authored* here rather than hand-written for one practical reason:
the codegen back-end emits a lot of fixed assembly text, and spelling that
text out by hand is error-prone. This generator splices stmt.p8's
*front-end* (streaming lexer + shunting-yard expression parser + frame-stack
statement driver + node arena -- everything up to, but not including, its
`; ---- serialization ----` section) together with a codegen back-end
written below, and renders the fixed-text fragments as `out_text("...")`
calls. The committed `p1/p1.p8` is the real artifact (it is what p8c -- and
eventually p1 itself -- compiles); regenerate it after editing this file:

    python3 p1/build_p1.py

Sourcing the front-end from stmt.p8 keeps the two in lockstep (a parser fix
in stmt.p8 flows into p1 on the next regenerate); only the back half differs
(stmt.p8 serializes the AST, p1.p8 emits 6502 assembly byte-identical to
`p8c -o`).

Fixed text is emitted with `out_text(s)` -- a copy loop over a pooled string
literal -- which relies on p8c's string-literal-as-data support (a bare
`"..."` evaluates to the address of its pool label). This is far smaller
than the per-character `out_byte($xx)` runs an earlier revision used (962
call sites at P7-M2; the prologue alone was ~5 KB of code), freeing the
64 KB budget for the rest of codegen. Distinct fixed fragments are wrapped
in o_* / out_text helper subs so each pooled string + call site appears once.

Milestones (see ../PHASE7_DESIGN.md):
  * P7-M1 -- `main { }` (nmos): prologue + empty p8s_main + nmos exit +
    reset vector.
  * P7-M2 -- module vars + simple assignment: pass S (symbol table + ZP
    bump allocation), ZP bindings after the prologue, and codegen for
    leaf assignments + byte augmented assignment.
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
STMT = HERE / "stmt.p8"
OUT = HERE / "p1.p8"

# Arena-size overrides for p1.p8. The spliced front-end sizes its arenas for
# the parser milestone (whole-program parse of tinyp8.p8 etc.), but p1.bin is
# exercised only on the SMALL codegen-test corpus, so those arenas are wildly
# oversized.
#
# THE REAL CEILING IS ~$F006, NOT $FFFF. The emulator injects its file-I/O
# syscall stubs (the routines reached via the $F006 jmp table -- argv, open,
# read, write, ...) starting at $F006 and growing UP to ~$F0C0, OVER p1.bin
# once it is loaded. So if p1.bin's code + arenas + string pool extend past
# ~$F006, the stub injection clobbers the top of the string pool (and the
# pool clobbers the stubs) -> corrupted out_text() strings AND wild jumps when
# a syscall's return address lands in stub bytes overwritten by pool data.
# Keep p1.bin's top comfortably below $F006: build_p1.py checks this after
# generating (see assert_fits, run by the test harness / `make p1-test`).
#
# Shrinking the unused arena headroom (and the now-dead serializer work stack,
# ws_*) keeps the top under the ceiling. These sizes stay generous for the
# M-corpus (a few vardecls + a short main); bump them if a future codegen test
# needs a bigger program -- but then also reclaim space elsewhere so the top
# stays < $F006. (stmt.p8 keeps its own sizes; this only rewrites p1.p8.)
ARENA_SIZES = {
    "ident_pool": 320, "ident_off": 64, "ident_len": 64,
    "str_pool": 320, "str_off": 32, "str_len": 32,
    "node_kind": 128, "node_op": 128,
    "node_a": 128, "node_b": 128, "node_c": 128, "node_d": 128,
    "operand_stack": 40, "op_kind": 40, "op_op": 40, "op_prec": 40,
    "op_a": 40, "op_b": 40, "op_floor": 40,
    "cons_val": 128, "cons_next": 128,
    # fr_* (the parser's frame stack) defaults to 64; the codegen corpus's
    # programs are shallow so 32 is ample and reclaims a bit more headroom.
    "fr_kind": 32, "fr_mode": 32, "fr_stmts": 32, "fr_defer": 32,
    "fr_cond": 32, "fr_then": 32, "fr_var": 32, "fr_lo": 32, "fr_hi": 32,
    "fr_choices": 32, "fr_values": 32,
    # ws_* is the AST serializer's work stack -- dropped from p1, so dead.
    "ws_type": 2, "ws_node": 2, "ws_depth": 2,
}


def shrink_arenas(body: str) -> str:
    """Apply ARENA_SIZES to the spliced front-end's array declarations."""
    for name, size in ARENA_SIZES.items():
        body, n = re.subn(
            rf"^((?:uword|ubyte)\[)\d+(\]\s+{re.escape(name)}\b)",
            rf"\g<1>{size}\g<2>", body, count=1, flags=re.M)
        assert n == 1, f"arena decl for {name!r} not found (count={n})"
    return body


def esc(s: str) -> str:
    """Escape a Python string into a Prog8 string literal (p8c lexer escapes:
    \\n \\r \\t \\" \\\\)."""
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def emit_text(s: str, indent="    ") -> str:
    """A fixed-text emission: out_text("<escaped s>")."""
    return f"{indent}out_text({esc(s)})"


# ---- the fixed assembly text (must match p8c/codegen.py exactly) ----
# The `; source:` line is normalized away by the test harness on both
# sides, so p1 emits a fixed placeholder.
PROLOGUE_PRE = (
    "; ---- generated by p8c -- DO NOT EDIT ----\n"
    "; source: SRC\n"
    "; target: nmos (vasm builds a self-contained 6502 binary, reset vector\n"
    ";               at $FFFC points to p8s_main; intended for the emulator's\n"
    ";               nmos-default machine with file-I/O stubs at $F006-$F03C).\n"
    "\n"
    "__p8c_tmp0 = $20                     ; codegen scratch (byte)\n"
    "__p8c_tmp1 = $21                     ; codegen scratch (byte)\n"
    "__p8c_wtmp0 = $22                   ; codegen scratch (word)\n"
    "__p8c_wtmp1 = $24                   ; codegen scratch (word)\n"
    "__p8c_ptr0  = $26                    ; indirect-Y pointer (2 bytes)\n"
    "__p8c_aptr  = $28                    ; array element pointer (2 bytes)\n"
    "\n"
    "  .org $"
)
PROLOGUE_POST = "\n  jmp p8s_main\n"
ZP_HEADER = "; ---- ZP variable allocations ----\n"
MAIN_HEAD = "\n\n; ---- sub main ----\np8s_main:\n"
MAIN_RET = ".Lp8s_main_ret:\n  lda #$00\n  jsr $f00f\n  brk\n"
# The ubyte*ubyte runtime helper (port of p8c's __p8c_mul_u8). Emitted between
# the last sub and the string pool, only when `*` was used (mul_used). The
# leading blank line matches p8c's `self.emit("")` before the comment.
MUL_HELPER = (
    "\n; ---- runtime: ubyte * ubyte -> A ----\n"
    "__p8c_mul_u8:\n"
    "  lda #0\n"
    "  ldx #8\n"
    ".__mul_loop:\n"
    "  lsr __p8c_tmp1\n"
    "  bcc .__mul_skip\n"
    "  clc\n"
    "  adc __p8c_tmp0\n"
    ".__mul_skip:\n"
    "  asl __p8c_tmp0\n"
    "  dex\n"
    "  bne .__mul_loop\n"
    "  rts\n"
)
TRAILERS = (
    "\n  ; ---- reset vector ----\n"
    "  .org $FFFC\n"
    "  .word p8s_main\n"
    "  .word $0000\n"
    "\n"
)

codegen = f"""\

; ============================================================
; codegen back-end (port of p8c/codegen.py) -- emits 6502 asm
; byte-identical to `p8c -o`. Fixed text is emitted with out_text()
; (a copy loop over a pooled string literal -- p8c's
; string-literal-as-data), wrapped in o_* helpers so each pooled
; string + call site appears once. Authored via build_p1.py.
; ============================================================

; ---- text primitives ----
; out_text: write the NUL-terminated string at `p` to the output file.
; (A string literal in value position is its pool address -- a uword.)
sub out_text(uword p) {{
    uword q
    q = p
    repeat {{
        ubyte c
        c = @(q)
        if c == 0 {{
            break
        }}
        out_byte(c)
        q = q + 1
    }}
}}
sub out_hex2(ubyte v) {{
    out_hex_nib(lsb(v >> 4))
    out_hex_nib(v)
}}
sub out_hex4(uword v) {{
    out_hex_nib(lsb(v >> 12))
    out_hex_nib(lsb(v >> 8))
    out_hex_nib(lsb(v >> 4))
    out_hex_nib(lsb(v))
}}
sub out_hex_nib(ubyte n) {{
    n = n & $0f
    if n >= $0a {{
        out_byte(n + $57)
    }} else {{
        out_byte(n + $30)
    }}
}}
sub out_ident_text(uword id) {{
    uword off
    uword n
    uword j
    off = ident_off[id]
    n = ident_len[id]
    j = 0
    repeat {{
        if j >= n {{
            break
        }}
        out_byte(ident_pool[off + j])
        j = j + 1
    }}
}}
; "p8v_<name>" -- the mangled label for a user var.
sub emit_mangled(uword identid) {{
    out_text("p8v_")
    out_ident_text(identid)
}}

; shared instruction-prefix fragments (leading 2-space indent included)
sub o_nl()    {{ out_byte($0a) }}
sub o_lda()   {{ out_text("  lda ") }}
sub o_ldy()   {{ out_text("  ldy ") }}
sub o_sta()   {{ out_text("  sta ") }}
sub o_sty()   {{ out_text("  sty ") }}
sub o_imm()   {{ out_text("#$") }}
sub o_plus1() {{ out_text("+1") }}

sub reverse_cons(uword head) -> uword {{
    uword rev
    rev = 0
    uword cell
    cell = head
    repeat {{
        if cell == 0 {{
            break
        }}
        rev = cons_prepend(rev, cons_val[cell])
        cell = cons_next[cell]
    }}
    return rev
}}

; ---- pass S: the symbol table -------------------------------
; A persistent (across passes) struct-of-arrays mapping a module var's
; ident id to its type tag + ZP address. Built from prog_vars right after
; pass A, BEFORE the arena is reset for pass M -- so the ident ids stay
; valid (the ident pool persists; pass M re-lexes the same names and
; intern_name dedups them to the same ids).
sub find_sym(uword identid) -> uword {{
    uword i
    i = 0
    repeat {{
        if i >= sym_count {{
            break
        }}
        if sym_ident[i] == identid {{
            return i
        }}
        i = i + 1
    }}
    return $ffff
}}
; allocate ZP for every scalar module var, in declaration order, exactly
; as p8c's sema does (bump from $40; ubyte/byte = 1 byte, uword = 2).
sub build_symbols() {{
    sym_count = 0
    zp_next = $40
    uword head
    head = reverse_cons(prog_vars)
    uword cell
    cell = head
    repeat {{
        if cell == 0 {{
            break
        }}
        uword vd
        vd = cons_val[cell]
        if node_kind[vd] == ND_VARDECL {{
            if node_c[vd] == 0 {{               ; scalar (not an array)
                ubyte tag
                tag = node_op[vd]
                if tag <= TY_UWORD {{           ; ubyte / byte / uword
                    sym_ident[sym_count] = node_a[vd]
                    sym_type[sym_count] = tag
                    sym_addr[sym_count] = zp_next
                    sym_count = sym_count + 1
                    if tag == TY_UWORD {{
                        zp_next = zp_next + 2
                    }} else {{
                        zp_next = zp_next + 1
                    }}
                }}
            }}
        }}
        cell = cons_next[cell]
    }}
}}

; ---- prologue / ZP bindings / trailers ----------------------
sub emit_prologue() {{
{emit_text(PROLOGUE_PRE)}
    out_hex4(prog_address)
{emit_text(PROLOGUE_POST)}
}}

; Emit the `; ---- ZP variable allocations ----` block + one
; `p8v_<name> = $XX` line per ZP scalar. Leading blank line, no trailing
; blank -- emit_main's leading "\\n\\n" supplies the two-blank gap. (Empty
; when there are no module vars, matching p8c.)
sub emit_zp_bindings() {{
    if sym_count == 0 {{
        return
    }}
    out_byte($0a)
{emit_text(ZP_HEADER)}
    uword i
    i = 0
    repeat {{
        if i >= sym_count {{
            break
        }}
        emit_mangled(sym_ident[i])
        out_text(" = $")
        out_hex2(lsb(sym_addr[i]))
        o_nl()
        i = i + 1
    }}
}}

sub emit_main(uword body) {{
{emit_text(MAIN_HEAD)}
    codegen_body(body)
{emit_text(MAIN_RET)}
}}

sub emit_trailers() {{
{emit_text(TRAILERS)}
}}

; the ubyte*ubyte helper, emitted only when `*` codegen set mul_used. Goes
; between the last sub and the string pool (matching p8c's tail order).
sub emit_mul_helper() {{
    if mul_used == 0 {{
        return
    }}
{emit_text(MUL_HELPER)}
}}

; ---- string pool trailer (port of p8c/codegen.py::_escape) ----
; A "plain" char goes inside a "..." run; everything else (control chars,
; `"`, `\\`) is emitted as $XX; parts are joined by ", "; an empty string
; emits the single part "0".
sub str_char_plain(ubyte c) -> ubyte {{
    if c < $20 {{
        return 0
    }}
    if c >= $7f {{
        return 0
    }}
    if c == $22 {{        ; "
        return 0
    }}
    if c == $5c {{        ; backslash
        return 0
    }}
    return 1
}}
sub emit_string_byte_list(uword sid) {{
    uword off
    uword n
    off = str_off[sid]
    n = str_len[sid]
    ubyte in_run        ; inside an open "..." run
    ubyte any           ; emitted at least one part (need ", " before next)
    in_run = 0
    any = 0
    uword j
    j = 0
    repeat {{
        if j >= n {{
            break
        }}
        ubyte c
        c = str_pool[off + j]
        if str_char_plain(c) != 0 {{
            if in_run == 0 {{
                if any != 0 {{
                    out_text(", ")
                }}
                out_byte($22)           ; open "
                in_run = 1
                any = 1
            }}
            out_byte(c)
        }} else {{
            if in_run != 0 {{
                out_byte($22)           ; close "
                in_run = 0
            }}
            if any != 0 {{
                out_text(", ")
            }}
            out_byte($24)               ; $
            out_hex2(c)
            any = 1
        }}
        j = j + 1
    }}
    if in_run != 0 {{
        out_byte($22)
    }}
    if any == 0 {{
        out_byte($30)                   ; "0" for the empty string
    }}
}}
; emit `; ---- string pool ----` + one `p8c_str_N:` / `.byte ..., 0` per
; label, in encounter order. Goes between the last sub and the reset vector
; (matching p8c). Empty -> nothing.
sub emit_string_pool() {{
    if strpool_count == 0 {{
        return
    }}
    out_byte($0a)
    out_text("; ---- string pool ----")
    o_nl()
    uword i
    i = 0
    repeat {{
        if i >= strpool_count {{
            break
        }}
        out_text("p8c_str_")
        out_dec(i)
        out_byte($3a)                   ; :
        o_nl()
        out_text("  .byte ")
        emit_string_byte_list(strpool_sid[i])
        out_text(", 0")
        o_nl()
        i = i + 1
    }}
}}

; ---- control-flow labels + long branches -------------------
; control label kinds: 0 else, 1 endif, 2 while_top, 3 while_end,
; 4 for_top, 5 for_cont, 6 for_end, 7 rep_top, 8 rep_dec, 9 rep_end,
; 10 rep_break.
sub emit_ctrl_label_ref(ubyte kind, uword id) {{
    if kind == 0 {{ out_text(".Lelse_") }}
    if kind == 1 {{ out_text(".Lendif_") }}
    if kind == 2 {{ out_text(".Lwhile_top_") }}
    if kind == 3 {{ out_text(".Lwhile_end_") }}
    if kind == 4 {{ out_text(".Lfor_top_") }}
    if kind == 5 {{ out_text(".Lfor_cont_") }}
    if kind == 6 {{ out_text(".Lfor_end_") }}
    if kind == 7 {{ out_text(".Lrep_top_") }}
    if kind == 8 {{ out_text(".Lrep_dec_") }}
    if kind == 9 {{ out_text(".Lrep_end_") }}
    if kind == 10 {{ out_text(".Lrep_break_") }}
    if kind == 11 {{ out_text(".Lwhen_end_") }}
    if kind == 12 {{ out_text(".Lwhen_body_") }}
    if kind == 13 {{ out_text(".Lwhen_next_") }}
    if kind == 14 {{ out_text(".Lwhen_skip_") }}
    out_dec(id)
}}
; branch mnemonics by code: 0 bne 1 beq 2 bcc 3 bcs 4 bmi 5 bpl 6 bvc 7 bvs.
sub out_br_mnem(ubyte code) {{
    if code == 0 {{ out_text("bne") return }}
    if code == 1 {{ out_text("beq") return }}
    if code == 2 {{ out_text("bcc") return }}
    if code == 3 {{ out_text("bcs") return }}
    if code == 4 {{ out_text("bmi") return }}
    if code == 5 {{ out_text("bpl") return }}
    if code == 6 {{ out_text("bvc") return }}
    out_text("bvs")
}}
; _br: branch to a (possibly distant) control label when `brcode` is TRUE,
; via the inverted-branch + jmp pattern (works at any distance).
sub emit_br(ubyte brcode, ubyte tkind, uword tid) {{
    ubyte inv
    inv = brcode ^ 1
    uword sk
    sk = label_seq
    label_seq = label_seq + 1
    out_text("  ")
    out_br_mnem(inv)
    out_text(" .Lbrs_")
    out_dec(sk)
    o_nl()
    out_text("  jmp ")
    emit_ctrl_label_ref(tkind, tid)
    o_nl()
    out_text(".Lbrs_")
    out_dec(sk)
    out_byte($3a)
    o_nl()
}}

; ---- condition codegen (branch to target if FALSE) ----------
; is this expression a uword (for the word-compare condition path)? Leaf
; idents resolve via the symbol table; &name is a uword. (Nested expr typing
; is a tracked gap, as in the byte comparison signedness.)
sub expr_is_word(uword e) -> ubyte {{
    if node_kind[e] == ND_ADDROF {{
        return 1
    }}
    if node_kind[e] == ND_IDENT {{
        uword si
        si = find_sym(node_a[e])
        if si != $ffff {{
            if sym_type[si] == TY_UWORD {{
                return 1
            }}
        }}
    }}
    return 0
}}
; the negated (branch-if-false) sequence for an UNSIGNED compare op.
sub emit_neg_unsigned(ubyte op, ubyte tkind, uword tid) {{
    if op == TK_EQ {{ emit_br(0, tkind, tid) return }}      ; bne
    if op == TK_NE {{ emit_br(1, tkind, tid) return }}      ; beq
    if op == TK_LT {{ emit_br(3, tkind, tid) return }}      ; bcs
    if op == TK_GE {{ emit_br(2, tkind, tid) return }}      ; bcc
    if op == TK_GT {{                                        ; beq + bcc
        emit_br(1, tkind, tid)
        emit_br(2, tkind, tid)
        return
    }}
    ; TK_LE: beq <skip> (short); bcs target; skip:
    uword sk
    sk = label_seq
    label_seq = label_seq + 1
    out_text("  beq .Lle_skip_")
    out_dec(sk)
    o_nl()
    emit_br(3, tkind, tid)
    out_text(".Lle_skip_")
    out_dec(sk)
    out_byte($3a)
    o_nl()
}}
; the negated (branch-if-false) sequence for a SIGNED compare op (after the
; overflow-corrected SBC has set N/Z).
sub emit_neg_signed(ubyte op, ubyte tkind, uword tid) {{
    if op == TK_EQ {{ emit_br(0, tkind, tid) return }}      ; bne
    if op == TK_NE {{ emit_br(1, tkind, tid) return }}      ; beq
    if op == TK_LT {{ emit_br(5, tkind, tid) return }}      ; bpl
    if op == TK_GE {{ emit_br(4, tkind, tid) return }}      ; bmi
    if op == TK_GT {{                                        ; beq + bmi
        emit_br(1, tkind, tid)
        emit_br(4, tkind, tid)
        return
    }}
    ; TK_LE: beq <skip> (short); bpl target; skip:
    uword sk
    sk = label_seq
    label_seq = label_seq + 1
    out_text("  beq .Lsle_skip_")
    out_dec(sk)
    o_nl()
    emit_br(5, tkind, tid)
    out_text(".Lsle_skip_")
    out_dec(sk)
    out_byte($3a)
    o_nl()
}}
; evaluate `cond` as bool and branch to the control label (tkind,tid) if it
; is FALSE. Comparison conditions emit the compare straight into the branch
; (no 0/1 materialized); anything else evaluates to A and branches on zero.
sub emit_cond_branch_if_false(uword cond, ubyte tkind, uword tid) {{
    if node_kind[cond] == ND_BINOP {{
        ubyte op
        op = node_op[cond]
        if is_cmp_op(op) != 0 {{
            uword lhs
            uword rhs
            lhs = node_a[cond]
            rhs = node_b[cond]
            ubyte isw
            isw = 0
            if expr_is_word(lhs) != 0 {{ isw = 1 }}
            if expr_is_word(rhs) != 0 {{ isw = 1 }}
            if isw != 0 {{
                ; 16-bit compare (always unsigned)
                codegen_word_expr(lhs)
                out_text("  sta __p8c_wtmp0")
                o_nl()
                out_text("  sty __p8c_wtmp0+1")
                o_nl()
                codegen_word_expr(rhs)
                out_text("  sta __p8c_wtmp1")
                o_nl()
                out_text("  sty __p8c_wtmp1+1")
                o_nl()
                out_text("  lda __p8c_wtmp0+1")
                o_nl()
                out_text("  cmp __p8c_wtmp1+1")
                o_nl()
                uword wlo
                wlo = label_seq
                label_seq = label_seq + 1
                out_text("  bne .Lwcmp_lo_")
                out_dec(wlo)
                o_nl()
                out_text("  lda __p8c_wtmp0")
                o_nl()
                out_text("  cmp __p8c_wtmp1")
                o_nl()
                out_text(".Lwcmp_lo_")
                out_dec(wlo)
                out_byte($3a)
                o_nl()
                emit_neg_unsigned(op, tkind, tid)
                return
            }}
            ; byte compare
            ubyte iss
            iss = cmp_is_signed(cond)
            if is_leaf_rhs(rhs) != 0 {{
                ; leaf rhs (literal / var): no tmp0/tmp1 spill -- eval lhs into
                ; A and compare directly. (Matches p8c's _emit_cmp_cond.)
                codegen_byte_expr(lhs)
                ubyte do_signed
                do_signed = 0
                if iss != 0 {{
                    if op != TK_EQ {{
                        if op != TK_NE {{
                            do_signed = 1
                        }}
                    }}
                }}
                if do_signed != 0 {{
                    out_text("  sec")
                    o_nl()
                    out_text("  sbc ")
                    emit_byte_operand(0, rhs)
                    o_nl()
                    uword sg2
                    sg2 = label_seq
                    label_seq = label_seq + 1
                    out_text("  bvc .Lsgn_ok_")
                    out_dec(sg2)
                    o_nl()
                    out_text("  eor #$80")
                    o_nl()
                    out_text(".Lsgn_ok_")
                    out_dec(sg2)
                    out_byte($3a)
                    o_nl()
                    emit_neg_signed(op, tkind, tid)
                    return
                }}
                out_text("  cmp ")
                emit_byte_operand(0, rhs)
                o_nl()
                emit_neg_unsigned(op, tkind, tid)
                return
            }}
            codegen_byte_expr(lhs)
            out_text("  sta __p8c_tmp0")
            o_nl()
            codegen_byte_expr(rhs)
            out_text("  sta __p8c_tmp1")
            o_nl()
            out_text("  lda __p8c_tmp0")
            o_nl()
            if iss != 0 {{
                if op != TK_EQ {{
                    if op != TK_NE {{
                        out_text("  sec")
                        o_nl()
                        out_text("  sbc __p8c_tmp1")
                        o_nl()
                        uword sg
                        sg = label_seq
                        label_seq = label_seq + 1
                        out_text("  bvc .Lsgn_ok_")
                        out_dec(sg)
                        o_nl()
                        out_text("  eor #$80")
                        o_nl()
                        out_text(".Lsgn_ok_")
                        out_dec(sg)
                        out_byte($3a)
                        o_nl()
                        emit_neg_signed(op, tkind, tid)
                        return
                    }}
                }}
                ; signed == / != still use cmp
                out_text("  cmp __p8c_tmp1")
                o_nl()
                emit_neg_signed(op, tkind, tid)
                return
            }}
            out_text("  cmp __p8c_tmp1")
            o_nl()
            emit_neg_unsigned(op, tkind, tid)
            return
        }}
    }}
    ; generic: evaluate to 0/1 in A, branch to target on zero.
    codegen_byte_expr(cond)
    emit_br(1, tkind, tid)
}}

; ---- statement codegen (work stack; control flow w/o recursion) ----
sub sws_push(ubyte ty, uword a, uword b) {{
    sws_type[sws_sp] = ty
    sws_a[sws_sp] = a
    sws_b[sws_sp] = b
    sws_sp = sws_sp + 1
}}
; push a block's statements so they pop in source order. node_a[blk] is the
; reversed cons (last stmt first), so pushing it directly puts the first stmt
; on top.
sub push_block_stmts(uword blk) {{
    if blk == 0 {{
        return
    }}
    uword cell
    cell = node_a[blk]
    repeat {{
        if cell == 0 {{
            break
        }}
        sws_push(0, cons_val[cell], 0)
        cell = cons_next[cell]
    }}
}}
; the statement-driver entry: emit a whole block (and everything nested) with
; no recursion.
sub codegen_body(uword body) {{
    sws_sp = 0
    lp_sp = 0
    push_block_stmts(body)
    repeat {{
        if sws_sp == 0 {{
            break
        }}
        sws_sp = sws_sp - 1
        ubyte ty
        uword a
        uword b
        ty = sws_type[sws_sp]
        a = sws_a[sws_sp]
        b = sws_b[sws_sp]
        if ty == 0 {{
            codegen_stmt(a)
        }} else {{
            if ty == 1 {{
                emit_ctrl_label_ref(lsb(a), b)
                out_byte($3a)
                o_nl()
            }} else {{
                if ty == 2 {{
                    out_text("  jmp ")
                    emit_ctrl_label_ref(lsb(a), b)
                    o_nl()
                }} else {{
                    if ty == 3 {{
                        lp_sp = lp_sp - 1
                    }} else {{
                        if ty == 5 {{
                            emit_rep_tail(b)          ; counted-repeat tail
                        }} else {{
                            if ty == 6 {{
                                emit_for_cont(a, b)   ; for cont/test/inc tail
                            }} else {{
                                emit_when_choice(a, b) ; ty == 7: a when arm
                            }}
                        }}
                    }}
                }}
            }}
        }}
    }}
}}

sub codegen_stmt(uword st) {{
    ubyte k
    k = node_kind[st]
    if k == ND_ASSIGN {{
        codegen_assign(st)
        return
    }}
    if k == ND_IF {{
        codegen_if(st)
        return
    }}
    if k == ND_WHILE {{
        codegen_while(st)
        return
    }}
    if k == ND_REPEAT {{
        codegen_repeat(st)
        return
    }}
    if k == ND_FOR {{
        codegen_for(st)
        return
    }}
    if k == ND_WHEN {{
        codegen_when(st)
        return
    }}
    if k == ND_BREAK {{
        out_text("  jmp ")
        emit_ctrl_label_ref(lp_bk[lp_sp - 1], lp_bi[lp_sp - 1])
        o_nl()
        return
    }}
    if k == ND_CONTINUE {{
        out_text("  jmp ")
        emit_ctrl_label_ref(lp_ck[lp_sp - 1], lp_ci[lp_sp - 1])
        o_nl()
        return
    }}
    ; other statement kinds arrive at later milestones.
}}
sub codegen_if(uword st) {{
    uword cond
    uword thenb
    uword elseb
    uword endif_id
    cond = node_a[st]
    thenb = node_b[st]
    elseb = node_c[st]
    if elseb != 0 {{
        uword else_id
        else_id = label_seq
        label_seq = label_seq + 1
        endif_id = label_seq
        label_seq = label_seq + 1
        emit_cond_branch_if_false(cond, 0, else_id)
        sws_push(1, 1, endif_id)          ; endif label (bottom)
        push_block_stmts(elseb)
        sws_push(1, 0, else_id)           ; else label
        sws_push(2, 1, endif_id)          ; jmp endif
        push_block_stmts(thenb)           ; then stmts (top)
        return
    }}
    endif_id = label_seq
    label_seq = label_seq + 1
    emit_cond_branch_if_false(cond, 1, endif_id)
    sws_push(1, 1, endif_id)
    push_block_stmts(thenb)
}}
sub codegen_while(uword st) {{
    uword cond
    uword body
    cond = node_a[st]
    body = node_b[st]
    uword top_id
    uword end_id
    top_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    emit_ctrl_label_ref(2, top_id)
    out_byte($3a)
    o_nl()
    lp_bk[lp_sp] = 3
    lp_bi[lp_sp] = end_id
    lp_ck[lp_sp] = 2
    lp_ci[lp_sp] = top_id
    lp_sp = lp_sp + 1
    emit_cond_branch_if_false(cond, 3, end_id)
    sws_push(3, 0, 0)                     ; pop loop stack (bottom)
    sws_push(1, 3, end_id)               ; while_end label
    sws_push(2, 2, top_id)               ; jmp while_top
    push_block_stmts(body)               ; body (top)
}}
; `repeat` (port of _emit_repeat). Forever (count 0) is a plain top/jmp/end
; loop. Counted pushes the count on the CPU stack, decrements per iteration,
; exits at 0; break pops the saved counter first. The 4 counted labels are
; allocated sequentially (rep_top, rep_dec, rep_end, rep_break) so the tail
; recovers them from rep_top alone.
sub codegen_repeat(uword st) {{
    uword count
    uword body
    count = node_a[st]
    body = node_b[st]
    uword top_id
    uword end_id
    top_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    if count == 0 {{
        ; forever: break -> rep_end, continue -> rep_top
        emit_ctrl_label_ref(7, top_id)
        out_byte($3a)
        o_nl()
        lp_bk[lp_sp] = 9
        lp_bi[lp_sp] = end_id
        lp_ck[lp_sp] = 7
        lp_ci[lp_sp] = top_id
        lp_sp = lp_sp + 1
        sws_push(3, 0, 0)                 ; pop loop
        sws_push(1, 9, end_id)           ; rep_end label
        sws_push(2, 7, top_id)           ; jmp rep_top
        push_block_stmts(body)
        return
    }}
    ; counted. top_id, end_id already allocated; allocate dec + break so the
    ; four are top, end, dec, break -- but the tail wants them sequential from
    ; rep_top. Re-derive: we use top_id (=N), dec=N+1, end=N+2, break=N+3.
    ; (Undo the end_id we took as N+1 and re-allocate in the canonical order.)
    label_seq = top_id + 1               ; rewind to just after rep_top
    uword dec_id
    uword break_id
    dec_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    break_id = label_seq
    label_seq = label_seq + 1
    codegen_byte_expr(count)
    out_text("  pha")
    o_nl()
    emit_ctrl_label_ref(7, top_id)
    out_byte($3a)
    o_nl()
    lp_bk[lp_sp] = 10                    ; break -> rep_break
    lp_bi[lp_sp] = break_id
    lp_ck[lp_sp] = 8                     ; continue -> rep_dec
    lp_ci[lp_sp] = dec_id
    lp_sp = lp_sp + 1
    sws_push(3, 0, 0)                    ; pop loop
    sws_push(5, 0, top_id)              ; rep tail (dec/pla/.../break/end)
    push_block_stmts(body)
}}
; counted-repeat tail: dec_id=top+1, end_id=top+2, break_id=top+3.
sub emit_rep_tail(uword top_id) {{
    uword dec_id
    uword end_id
    uword break_id
    dec_id = top_id + 1
    end_id = top_id + 2
    break_id = top_id + 3
    emit_ctrl_label_ref(8, dec_id)
    out_byte($3a)
    o_nl()
    out_text("  pla")
    o_nl()
    out_text("  sec")
    o_nl()
    out_text("  sbc #1")
    o_nl()
    emit_br(1, 9, end_id)               ; beq rep_end
    out_text("  pha")
    o_nl()
    out_text("  jmp ")
    emit_ctrl_label_ref(7, top_id)
    o_nl()
    emit_ctrl_label_ref(10, break_id)
    out_byte($3a)
    o_nl()
    out_text("  pla")
    o_nl()
    emit_ctrl_label_ref(9, end_id)
    out_byte($3a)
    o_nl()
}}
; `for v in lo to hi` (inclusive, ubyte; port of _emit_for). The loop var must
; be pre-declared (it is already in the symbol table). Init v=lo; for_top:; body;
; for_cont:; compare v to hi, exit if equal; inc v; jmp for_top; for_end:.
; The 3 labels are allocated top, end, cont (matching p8c) so the deferred cont
; tail derives top=end-1, cont=end+1 from end_id.
sub codegen_for(uword st) {{
    uword var
    uword lo
    uword body
    var = node_a[st]
    lo = node_b[st]
    body = node_d[st]
    uword si
    si = find_sym(var)
    uword top_id
    uword end_id
    top_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    uword cont_id
    cont_id = label_seq
    label_seq = label_seq + 1
    ; init: v = lo
    codegen_byte_expr(lo)
    emit_sta_sym(si)
    ; for_top:
    emit_ctrl_label_ref(4, top_id)
    out_byte($3a)
    o_nl()
    lp_bk[lp_sp] = 6                     ; break -> for_end
    lp_bi[lp_sp] = end_id
    lp_ck[lp_sp] = 5                     ; continue -> for_cont
    lp_ci[lp_sp] = cont_id
    lp_sp = lp_sp + 1
    sws_push(3, 0, 0)                    ; pop loop
    sws_push(1, 6, end_id)             ; for_end label
    sws_push(6, st, end_id)            ; cont/test/inc tail
    push_block_stmts(body)
}}
; for-loop continue/test/increment tail. labels: top=end-1, cont=end+1.
sub emit_for_cont(uword st, uword end_id) {{
    uword top_id
    uword cont_id
    top_id = end_id - 1
    cont_id = end_id + 1
    uword si
    si = find_sym(node_a[st])
    uword hi
    hi = node_c[st]
    emit_ctrl_label_ref(5, cont_id)
    out_byte($3a)
    o_nl()
    out_text("  lda ")
    emit_mangled(node_a[st])
    o_nl()
    if node_kind[hi] == ND_INT {{
        out_text("  cmp #$")
        out_hex2(lsb(node_a[hi]))
        o_nl()
    }} else {{
        if node_kind[hi] == ND_IDENT {{
            out_text("  cmp ")
            emit_mangled(node_a[hi])
            o_nl()
        }} else {{
            out_text("  sta __p8c_tmp0")
            o_nl()
            codegen_byte_expr(hi)
            out_text("  sta __p8c_tmp1")
            o_nl()
            out_text("  lda __p8c_tmp0")
            o_nl()
            out_text("  cmp __p8c_tmp1")
            o_nl()
        }}
    }}
    emit_br(1, 6, end_id)               ; beq for_end
    out_text("  inc ")
    emit_mangled(node_a[st])
    o_nl()
    out_text("  jmp ")
    emit_ctrl_label_ref(4, top_id)
    o_nl()
}}
; `when` (port of _emit_when): when expr, a list of value-arms and an optional
; else arm. The expr is evaluated once (byte -> __p8c_tmp0, word -> __p8c_wtmp0);
; each arm compares
; its value(s) and jumps to its body on a match, else to the next arm. Each arm
; is a deferred sws task (ty 7) so its body (a nested block) and trailers
; interleave per-arm exactly as p8c emits them. is_word is packed into the high
; bit of the task's end_id field (whens may nest; a global would be clobbered).
sub codegen_when(uword st) {{
    uword endw_id
    endw_id = label_seq
    label_seq = label_seq + 1
    uword expr
    expr = node_a[st]
    ubyte isw
    isw = expr_is_word(expr)
    if isw != 0 {{
        codegen_word_expr(expr)
        out_text("  sta __p8c_wtmp0")
        o_nl()
        out_text("  sty __p8c_wtmp0+1")
        o_nl()
    }} else {{
        codegen_byte_expr(expr)
        out_text("  sta __p8c_tmp0")
        o_nl()
    }}
    uword packed
    packed = endw_id
    if isw != 0 {{
        packed = endw_id | $8000
    }}
    ; end label (bottom), then choices. node_b[st] is the reversed cons (last
    ; arm first); pushing it directly pops the arms in source order.
    sws_push(1, 11, endw_id)            ; when_end label
    uword cell
    cell = node_b[st]
    repeat {{
        if cell == 0 {{
            break
        }}
        sws_push(7, cons_val[cell], packed)
        cell = cons_next[cell]
    }}
}}
; emit one when arm. Allocates body+next labels (always, even for else, to
; match p8c's label numbering); emits the value matches immediately, then
; defers the body + trailers.
sub emit_when_choice(uword choice, uword packed) {{
    ubyte isw
    uword endw_id
    isw = 0
    endw_id = packed
    if (packed & $8000) != 0 {{
        isw = 1
        endw_id = packed & $7fff
    }}
    uword body_id
    uword next_id
    body_id = label_seq
    label_seq = label_seq + 1
    next_id = label_seq
    label_seq = label_seq + 1
    uword values
    uword body
    values = node_a[choice]
    body = node_b[choice]
    if values == 0 {{
        ; else arm: body, jmp when_end (no next label).
        sws_push(2, 11, endw_id)        ; jmp when_end
        push_block_stmts(body)
        return
    }}
    ; value matches (source order -> reverse the cons).
    uword head
    head = reverse_cons(values)
    uword cell
    cell = head
    repeat {{
        if cell == 0 {{
            break
        }}
        uword v
        v = cons_val[cell]
        if isw != 0 {{
            codegen_word_expr(v)
            out_text("  sta __p8c_wtmp1")
            o_nl()
            out_text("  sty __p8c_wtmp1+1")
            o_nl()
            out_text("  lda __p8c_wtmp0+1")
            o_nl()
            out_text("  cmp __p8c_wtmp1+1")
            o_nl()
            uword skip_id
            skip_id = label_seq
            label_seq = label_seq + 1
            emit_br(0, 14, skip_id)     ; bne when_skip
            out_text("  lda __p8c_wtmp0")
            o_nl()
            out_text("  cmp __p8c_wtmp1")
            o_nl()
            emit_br(1, 12, body_id)     ; beq when_body
            emit_ctrl_label_ref(14, skip_id)
            out_byte($3a)
            o_nl()
        }} else {{
            codegen_byte_expr(v)
            out_text("  cmp __p8c_tmp0")
            o_nl()
            emit_br(1, 12, body_id)     ; beq when_body
        }}
        cell = cons_next[cell]
    }}
    out_text("  jmp ")
    emit_ctrl_label_ref(13, next_id)    ; jmp when_next
    o_nl()
    emit_ctrl_label_ref(12, body_id)    ; when_body:
    out_byte($3a)
    o_nl()
    ; deferred: body stmts, jmp when_end, when_next label.
    sws_push(1, 13, next_id)            ; when_next label (bottom)
    sws_push(2, 11, endw_id)           ; jmp when_end
    push_block_stmts(body)             ; body (top)
}}

; ---- byte expression codegen (work-stack; no recursion) -----
; p8c's _emit_byte_expr_into_a recurses on operands; p1 can't recurse, so
; the tree walk runs on an explicit work stack of tasks (cws_*). The
; leaf-RHS fast path (left-nested chains like a+b+c) needs no spill; a
; non-leaf RHS holds the LHS on the CPU stack across the RHS's evaluation
; (-> __p8c_tmp1), matching the host's dual-scratch-safe sequence.
sub cws_push(ubyte ty, uword nd, ubyte op) {{
    cws_type[cws_sp] = ty
    cws_node[cws_sp] = nd
    cws_op[cws_sp] = op
    cws_sp = cws_sp + 1
}}
; a binop RHS that needs no evaluation (matches p8c's isinstance(rhs,
; (IntLit, Ident)) leaf-path test -- note: NOT BoolLit).
sub is_leaf_rhs(uword e) -> ubyte {{
    ubyte k
    k = node_kind[e]
    if k == ND_INT {{
        return 1
    }}
    if k == ND_IDENT {{
        return 1
    }}
    return 0
}}
; byte expression leaf -> A.
sub emit_byte_leaf_load(uword e) {{
    ubyte k
    k = node_kind[e]
    if k == ND_INT {{
        o_lda() o_imm()
        out_hex2(lsb(node_a[e]))
        o_nl()
        return
    }}
    if k == ND_BOOL {{
        o_lda() o_imm()
        out_hex2(lsb(node_a[e]))
        o_nl()
        return
    }}
    if k == ND_IDENT {{
        o_lda()
        emit_mangled(node_a[e])
        o_nl()
        return
    }}
}}
; emit the right-hand operand text of a byte binop. mode 0: a leaf rhs node
; ("#$XX" for an ND_INT, "p8v_<name>" for a var); mode 1: the __p8c_tmp1
; spill slot (the rhs node is ignored).
sub emit_byte_operand(ubyte mode, uword rhs) {{
    if mode == 0 {{
        if node_kind[rhs] == ND_INT {{
            o_imm()
            out_hex2(lsb(node_a[rhs]))
        }} else {{
            emit_mangled(node_a[rhs])
        }}
    }} else {{
        out_text("__p8c_tmp1")
    }}
}}
; one shift label: ".Lshl_top_<id>" / ".Lshr_end_<id>" etc. (matching p8c's
; _new_label format `.L<prefix>_<id>`). is_left selects shl/shr; is_top top/end.
sub emit_shift_label(ubyte is_left, ubyte is_top, uword id) {{
    if is_left != 0 {{
        if is_top != 0 {{
            out_text(".Lshl_top_")
        }} else {{
            out_text(".Lshl_end_")
        }}
    }} else {{
        if is_top != 0 {{
            out_text(".Lshr_top_")
        }} else {{
            out_text(".Lshr_end_")
        }}
    }}
    out_dec(id)
}}
; A << / >> by a count. Immediate count -> unrolled asl/lsr (count & 7);
; otherwise a runtime loop over the operand (var or __p8c_tmp1), allocating a
; top/end label pair (label_seq, in alloc order top-then-end, like p8c).
sub emit_shift_op(ubyte is_left, ubyte is_imm, ubyte imm_val, ubyte mode, uword rhs) {{
    if is_imm != 0 {{
        ubyte cnt
        cnt = imm_val & 7
        ubyte i
        i = 0
        repeat {{
            if i >= cnt {{
                break
            }}
            if is_left != 0 {{
                out_text("  asl a")
            }} else {{
                out_text("  lsr a")
            }}
            o_nl()
            i = i + 1
        }}
        return
    }}
    uword top_id
    uword end_id
    top_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    out_text("  pha")
    o_nl()
    o_lda()
    emit_byte_operand(mode, rhs)
    o_nl()
    out_text("  tay")
    o_nl()
    out_text("  pla")
    o_nl()
    out_text("  cpy #0")
    o_nl()
    out_text("  beq ")
    emit_shift_label(is_left, 0, end_id)
    o_nl()
    emit_shift_label(is_left, 1, top_id)
    out_byte($3a)
    o_nl()
    if is_left != 0 {{
        out_text("  asl a")
    }} else {{
        out_text("  lsr a")
    }}
    o_nl()
    out_text("  dey")
    o_nl()
    out_text("  bne ")
    emit_shift_label(is_left, 1, top_id)
    o_nl()
    emit_shift_label(is_left, 0, end_id)
    out_byte($3a)
    o_nl()
}}
; the byte-binop core: A op <operand>, where the operand is selected by `mode`
; (0 = leaf rhs node, 1 = __p8c_tmp1 spill). Covers + - & | ^ (carry-correct
; add/sub, bitwise), * (the __p8c_mul_u8 helper -- sets mul_used), and the
; shifts << >>. p8c recurses on operands; p1 reaches this via the work stack.
sub emit_byte_binop_core(ubyte op, ubyte mode, uword rhs) {{
    if op == TK_PLUS {{
        out_text("  clc")
        o_nl()
        out_text("  adc ")
        emit_byte_operand(mode, rhs)
        o_nl()
        return
    }}
    if op == TK_MINUS {{
        out_text("  sec")
        o_nl()
        out_text("  sbc ")
        emit_byte_operand(mode, rhs)
        o_nl()
        return
    }}
    if op == TK_AMP {{
        out_text("  and ")
        emit_byte_operand(mode, rhs)
        o_nl()
        return
    }}
    if op == TK_PIPE {{
        out_text("  ora ")
        emit_byte_operand(mode, rhs)
        o_nl()
        return
    }}
    if op == TK_CARET {{
        out_text("  eor ")
        emit_byte_operand(mode, rhs)
        o_nl()
        return
    }}
    if op == TK_STAR {{
        out_text("  sta __p8c_tmp0")
        o_nl()
        o_lda()
        emit_byte_operand(mode, rhs)
        o_nl()
        out_text("  sta __p8c_tmp1")
        o_nl()
        out_text("  jsr __p8c_mul_u8")
        o_nl()
        mul_used = 1
        return
    }}
    ; shifts: an immediate count (leaf ND_INT) unrolls; everything else loops.
    ubyte is_imm
    ubyte imm_val
    is_imm = 0
    imm_val = 0
    if mode == 0 {{
        if node_kind[rhs] == ND_INT {{
            is_imm = 1
            imm_val = lsb(node_a[rhs])
        }}
    }}
    if op == TK_SHL {{
        emit_shift_op(1, is_imm, imm_val, mode, rhs)
    }} else {{
        emit_shift_op(0, is_imm, imm_val, mode, rhs)
    }}
}}
; emit a byte binop against a leaf operand rhs ("#$XX" or "p8v_<name>").
sub emit_byte_binop_leaf(ubyte op, uword rhs) {{
    emit_byte_binop_core(op, 0, rhs)
}}
; same op against the __p8c_tmp1 spill slot.
sub emit_byte_binop_zp(ubyte op) {{
    emit_byte_binop_core(op, 1, 0)
}}
; apply a unary op to A (operand already evaluated): ~ (eor #$ff), - (two's
; complement), not (bool 0->1 else 0, with a label pair allocated end-first
; to match p8c's _new_label order: .Lnot_end_N then .Lnot_zero_N+1). The
; `not` path is a faithful port but not yet test-reachable: its operand must
; be bool, and the only bool sources (comparisons / logical ops) arrive with
; the next M3 slice -- exercised then.
sub emit_unary_apply(ubyte uncode) {{
    if uncode == UN_INV {{
        out_text("  eor #$ff")
        o_nl()
        return
    }}
    if uncode == UN_NEG {{
        out_text("  eor #$ff")
        o_nl()
        out_text("  clc")
        o_nl()
        out_text("  adc #$01")
        o_nl()
        return
    }}
    ; UN_NOT
    uword end_id
    uword zero_id
    end_id = label_seq
    label_seq = label_seq + 1
    zero_id = label_seq
    label_seq = label_seq + 1
    out_text("  beq .Lnot_zero_")
    out_dec(zero_id)
    o_nl()
    out_text("  lda #$00")
    o_nl()
    out_text("  jmp .Lnot_end_")
    out_dec(end_id)
    o_nl()
    out_text(".Lnot_zero_")
    out_dec(zero_id)
    out_byte($3a)
    o_nl()
    out_text("  lda #$01")
    o_nl()
    out_text(".Lnot_end_")
    out_dec(end_id)
    out_byte($3a)
    o_nl()
}}

; ---- comparison codegen (port of _emit_cmp_into_a) -----------
; A comparison op token (TK_EQ..TK_GE are contiguous 78..83).
sub is_cmp_op(ubyte op) -> ubyte {{
    if op < TK_EQ {{
        return 0
    }}
    if op > TK_GE {{
        return 0
    }}
    return 1
}}
; the short-circuit logical operators `and` / `or` (the keyword tokens).
sub is_logical_op(ubyte op) -> ubyte {{
    if op == TK_KAND {{
        return 1
    }}
    if op == TK_KOR {{
        return 1
    }}
    return 0
}}
; Is a byte operand signed? p8c marks a comparison signed only when BOTH
; operands are exactly the BYTE type; here we resolve a leaf ident's type via
; the symbol table (literals are unsigned). NOTE: nested byte-arith operands
; that p8c would infer as BYTE are treated as unsigned here -- a known gap
; until p1 does full expression typing; the corpus uses leaf operands.
sub is_byte_signed(uword nd) -> ubyte {{
    if node_kind[nd] == ND_IDENT {{
        uword si
        si = find_sym(node_a[nd])
        if si == $ffff {{
            return 0
        }}
        if sym_type[si] == TY_BYTE {{
            return 1
        }}
    }}
    return 0
}}
sub cmp_is_signed(uword e) -> ubyte {{
    if is_byte_signed(node_a[e]) == 0 {{
        return 0
    }}
    if is_byte_signed(node_b[e]) == 0 {{
        return 0
    }}
    return 1
}}
; emit a branch-to-cmp_true line: "  <mnem> .Lcmp_true_<id>".
sub emit_br_true(uword mnem, uword true_id) {{
    out_text("  ")
    out_text(mnem)
    out_byte($20)
    out_text(".Lcmp_true_")
    out_dec(true_id)
    o_nl()
}}
; The comparison tail (operands already in __p8c_tmp0 / __p8c_tmp1): compare
; and materialize 0/1 in A. Labels are allocated here (after the operand eval),
; matching p8c's _new_label order: cmp_true, cmp_end, then any op-specific
; extra (gt_no / sgn_ok / sgt_no).
sub emit_cmp_tail(uword e, ubyte op) {{
    ubyte is_signed
    is_signed = cmp_is_signed(e)
    out_text("  lda __p8c_tmp0")
    o_nl()
    uword true_id
    uword end_id
    uword no_id
    true_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    if is_signed == 0 {{
        out_text("  cmp __p8c_tmp1")
        o_nl()
        if op == TK_EQ {{
            emit_br_true("beq", true_id)
        }}
        if op == TK_NE {{
            emit_br_true("bne", true_id)
        }}
        if op == TK_LT {{
            emit_br_true("bcc", true_id)
        }}
        if op == TK_GE {{
            emit_br_true("bcs", true_id)
        }}
        if op == TK_GT {{
            no_id = label_seq
            label_seq = label_seq + 1
            out_text("  beq .Lgt_no_")
            out_dec(no_id)
            o_nl()
            emit_br_true("bcs", true_id)
            out_text(".Lgt_no_")
            out_dec(no_id)
            out_byte($3a)
            o_nl()
        }}
        if op == TK_LE {{
            emit_br_true("beq", true_id)
            emit_br_true("bcc", true_id)
        }}
    }} else {{
        if op == TK_EQ {{
            out_text("  cmp __p8c_tmp1")
            o_nl()
            emit_br_true("beq", true_id)
        }} else {{
            if op == TK_NE {{
                out_text("  cmp __p8c_tmp1")
                o_nl()
                emit_br_true("bne", true_id)
            }} else {{
                out_text("  sec")
                o_nl()
                out_text("  sbc __p8c_tmp1")
                o_nl()
                uword skip_id
                skip_id = label_seq
                label_seq = label_seq + 1
                out_text("  bvc .Lsgn_ok_")
                out_dec(skip_id)
                o_nl()
                out_text("  eor #$80")
                o_nl()
                out_text(".Lsgn_ok_")
                out_dec(skip_id)
                out_byte($3a)
                o_nl()
                if op == TK_LT {{
                    emit_br_true("bmi", true_id)
                }}
                if op == TK_GE {{
                    emit_br_true("bpl", true_id)
                }}
                if op == TK_GT {{

                    no_id = label_seq
                    label_seq = label_seq + 1
                    out_text("  beq .Lsgt_no_")
                    out_dec(no_id)
                    o_nl()
                    emit_br_true("bpl", true_id)
                    out_text(".Lsgt_no_")
                    out_dec(no_id)
                    out_byte($3a)
                    o_nl()
                }}
                if op == TK_LE {{
                    emit_br_true("beq", true_id)
                    emit_br_true("bmi", true_id)
                }}
            }}
        }}
    }}
    out_text("  lda #$00")
    o_nl()
    out_text("  jmp .Lcmp_end_")
    out_dec(end_id)
    o_nl()
    out_text(".Lcmp_true_")
    out_dec(true_id)
    out_byte($3a)
    o_nl()
    out_text("  lda #$01")
    o_nl()
    out_text(".Lcmp_end_")
    out_dec(end_id)
    out_byte($3a)
    o_nl()
}}

; ---- logical and/or (short-circuit, port of _emit_logical_into_a) -----
; emit the open-label name for the current op (and -> .Land_false_, or ->
; .Lor_true_) and the close-label name (and -> .Land_end_, or -> .Lor_end_).
sub emit_logic_open_name(ubyte op, uword id) {{
    if op == TK_KAND {{
        out_text(".Land_false_")
    }} else {{
        out_text(".Lor_true_")
    }}
    out_dec(id)
}}
sub emit_logic_end_name(ubyte op, uword id) {{
    if op == TK_KAND {{
        out_text(".Land_end_")
    }} else {{
        out_text(".Lor_end_")
    }}
    out_dec(id)
}}
; the short-circuit branch on a freshly-evaluated operand in A: `and` falls
; through on true and bails to false on zero (beq); `or` bails to true on
; non-zero (bne).
sub emit_logic_branch(ubyte op, uword id) {{
    if op == TK_KAND {{
        out_text("  beq ")
    }} else {{
        out_text("  bne ")
    }}
    emit_logic_open_name(op, id)
    o_nl()
}}
; mid task: after the lhs, allocate the label pair (matching p8c's order --
; after lhs eval) and emit the lhs short-circuit branch.
sub emit_logic_mid(ubyte op) {{
    uword id1
    uword id2
    id1 = label_seq
    label_seq = label_seq + 1
    id2 = label_seq
    label_seq = label_seq + 1
    lstk_id1[lstk_sp] = id1
    lstk_id2[lstk_sp] = id2
    lstk_sp = lstk_sp + 1
    emit_logic_branch(op, id1)
}}
; tail task: after the rhs, emit the rhs short-circuit branch and materialize
; 0/1 (and -> rhs true => 1; or -> rhs false => 0).
sub emit_logic_tail(ubyte op) {{
    lstk_sp = lstk_sp - 1
    uword id1
    uword id2
    id1 = lstk_id1[lstk_sp]
    id2 = lstk_id2[lstk_sp]
    emit_logic_branch(op, id1)
    if op == TK_KAND {{
        out_text("  lda #$01")
        o_nl()
    }} else {{
        out_text("  lda #$00")
        o_nl()
    }}
    out_text("  jmp ")
    emit_logic_end_name(op, id2)
    o_nl()
    emit_logic_open_name(op, id1)
    out_byte($3a)
    o_nl()
    if op == TK_KAND {{
        out_text("  lda #$00")
        o_nl()
    }} else {{
        out_text("  lda #$01")
        o_nl()
    }}
    emit_logic_end_name(op, id2)
    out_byte($3a)
    o_nl()
}}
; evaluate a byte expression into A.
sub codegen_byte_expr(uword root) {{
    cws_sp = 0
    cws_push(0, root, 0)
    repeat {{
        if cws_sp == 0 {{
            break
        }}
        cws_sp = cws_sp - 1
        ubyte ty
        uword nd
        ubyte op
        ty = cws_type[cws_sp]
        nd = cws_node[cws_sp]
        op = cws_op[cws_sp]
        if ty == 0 {{
            if node_kind[nd] == ND_BINOP {{
                uword lhs
                uword rhs
                lhs = node_a[nd]
                rhs = node_b[nd]
                if is_cmp_op(node_op[nd]) != 0 {{
                    ; eval(lhs); sta tmp0; eval(rhs); sta tmp1; cmp-tail
                    cws_push(7, nd, node_op[nd])
                    cws_push(3, 0, 0)
                    cws_push(0, rhs, 0)
                    cws_push(8, 0, 0)
                    cws_push(0, lhs, 0)
                }} else {{
                    if is_logical_op(node_op[nd]) != 0 {{
                        ; eval(lhs); logic-mid; eval(rhs); logic-tail
                        cws_push(10, 0, node_op[nd])
                        cws_push(0, rhs, 0)
                        cws_push(9, 0, node_op[nd])
                        cws_push(0, lhs, 0)
                    }} else {{
                        if node_op[nd] == TK_KXOR {{
                            ; eval(lhs); pha; eval(rhs); sta tmp0; pla; eor tmp0
                            cws_push(11, 0, 0)
                            cws_push(4, 0, 0)
                            cws_push(8, 0, 0)
                            cws_push(0, rhs, 0)
                            cws_push(2, 0, 0)
                            cws_push(0, lhs, 0)
                        }} else {{
                            if is_leaf_rhs(rhs) != 0 {{
                                ; eval(lhs); binop_leaf(op, rhs)
                                cws_push(1, rhs, node_op[nd])
                                cws_push(0, lhs, 0)
                            }} else {{
                                ; eval(lhs); pha; eval(rhs); sta tmp1; pla; binop_tmp1
                                cws_push(5, 0, node_op[nd])
                                cws_push(4, 0, 0)
                                cws_push(3, 0, 0)
                                cws_push(0, rhs, 0)
                                cws_push(2, 0, 0)
                                cws_push(0, lhs, 0)
                            }}
                        }}
                    }}
                }}
            }} else {{
                if node_kind[nd] == ND_UNOP {{
                    ; eval(operand); apply-unary(op)
                    cws_push(6, 0, node_op[nd])
                    cws_push(0, node_a[nd], 0)
                }} else {{
                    if node_kind[nd] == ND_MEMAT {{
                        ; @(addr) byte read -- self-contained (result in A)
                        emit_memat_read(nd)
                    }} else {{
                        emit_byte_leaf_load(nd)
                    }}
                }}
            }}
        }} else {{
            if ty == 1 {{
                emit_byte_binop_leaf(op, nd)
            }} else {{
                if ty == 2 {{
                    out_text("  pha")
                    o_nl()
                }} else {{
                    if ty == 3 {{
                        out_text("  sta __p8c_tmp1")
                        o_nl()
                    }} else {{
                        if ty == 4 {{
                            out_text("  pla")
                            o_nl()
                        }} else {{
                            if ty == 5 {{
                                emit_byte_binop_zp(op)
                            }} else {{
                                if ty == 6 {{
                                    emit_unary_apply(op)
                                }} else {{
                                    if ty == 7 {{
                                        emit_cmp_tail(nd, op)
                                    }} else {{
                                        if ty == 8 {{
                                            out_text("  sta __p8c_tmp0")
                                            o_nl()
                                        }} else {{
                                            if ty == 9 {{
                                                emit_logic_mid(op)
                                            }} else {{
                                                if ty == 10 {{
                                                    emit_logic_tail(op)
                                                }} else {{
                                                    out_text("  eor __p8c_tmp0")
                                                    o_nl()
                                                }}
                                            }}
                                        }}
                                    }}
                                }}
                            }}
                        }}
                    }}
                }}
            }}
        }}
    }}
}}
; map an augmented-assignment token to its binop token.
sub aug_to_binop(ubyte op) -> ubyte {{
    if op == TK_PLUSEQ {{
        return TK_PLUS
    }}
    if op == TK_MINUSEQ {{
        return TK_MINUS
    }}
    if op == TK_ANDEQ {{
        return TK_AMP
    }}
    if op == TK_OREQ {{
        return TK_PIPE
    }}
    if op == TK_XOREQ {{
        return TK_CARET
    }}
    if op == TK_SHLEQ {{
        return TK_SHL
    }}
    return TK_SHR       ; TK_SHREQ
}}
; word expression leaf -> A (low) / Y (high), widening ubyte to uword.
sub codegen_word_leaf(uword e) {{
    ubyte k
    k = node_kind[e]
    if k == ND_INT {{
        o_lda() o_imm()
        out_hex2(lsb(node_a[e]))
        o_nl()
        o_ldy() o_imm()
        out_hex2(lsb(node_a[e] >> 8))
        o_nl()
        return
    }}
    if k == ND_IDENT {{
        uword si
        si = find_sym(node_a[e])
        o_lda()
        emit_mangled(node_a[e])
        o_nl()
        if sym_type[si] == TY_UWORD {{
            o_ldy()
            emit_mangled(node_a[e])
            o_plus1()
            o_nl()
        }} else {{
            o_ldy() o_imm()
            out_text("00")
            o_nl()
        }}
        return
    }}
    if k == ND_STR {{
        ; a string literal is its pool address. Assign the next label number
        ; (encounter order) and record its str id for the pool trailer.
        uword lbl
        lbl = strpool_count
        strpool_sid[lbl] = node_a[e]
        strpool_count = strpool_count + 1
        out_text("  lda #<p8c_str_")
        out_dec(lbl)
        o_nl()
        out_text("  ldy #>p8c_str_")
        out_dec(lbl)
        o_nl()
        return
    }}
}}

sub wws_push(ubyte ty, uword nd, ubyte op) {{
    wws_type[wws_sp] = ty
    wws_node[wws_sp] = nd
    wws_op[wws_sp] = op
    wws_sp = wws_sp + 1
}}
; &name (address-of) -> a uword value (lda #< / ldy #> the mangled label).
sub emit_addrof(uword e) {{
    out_text("  lda #<")
    emit_mangled(node_a[e])
    o_nl()
    out_text("  ldy #>")
    emit_mangled(node_a[e])
    o_nl()
}}
; the combine tail of a word + / - / & | ^ binop: LHS in A:Y, RHS in
; __p8c_wtmp0; result back into A:Y. (Port of _emit_word_binop_into_ay's
; arithmetic/bitwise arms.)
sub emit_word_combine(ubyte op) {{
    if op == TK_PLUS {{
        out_text("  clc")
        o_nl()
        out_text("  adc __p8c_wtmp0")
        o_nl()
        out_text("  pha")
        o_nl()
        out_text("  tya")
        o_nl()
        out_text("  adc __p8c_wtmp0+1")
        o_nl()
        out_text("  tay")
        o_nl()
        out_text("  pla")
        o_nl()
        return
    }}
    if op == TK_MINUS {{
        out_text("  sec")
        o_nl()
        out_text("  sbc __p8c_wtmp0")
        o_nl()
        out_text("  pha")
        o_nl()
        out_text("  tya")
        o_nl()
        out_text("  sbc __p8c_wtmp0+1")
        o_nl()
        out_text("  tay")
        o_nl()
        out_text("  pla")
        o_nl()
        return
    }}
    ; bitwise & | ^ : and / ora / eor on both bytes.
    out_text("  ")
    emit_bitwise_mnem(op)
    out_text(" __p8c_wtmp0")
    o_nl()
    out_text("  pha")
    o_nl()
    out_text("  tya")
    o_nl()
    out_text("  ")
    emit_bitwise_mnem(op)
    out_text(" __p8c_wtmp0+1")
    o_nl()
    out_text("  tay")
    o_nl()
    out_text("  pla")
    o_nl()
}}
sub emit_bitwise_mnem(ubyte op) {{
    if op == TK_AMP {{
        out_text("and")
    }} else {{
        if op == TK_PIPE {{
            out_text("ora")
        }} else {{
            out_text("eor")
        }}
    }}
}}
; apply a word unary op (~ or -) to A:Y (operand already evaluated).
sub emit_word_unary(ubyte uncode) {{
    out_text("  eor #$ff")
    o_nl()
    out_text("  sta __p8c_wtmp0")
    o_nl()
    out_text("  tya")
    o_nl()
    out_text("  eor #$ff")
    o_nl()
    out_text("  tay")
    o_nl()
    out_text("  lda __p8c_wtmp0")
    o_nl()
    if uncode == UN_NEG {{
        out_text("  clc")
        o_nl()
        out_text("  adc #$01")
        o_nl()
        out_text("  bcc *+3")
        o_nl()
        out_text("  iny")
        o_nl()
    }}
}}
; dispatch a word-expression node onto the word work stack.
; ---- word shifts (port of _emit_word_shl / _emit_word_shr) ----
; one A:Y<<1 step (lo in A, hi in Y): asl low, rol high, through wtmp0.
sub emit_wshl_step() {{
    out_text("  asl a")
    o_nl()
    out_text("  sta __p8c_wtmp0")
    o_nl()
    out_text("  tya")
    o_nl()
    out_text("  rol a")
    o_nl()
    out_text("  tay")
    o_nl()
    out_text("  lda __p8c_wtmp0")
    o_nl()
}}
; A:Y << n for a constant n (operand already in A:Y). n is value & $0f.
sub emit_wshl_const(ubyte n) {{
    if n == 0 {{
        return
    }}
    ubyte i
    if n >= 8 {{
        out_text("  tay")              ; low -> high
        o_nl()
        out_text("  lda #$00")         ; new low = 0
        o_nl()
        i = 8
        repeat {{
            if i >= n {{
                break
            }}
            emit_wshl_step()
            i = i + 1
        }}
        return
    }}
    i = 0
    repeat {{
        if i >= n {{
            break
        }}
        emit_wshl_step()
        i = i + 1
    }}
}}
; one A:Y>>1 step for the 1<=n<8 case (sty wtmp0+1; sta wtmp0; lsr/ror; reload).
sub emit_wshr_step_lo() {{
    out_text("  sty __p8c_wtmp0+1")
    o_nl()
    out_text("  sta __p8c_wtmp0")
    o_nl()
    out_text("  lsr __p8c_wtmp0+1")
    o_nl()
    out_text("  ror __p8c_wtmp0")
    o_nl()
    out_text("  lda __p8c_wtmp0")
    o_nl()
    out_text("  ldy __p8c_wtmp0+1")
    o_nl()
}}
; one A:Y>>1 step for the n>=8 case (note p8c's swapped sty/sta order here).
sub emit_wshr_step_hi() {{
    out_text("  sty __p8c_wtmp0")
    o_nl()
    out_text("  sta __p8c_wtmp0+1")
    o_nl()
    out_text("  lsr __p8c_wtmp0+1")
    o_nl()
    out_text("  ror __p8c_wtmp0")
    o_nl()
    out_text("  lda __p8c_wtmp0")
    o_nl()
    out_text("  ldy __p8c_wtmp0+1")
    o_nl()
}}
; A:Y >> n for a constant n (operand already in A:Y). Logical shift right.
sub emit_wshr_const(ubyte n) {{
    if n == 0 {{
        return
    }}
    ubyte i
    if n >= 8 {{
        out_text("  tya")              ; high -> low
        o_nl()
        out_text("  ldy #$00")         ; new high = 0
        o_nl()
        i = 8
        repeat {{
            if i >= n {{
                break
            }}
            emit_wshr_step_hi()
            i = i + 1
        }}
        return
    }}
    i = 0
    repeat {{
        if i >= n {{
            break
        }}
        emit_wshr_step_lo()
        i = i + 1
    }}
}}
; ".Lwshl_top_N" / ".Lwshr_end_N" etc.
sub emit_wshift_label(ubyte is_left, ubyte is_top, uword id) {{
    if is_left != 0 {{
        if is_top != 0 {{
            out_text(".Lwshl_top_")
        }} else {{
            out_text(".Lwshl_end_")
        }}
    }} else {{
        if is_top != 0 {{
            out_text(".Lwshr_top_")
        }} else {{
            out_text(".Lwshr_end_")
        }}
    }}
    out_dec(id)
}}
; variable-count shift tail: LHS already in __p8c_wtmp0 (lo,hi). Evaluate the
; count into A (-> X) and loop. NOTE: the count goes through codegen_byte_expr,
; which resets the byte work stack -- safe at top level, but a word shift with
; a non-leaf count nested inside a byte expr's @() address would corrupt it.
sub emit_wshift_var_tail(uword nd, ubyte is_left) {{
    codegen_byte_expr(node_b[nd])
    out_text("  tax")
    o_nl()
    uword top_id
    uword end_id
    top_id = label_seq
    label_seq = label_seq + 1
    end_id = label_seq
    label_seq = label_seq + 1
    out_text("  cpx #$00")
    o_nl()
    out_text("  beq ")
    emit_wshift_label(is_left, 0, end_id)
    o_nl()
    emit_wshift_label(is_left, 1, top_id)
    out_byte($3a)
    o_nl()
    if is_left != 0 {{
        out_text("  asl __p8c_wtmp0")
        o_nl()
        out_text("  rol __p8c_wtmp0+1")
        o_nl()
    }} else {{
        out_text("  lsr __p8c_wtmp0+1")
        o_nl()
        out_text("  ror __p8c_wtmp0")
        o_nl()
    }}
    out_text("  dex")
    o_nl()
    out_text("  bne ")
    emit_wshift_label(is_left, 1, top_id)
    o_nl()
    emit_wshift_label(is_left, 0, end_id)
    out_byte($3a)
    o_nl()
    out_text("  lda __p8c_wtmp0")
    o_nl()
    out_text("  ldy __p8c_wtmp0+1")
    o_nl()
}}
; dispatch a word shift: const count (IntLit 0..16) unrolls; else loop. The
; const path evaluates the lhs then unrolls; the variable path stashes the lhs
; into wtmp0 first (STA_WTMP0 task), then the tail evaluates the count + loops.
sub word_dispatch_shift(uword nd, ubyte is_left) {{
    uword rhsn
    rhsn = node_b[nd]
    if node_kind[rhsn] == ND_INT {{
        if node_a[rhsn] <= 16 {{
            ubyte n
            n = lsb(node_a[rhsn]) & $0f
            if is_left != 0 {{
                wws_push(5, 0, n)
            }} else {{
                wws_push(6, 0, n)
            }}
            wws_push(0, node_a[nd], 0)
            return
        }}
    }}
    if is_left != 0 {{
        wws_push(7, nd, 0)
    }} else {{
        wws_push(8, nd, 0)
    }}
    wws_push(4, 0, 0)
    wws_push(0, node_a[nd], 0)
}}
sub word_dispatch(uword nd) {{
    ubyte k
    k = node_kind[nd]
    if k == ND_ADDROF {{
        emit_addrof(nd)
        return
    }}
    if k == ND_BINOP {{
        ubyte bop
        bop = node_op[nd]
        if bop == TK_SHL {{
            word_dispatch_shift(nd, 1)
            return
        }}
        if bop == TK_SHR {{
            word_dispatch_shift(nd, 0)
            return
        }}
        ; arithmetic / bitwise: eval lhs; save; eval rhs; stash; combine.
        wws_push(3, 0, bop)
        wws_push(2, 0, 0)
        wws_push(0, node_b[nd], 0)
        wws_push(1, 0, 0)
        wws_push(0, node_a[nd], 0)
        return
    }}
    if k == ND_UNOP {{
        wws_push(11, 0, node_op[nd])
        wws_push(0, node_a[nd], 0)
        return
    }}
    ; leaf: int / ident / string
    codegen_word_leaf(nd)
}}
; evaluate a uword expression into A (low) / Y (high), on the word work stack
; (no recursion). Port of _emit_word_expr_into_ay + _emit_word_binop_into_ay.
; Covers leaves, `&name`, the arithmetic/bitwise binops (+ - & | ^), and the
; word unary ~ / -. (Shifts, comparison, indexing, calls arrive next.)
sub codegen_word_expr(uword root) {{
    wws_sp = 0
    wws_push(0, root, 0)
    repeat {{
        if wws_sp == 0 {{
            break
        }}
        wws_sp = wws_sp - 1
        ubyte ty
        uword nd
        ubyte op
        ty = wws_type[wws_sp]
        nd = wws_node[wws_sp]
        op = wws_op[wws_sp]
        if ty == 0 {{
            word_dispatch(nd)
        }} else {{
            if ty == 1 {{
                ; save LHS (A:Y) on the CPU stack across the RHS eval
                out_text("  pha")
                o_nl()
                out_text("  tya")
                o_nl()
                out_text("  pha")
                o_nl()
            }} else {{
                if ty == 2 {{
                    ; RHS -> wtmp0; restore LHS to A:Y
                    out_text("  sta __p8c_wtmp0")
                    o_nl()
                    out_text("  sty __p8c_wtmp0+1")
                    o_nl()
                    out_text("  pla")
                    o_nl()
                    out_text("  tay")
                    o_nl()
                    out_text("  pla")
                    o_nl()
                }} else {{
                    if ty == 3 {{
                        emit_word_combine(op)
                    }} else {{
                        if ty == 4 {{
                            ; LHS -> wtmp0 (for the variable-shift loop)
                            out_text("  sta __p8c_wtmp0")
                            o_nl()
                            out_text("  sty __p8c_wtmp0+1")
                            o_nl()
                        }} else {{
                            if ty == 5 {{
                                emit_wshl_const(op)
                            }} else {{
                                if ty == 6 {{
                                    emit_wshr_const(op)
                                }} else {{
                                    if ty == 7 {{
                                        emit_wshift_var_tail(nd, 1)
                                    }} else {{
                                        if ty == 8 {{
                                            emit_wshift_var_tail(nd, 0)
                                        }} else {{
                                            emit_word_unary(op)
                                        }}
                                    }}
                                }}
                            }}
                        }}
                    }}
                }}
            }}
        }}
    }}
}}

; ---- @() memory read (byte) ---------------------------------
; @(IntLit) -> a direct absolute load; @(<word expr>) -> evaluate the address
; into __p8c_ptr0 and load via (ptr0),y.
sub emit_memat_read(uword nd) {{
    uword addr
    addr = node_a[nd]
    if node_kind[addr] == ND_INT {{
        out_text("  lda $")
        out_hex4(node_a[addr])
        o_nl()
        return
    }}
    codegen_word_expr(addr)
    out_text("  sta __p8c_ptr0")
    o_nl()
    out_text("  sty __p8c_ptr0+1")
    o_nl()
    out_text("  ldy #$00")
    o_nl()
    out_text("  lda (__p8c_ptr0),y")
    o_nl()
}}

; sym-addressed loads/stores.
sub emit_lda_sym(uword si) {{
    o_lda()
    emit_mangled(sym_ident[si])
    o_nl()
}}
sub emit_sta_sym(uword si) {{
    o_sta()
    emit_mangled(sym_ident[si])
    o_nl()
}}
sub emit_sty_sym_hi(uword si) {{
    o_sty()
    emit_mangled(sym_ident[si])
    o_plus1()
    o_nl()
}}

; ---- @() memory write (byte): @(addr) = byteexpr -----------
; @(IntLit) = e  -> eval e, sta absolute. @(<word expr>) = e -> eval e into
; __p8c_tmp0, evaluate the address into __p8c_ptr0, sta (ptr0),y.
sub codegen_assign_memat(uword st, uword target) {{
    uword rhs
    uword addr
    rhs = node_b[st]
    addr = node_a[target]
    if node_kind[addr] == ND_INT {{
        codegen_byte_expr(rhs)
        out_text("  sta $")
        out_hex4(node_a[addr])
        o_nl()
        return
    }}
    codegen_byte_expr(rhs)
    out_text("  sta __p8c_tmp0")
    o_nl()
    codegen_word_expr(addr)
    out_text("  sta __p8c_ptr0")
    o_nl()
    out_text("  sty __p8c_ptr0+1")
    o_nl()
    out_text("  ldy #$00")
    o_nl()
    out_text("  lda __p8c_tmp0")
    o_nl()
    out_text("  sta (__p8c_ptr0),y")
    o_nl()
}}

; ---- assignment codegen -------------------------------------
; target is a plain (module) var or @(addr). `=` of a byte expression
; (arithmetic + - & | ^ * << >> cmp logical, leaf or nested) with
; ubyte->uword widening on word stores; `=` of a word expr; byte augmented
; (+= -= &= |= ^= <<= >>=) with a leaf operand.
sub codegen_assign(uword st) {{
    uword target
    uword rhs
    ubyte op
    target = node_a[st]
    op = node_op[st]
    rhs = node_b[st]
    if node_kind[target] == ND_MEMAT {{
        codegen_assign_memat(st, target)
        return
    }}
    uword si
    si = find_sym(node_a[target])
    ubyte ttype
    ttype = sym_type[si]
    if op == TK_ASSIGN {{
        if ttype == TY_UWORD {{
            codegen_word_expr(rhs)
            emit_sta_sym(si)
            emit_sty_sym_hi(si)
        }} else {{
            codegen_byte_expr(rhs)
            emit_sta_sym(si)
        }}
        return
    }}
    ; augmented. For a uword target, p8c rewrites `w op= e` to `w = w op e`
    ; and runs the word evaluator on that synthetic binop (matching its
    ; _emit_assign); build the same node and store the A:Y result.
    if ttype == TY_UWORD {{
        uword synth
        synth = new_node(ND_BINOP, aug_to_binop(op), target, rhs)
        codegen_word_expr(synth)
        emit_sta_sym(si)
        emit_sty_sym_hi(si)
        return
    }}
    ; byte augmented: lda LHS; <op> leaf-operand; sta LHS.
    emit_lda_sym(si)
    emit_byte_binop_leaf(aug_to_binop(op), rhs)
    emit_sta_sym(si)
}}

; ---- main: the multi-pass codegen driver --------------------
; Pass A parses directives + module decls. Pass S (build_symbols) fixes
; every module var's ZP address. Then: prologue, ZP bindings, pass M
; (find + codegen `main`), trailers. (Pass B -- non-main subs -- and the
; symbol-table per-sub locals arrive at later milestones.)
main {{
    uword fn
    fn = _argv(0)
    src_hand = _open(fn)
    fn = _argv(1)
    dst_hand = _openout(fn)

    reset_arena()
    prog_address = $4000
    prog_target = 0
    prog_imports = 0
    prog_vars = 0
    prog_enums = 0
    prog_structs = 0
    prog_subs = 0

    ; ---- pass A: directives + module decls (sub bodies skipped) ----
    reset_source()
    lex_init()
    parse_decls_pass()

    ; ---- pass S: symbol table + ZP allocation ----
    build_symbols()

    ; ---- prologue + ZP bindings ----
    emit_prologue()
    emit_zp_bindings()

    ; ---- pass M: find `main` and codegen its body ----
    ; reset_nodes (not reset_arena): keep the persistent ident/str pools so
    ; the symbol table's ident ids stay valid as main is re-lexed.
    reset_source()
    reset_nodes()
    lex_init()
    strpool_count = 0
    mul_used = 0
    label_seq = 0
    lstk_sp = 0
    uword mainbody
    mainbody = 0
    repeat {{
        ubyte t
        t = cur_kind()
        if t == TK_EOF {{
            break
        }}
        if t == TK_KMAIN {{
            uword mnode
            mnode = parse_main()
            mainbody = node_c[mnode]
            break
        }}
        advance()
    }}
    emit_main(mainbody)

    ; ---- mul helper + string pool + trailers ----
    emit_mul_helper()
    emit_string_pool()
    emit_trailers()

    _close(src_hand)
    _close(dst_hand)
}}
"""

header = (
    "; p1.p8 -- the self-hosting Prog8 compiler (Phase 7).\n"
    ";\n"
    "; GENERATED by p1/build_p1.py -- do not edit by hand; edit the generator\n"
    "; and rerun `python3 p1/build_p1.py`. Fixed assembly text is emitted via\n"
    "; out_text() over pooled string literals (p8c's string-literal-as-data).\n"
    ";\n"
    "; Compiles a .p8 source (argv[0]) to 6502 assembly text (argv[1]),\n"
    "; byte-identical to `python3 -m p8c source.p8 -o` (the oracle). The\n"
    "; front-end (lexer + shunting-yard expression parser + frame-stack\n"
    "; statement driver + node arena) is spliced in from stmt.p8; the AST\n"
    "; serializer is replaced by the codegen back-end below.\n"
    ";\n"
    "; Milestones (see ../PHASE7_DESIGN.md): P7-M1 skeleton (main {} -> prologue\n"
    "; + empty p8s_main + nmos exit + reset vector); P7-M2 module vars + simple\n"
    "; assignment (symbol table + ZP bindings + leaf/augmented assignment).\n"
)


def main():
    lines = STMT.read_text().split("\n")
    ser_idx = next(i for i, ln in enumerate(lines)
                   if ln.strip() == "; ---- serialization ----")
    frontend = lines[:ser_idx]
    while frontend and frontend[-1].strip() == "":
        frontend.pop()
    # drop stmt.p8's leading comment block (replaced by p1's header)
    j = 0
    while j < len(frontend) and (frontend[j].startswith(";")
                                 or frontend[j].strip() == ""):
        j += 1
    frontend_body = "\n".join(frontend[j:])

    # Inject the symbol-table module state right after the program-structure
    # state block (so it sits with the rest of the module state).
    marker = "; serializer work stack"
    sym_state = (
        "; ---- codegen symbol table (persistent across passes) ----\n"
        "uword[96] sym_ident      ; module var ident id\n"
        "ubyte[96] sym_type       ; type tag (TY_UBYTE / TY_BYTE / TY_UWORD)\n"
        "uword[96] sym_addr       ; ZP address\n"
        "ubyte sym_count\n"
        "uword zp_next            ; ZP bump allocator (from $40)\n"
        "; string pool: one label per string-literal *occurrence*, numbered\n"
        "; in codegen encounter order (matching p8c's sema-walk order); the\n"
        "; recorded str id indexes the parser's str_pool for the trailer.\n"
        "uword[64] strpool_sid    ; str id for label N (p8c_str_N)\n"
        "uword strpool_count\n"
        "; byte-expression codegen work stack (replaces p8c's recursion):\n"
        "; per entry a task -- 0 eval node, 1 binop-leaf, 2 pha, 3 sta tmp1,\n"
        "; 4 pla, 5 binop-tmp1.\n"
        "ubyte[96] cws_type\n"
        "uword[96] cws_node\n"
        "ubyte[96] cws_op\n"
        "ubyte cws_sp\n"
        "; word-expression codegen work stack (separate from the byte stack so\n"
        "; a byte expression's @() address can drive a word eval without\n"
        "; corrupting the byte stack -- the two never share state).\n"
        "ubyte[96] wws_type\n"
        "uword[96] wws_node\n"
        "ubyte[96] wws_op\n"
        "ubyte wws_sp\n"
        "; statement work stack (control flow without recursion): a task is\n"
        "; 0=emit stmt node, 1=emit label .L<kind>_<id>:, 2=emit jmp to it,\n"
        "; 3=pop the loop-label stack.\n"
        "ubyte[128] sws_type\n"
        "uword[128] sws_a\n"
        "uword[128] sws_b\n"
        "ubyte sws_sp\n"
        "; loop-label stack for break/continue (break -> bk kind/id, continue\n"
        "; -> ck kind/id), pushed per loop.\n"
        "ubyte[16] lp_bk\n"
        "uword[16] lp_bi\n"
        "ubyte[16] lp_ck\n"
        "uword[16] lp_ci\n"
        "ubyte lp_sp\n"
        "; short-circuit and/or label stack: a label-id pair is allocated mid-\n"
        "; evaluation (after the lhs) and consumed by the tail (after the rhs);\n"
        "; LIFO nesting matches the work-stack task order.\n"
        "uword[32] lstk_id1\n"
        "uword[32] lstk_id2\n"
        "ubyte lstk_sp\n"
        "; codegen scratch flags/counters (reset before pass M):\n"
        "ubyte mul_used           ; `*` was emitted -> emit __p8c_mul_u8 trailer\n"
        "uword label_seq          ; global local-label counter (p8c's _label_id)\n\n"
    )
    assert marker in frontend_body, "could not find serializer-state marker"
    frontend_body = frontend_body.replace(marker, sym_state + marker, 1)
    frontend_body = shrink_arenas(frontend_body)

    OUT.write_text(header + "\n" + frontend_body + "\n" + codegen)
    print(f"wrote {OUT} ({len(OUT.read_text().splitlines())} lines)")


if __name__ == "__main__":
    main()

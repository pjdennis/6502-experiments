; stmt.p8 -- the Prog8 statement + whole-program parser port (Phase 6, M3).
;
; Reads a whole .p8 program (argv[0]) and writes its canonical AST
; serialization -- the full `(program ...)` form (argv[1]), byte-identical
; to the Python oracle (p8c/serialize.py::serialize). Verified against the
; STMT_PROGRAMS corpus.
;
; Builds on expr.p8: same no-recursion design (shunting-yard expression
; parser, struct-of-arrays node arena, explicit work-stack serializer),
; but now with uword arenas/indices (p8c gained 16-bit arrays), the full
; keyword set, a top-level program parser, and the frame-stack statement
; driver (port of parse.py::parse_block_iter).

%target nmos
%address $0200

; ---- token kinds ----
const ubyte TK_EOF    = 0
const ubyte TK_INT    = 1
const ubyte TK_STR    = 2
const ubyte TK_IDENT  = 3
const ubyte TK_DIRECTIVE = 4
const ubyte TK_TRUE   = 5
const ubyte TK_FALSE  = 6
const ubyte TK_KNOT   = 7
const ubyte TK_KAND   = 8
const ubyte TK_KOR    = 9
const ubyte TK_KXOR   = 10
const ubyte TK_LPAREN = 11
const ubyte TK_RPAREN = 12
const ubyte TK_DOT    = 13
const ubyte TK_COMMA  = 14
const ubyte TK_LBRACK = 15
const ubyte TK_RBRACK = 16
const ubyte TK_AT     = 17
const ubyte TK_LBRACE = 18
const ubyte TK_RBRACE = 19
const ubyte TK_ARROW  = 20        ; ->
; keyword kinds
const ubyte TK_KUBYTE = 40
const ubyte TK_KBYTE  = 41
const ubyte TK_KUWORD = 42
const ubyte TK_KBOOL  = 43
const ubyte TK_KVOID  = 44
const ubyte TK_KSTR   = 45
const ubyte TK_KSUB   = 46
const ubyte TK_KASMSUB= 47
const ubyte TK_KINLINE= 48
const ubyte TK_KMAIN  = 49
const ubyte TK_KIF    = 50
const ubyte TK_KELSE  = 51
const ubyte TK_KWHILE = 52
const ubyte TK_KFOR   = 53
const ubyte TK_KIN    = 54
const ubyte TK_KTO    = 55
const ubyte TK_KREPEAT= 56
const ubyte TK_KBREAK = 57
const ubyte TK_KCONTINUE = 58
const ubyte TK_KRETURN= 59
const ubyte TK_KDEFER = 60
const ubyte TK_KWHEN  = 61
const ubyte TK_KCONST = 62
const ubyte TK_KENUM  = 63
const ubyte TK_KSTRUCT= 64
; operator punctuation
const ubyte TK_PLUS   = 70
const ubyte TK_MINUS  = 71
const ubyte TK_STAR   = 72
const ubyte TK_AMP    = 73
const ubyte TK_PIPE   = 74
const ubyte TK_CARET  = 75
const ubyte TK_SHL    = 76
const ubyte TK_SHR    = 77
const ubyte TK_EQ     = 78
const ubyte TK_NE     = 79
const ubyte TK_LT     = 80
const ubyte TK_LE     = 81
const ubyte TK_GT     = 82
const ubyte TK_GE     = 83
const ubyte TK_TILDE  = 84
; assignment operators
const ubyte TK_ASSIGN = 90        ; =
const ubyte TK_PLUSEQ = 91
const ubyte TK_MINUSEQ= 92
const ubyte TK_ANDEQ  = 93
const ubyte TK_OREQ   = 94
const ubyte TK_XOREQ  = 95
const ubyte TK_SHLEQ  = 96
const ubyte TK_SHREQ  = 97
const ubyte TK_OTHER  = 120

; ---- node kinds ----
const ubyte ND_INT   = 1
const ubyte ND_STR   = 2
const ubyte ND_BOOL  = 3
const ubyte ND_IDENT = 4
const ubyte ND_BINOP = 5
const ubyte ND_UNOP  = 6
const ubyte ND_CALL  = 7
const ubyte ND_INDEX = 8
const ubyte ND_MEMAT = 9
const ubyte ND_ADDROF= 10
const ubyte ND_BLOCK = 11   ; a=stmt cons head
const ubyte ND_EXPRSTMT = 12 ; a=expr
const ubyte ND_VARDECL = 13 ; op=type tag, a=name id, b=init(0=none), c=arrsize(0=scalar)
const ubyte ND_ASSIGN = 14  ; op=assign code, a=target, b=rhs
const ubyte ND_IF    = 15   ; a=cond, b=then block, c=else block(0=none)
const ubyte ND_WHILE = 16   ; a=cond, b=body
const ubyte ND_FOR   = 17   ; a=var id, b=lo, c=hi, d=body
const ubyte ND_REPEAT= 18   ; a=count(0=forever), b=body
const ubyte ND_WHEN  = 19   ; a=expr, b=choices cons head
const ubyte ND_WHENCHOICE = 20 ; a=values cons head (0=else), b=body
const ubyte ND_BREAK = 21
const ubyte ND_CONTINUE = 22
const ubyte ND_RETURN= 23   ; a=value(0=none)
const ubyte ND_DEFER = 24   ; a=stmt
const ubyte ND_INLINEASM = 25 ; a=str id
const ubyte ND_SUB   = 26   ; op=kind, a=name id, b=params cons head, c=body, d=ret tag
const ubyte ND_PARAM = 27   ; op=type tag, a=name id
const ubyte ND_ENUM  = 28   ; a=name id, b=members cons head
const ubyte ND_ENUMMEMBER = 29 ; op=has_value, a=name id, b=value
const ubyte ND_STRUCT= 30   ; a=name id, b=fields cons head
const ubyte ND_FIELD = 31   ; op=type tag, a=field name id

; type tags
const ubyte TY_UBYTE = 0
const ubyte TY_BYTE  = 1
const ubyte TY_UWORD = 2
const ubyte TY_BOOL  = 3
const ubyte TY_VOID  = 4
const ubyte TY_STR   = 5
const ubyte TY_CONST_UBYTE = 6
const ubyte TY_CONST_BYTE  = 7
const ubyte TY_CONST_UWORD = 8
const ubyte TY_STRUCT      = 9   ; struct-typed var; struct name id in node_d

; sub kinds
const ubyte SUBK_SUB    = 0
const ubyte SUBK_MAIN   = 1
const ubyte SUBK_INLINE = 2
const ubyte SUBK_ASMSUB = 3

; unary op-ids
const ubyte UN_NEG = 0
const ubyte UN_NOT = 1
const ubyte UN_INV = 2

; op-stack record kinds (markers >= OPK_LPAREN)
const ubyte OPK_BINOP  = 0
const ubyte OPK_UNOP   = 1
const ubyte OPK_LPAREN = 2
const ubyte OPK_MEMAT  = 3
const ubyte OPK_CALL   = 4
const ubyte OPK_LBRACK = 5

const ubyte UNARY_PREC = 110

; frame kinds
const ubyte FR_ROOT   = 0
const ubyte FR_THEN   = 1
const ubyte FR_ELSE   = 2
const ubyte FR_WHILE  = 3
const ubyte FR_FOR    = 4
const ubyte FR_REPEAT = 5
const ubyte FR_WHEN   = 6
const ubyte FR_CHOICE = 7

; ---- module state ----
ubyte src_hand
ubyte dst_hand
ubyte peek_buf
ubyte peek_ok
ubyte src_eof

; streaming lexer: a 2-token lookahead window (tk0 = current, tk1 = next)
; instead of a whole-program token array, so arbitrarily large programs
; fit. next_raw_token() produces one token into ntok_*.
ubyte tk0_kind
uword tk0_val
ubyte tk1_kind
uword tk1_val
ubyte ntok_kind
uword ntok_val

; identifier text pool (reset per top-level unit while streaming)
ubyte[6144] ident_pool
uword[768]  ident_off
uword[768]  ident_len
uword ident_count
uword ident_pool_len

; string literal pool
ubyte[4096] str_pool
uword[256]  str_off
uword[256]  str_len
uword str_count
uword str_pool_len

ubyte[64] name_buf
ubyte[96] path_buf       ; parser's dotted-path buffer (lexer owns name_buf)
uword path_len
uword name_len

uword int_val

; node arena
ubyte[640] node_kind
ubyte[640] node_op
uword[640] node_a
uword[640] node_b
uword[640] node_c
uword[640] node_d
uword node_count

; expression stacks
uword[128] operand_stack
uword operand_sp
ubyte[128] op_kind
ubyte[128] op_op
ubyte[128] op_prec
uword[128] op_a
uword[128] op_b
uword[128] op_floor
uword op_sp

; cons cells
uword[640] cons_val
uword[640] cons_next
uword cons_count

; statement frame stack
ubyte[64] fr_kind
ubyte[64] fr_mode        ; 0=stmts, 1=choices
uword[64] fr_stmts       ; cons head (reversed)
ubyte[64] fr_defer       ; 1 if defer-prefixed
uword[64] fr_cond        ; cond / when-expr / repeat-count
uword[64] fr_then        ; saved then block (else frame)
uword[64] fr_var
uword[64] fr_lo
uword[64] fr_hi
uword[64] fr_choices     ; when: choices cons head
uword[64] fr_values      ; when_choice: values cons head
ubyte fr_sp
ubyte pending_defer

; program structure
uword prog_address
ubyte prog_target        ; 0=wendy2c, 1=nmos
uword prog_imports       ; cons of ident ids (reversed)
uword prog_vars          ; cons of vardecl node ids (reversed)
uword prog_enums         ; cons of enum node ids (reversed)
uword prog_structs       ; cons of struct node ids (reversed)
uword prog_subs          ; cons of sub node ids (reversed)

; serializer work stack
ubyte[256] ws_type       ; 0=node,1=close,2=newline,3=field line,4=literal text
uword[256] ws_node
ubyte[256] ws_depth
uword ws_sp

uword dec_v
ubyte dec_started


; ---- syscall asmsubs ----
asmsub _exit(ubyte code) = $F00F
asmsub _close(ubyte handle) = $F015
sub _argv(ubyte i) -> uword {
    %asm{{ "lda p8v__argv_arg_i\njsr $f01e\npha\ntxa\ntay\npla\nrts" }}
}
sub _open(uword filename) -> ubyte {
    %asm{{ "lda p8v__open_arg_filename\nldx p8v__open_arg_filename+1\njsr $f012\nrts" }}
}
sub _openout(uword filename) -> ubyte {
    %asm{{ "lda p8v__openout_arg_filename\nldx p8v__openout_arg_filename+1\njsr $f021\nrts" }}
}
sub _read(ubyte handle) -> ubyte {
    %asm{{ "lda p8v__read_arg_handle\njsr $f018\nbcc .ok\nlda #1\nsta p8v_src_eof\nlda #0\nrts\n.ok:\nsta __p8c_tmp0\nlda #0\nsta p8v_src_eof\nlda __p8c_tmp0\nrts" }}
}
sub _write(ubyte b, ubyte handle) {
    %asm{{ "ldx p8v__write_arg_handle\nlda p8v__write_arg_b\njsr $f024\nrts" }}
}

; ---- I/O (sticky-EOF; emulator rewinds on EOF) ----
sub read_src() -> ubyte {
    if peek_ok != 0 {
        peek_ok = 0
        return peek_buf
    }
    if src_eof != 0 {
        return 0
    }
    return _read(src_hand)
}
sub peek_src() -> ubyte {
    if peek_ok != 0 {
        return peek_buf
    }
    if src_eof != 0 {
        return 0
    }
    ubyte b
    b = _read(src_hand)
    if src_eof != 0 {
        return 0
    }
    peek_buf = b
    peek_ok = 1
    return peek_buf
}
sub out_byte(ubyte b) {
    _write(b, dst_hand)
}

; ---- character classes ----
sub is_digit(ubyte c) -> ubyte {
    if c >= $30 {
        if c <= $39 {
            return 1
        }
    }
    return 0
}
sub is_alpha_us(ubyte c) -> ubyte {
    if c >= $61 {
        if c <= $7a {
            return 1
        }
    }
    if c >= $41 {
        if c <= $5a {
            return 1
        }
    }
    if c == $5f {
        return 1
    }
    return 0
}
sub is_alnum_us(ubyte c) -> ubyte {
    if is_alpha_us(c) != 0 {
        return 1
    }
    return is_digit(c)
}
sub is_hexdig(ubyte c) -> ubyte {
    if is_digit(c) != 0 {
        return 1
    }
    if c >= $61 {
        if c <= $66 {
            return 1
        }
    }
    if c >= $41 {
        if c <= $46 {
            return 1
        }
    }
    return 0
}
sub hex_nibble(ubyte c) -> ubyte {
    if c >= $61 {
        return c - $57
    }
    if c >= $41 {
        return c - $37
    }
    return c - $30
}

; ---- decimal output ----
sub out_dec_place(uword p) {
    ubyte d
    d = 0
    repeat {
        if dec_v < p {
            break
        }
        dec_v = dec_v - p
        d = d + 1
    }
    if d != 0 {
        dec_started = 1
    }
    if dec_started != 0 {
        out_byte(d + $30)
    }
}
sub out_dec(uword v) {
    dec_v = v
    dec_started = 0
    out_dec_place(10000)
    out_dec_place(1000)
    out_dec_place(100)
    out_dec_place(10)
    out_byte(lsb(dec_v) + $30)
}

; ---- numeric scanners ----
sub read_hex() {
    int_val = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $5f {
            c = read_src()
        } else {
            if is_hexdig(c) != 0 {
                c = read_src()
                int_val = (int_val << 4) + hex_nibble(c)
            } else {
                return
            }
        }
    }
}
sub read_bin() {
    int_val = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $5f {
            c = read_src()
        } else {
            if c == $30 {
                c = read_src()
                int_val = int_val << 1
            } else {
                if c == $31 {
                    c = read_src()
                    int_val = (int_val << 1) + 1
                } else {
                    return
                }
            }
        }
    }
}
sub read_dec() {
    int_val = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $5f {
            c = read_src()
        } else {
            if is_digit(c) != 0 {
                c = read_src()
                int_val = (int_val << 3) + (int_val << 1) + (c - $30)
            } else {
                return
            }
        }
    }
}
sub decode_escape_val(ubyte e) -> ubyte {
    if e == $6e { return $0a }
    if e == $72 { return $0d }
    if e == $74 { return $09 }
    if e == $30 { return $00 }
    if e == $27 { return $27 }
    if e == $5c { return $5c }
    if e == $22 { return $22 }
    if e == $78 {
        ubyte h1
        ubyte h2
        h1 = read_src()
        h2 = read_src()
        return (hex_nibble(h1) << 4) + hex_nibble(h2)
    }
    return e
}

; ---- identifier + interning ----
sub read_ident() {
    name_len = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if is_alnum_us(c) != 0 {
            c = read_src()
            if name_len < 64 {
                name_buf[name_len] = c
                name_len = name_len + 1
            }
        } else {
            return
        }
    }
}
sub intern_name() -> uword {
    uword i
    i = 0
    repeat {
        if i >= ident_count {
            break
        }
        if ident_len[i] == name_len {
            uword off
            uword j
            ubyte match
            off = ident_off[i]
            match = 1
            j = 0
            repeat {
                if j >= name_len {
                    break
                }
                if ident_pool[off + j] != name_buf[j] {
                    match = 0
                    break
                }
                j = j + 1
            }
            if match != 0 {
                return i
            }
        }
        i = i + 1
    }
    ident_off[ident_count] = ident_pool_len
    ident_len[ident_count] = name_len
    uword k
    k = 0
    repeat {
        if k >= name_len {
            break
        }
        ident_pool[ident_pool_len] = name_buf[k]
        ident_pool_len = ident_pool_len + 1
        k = k + 1
    }
    uword id
    id = ident_count
    ident_count = ident_count + 1
    return id
}

; classify_name dispatches by length to a per-length helper. Splitting the
; keyword if-chains out of one big `when` keeps every sub's node count well
; under the per-unit node arena, so the self-host front-end (pass 1) can parse
; this file itself without overflowing. (Behaviour is identical; the helpers
; return TK_IDENT when no keyword matches, which classify_name passes through.)
sub cn_len2() -> ubyte {
    if name_buf[0]==$69 and name_buf[1]==$66 { return TK_KIF }   ; if
    if name_buf[0]==$69 and name_buf[1]==$6e { return TK_KIN }   ; in
    if name_buf[0]==$6f and name_buf[1]==$72 { return TK_KOR }   ; or
    if name_buf[0]==$74 and name_buf[1]==$6f { return TK_KTO }   ; to
    return TK_IDENT
}
sub cn_len3() -> ubyte {
    if name_buf[0]==$61 and name_buf[1]==$6e and name_buf[2]==$64 { return TK_KAND }   ; and
    if name_buf[0]==$66 and name_buf[1]==$6f and name_buf[2]==$72 { return TK_KFOR }   ; for
    if name_buf[0]==$6e and name_buf[1]==$6f and name_buf[2]==$74 { return TK_KNOT }   ; not
    if name_buf[0]==$73 and name_buf[1]==$74 and name_buf[2]==$72 { return TK_KSTR }   ; str
    if name_buf[0]==$73 and name_buf[1]==$75 and name_buf[2]==$62 { return TK_KSUB }   ; sub
    if name_buf[0]==$78 and name_buf[1]==$6f and name_buf[2]==$72 { return TK_KXOR }   ; xor
    return TK_IDENT
}
sub cn_len4() -> ubyte {
    if name_buf[0]==$62 and name_buf[1]==$6f and name_buf[2]==$6f and name_buf[3]==$6c { return TK_KBOOL }   ; bool
    if name_buf[0]==$62 and name_buf[1]==$79 and name_buf[2]==$74 and name_buf[3]==$65 { return TK_KBYTE }   ; byte
    if name_buf[0]==$65 and name_buf[1]==$6c and name_buf[2]==$73 and name_buf[3]==$65 { return TK_KELSE }   ; else
    if name_buf[0]==$65 and name_buf[1]==$6e and name_buf[2]==$75 and name_buf[3]==$6d { return TK_KENUM }   ; enum
    if name_buf[0]==$6d and name_buf[1]==$61 and name_buf[2]==$69 and name_buf[3]==$6e { return TK_KMAIN }   ; main
    if name_buf[0]==$74 and name_buf[1]==$72 and name_buf[2]==$75 and name_buf[3]==$65 { return TK_TRUE }   ; true
    if name_buf[0]==$76 and name_buf[1]==$6f and name_buf[2]==$69 and name_buf[3]==$64 { return TK_KVOID }   ; void
    if name_buf[0]==$77 and name_buf[1]==$68 and name_buf[2]==$65 and name_buf[3]==$6e { return TK_KWHEN }   ; when
    return TK_IDENT
}
sub cn_len5() -> ubyte {
    if name_buf[0]==$62 and name_buf[1]==$72 and name_buf[2]==$65 and name_buf[3]==$61 and name_buf[4]==$6b { return TK_KBREAK }   ; break
    if name_buf[0]==$63 and name_buf[1]==$6f and name_buf[2]==$6e and name_buf[3]==$73 and name_buf[4]==$74 { return TK_KCONST }   ; const
    if name_buf[0]==$64 and name_buf[1]==$65 and name_buf[2]==$66 and name_buf[3]==$65 and name_buf[4]==$72 { return TK_KDEFER }   ; defer
    if name_buf[0]==$66 and name_buf[1]==$61 and name_buf[2]==$6c and name_buf[3]==$73 and name_buf[4]==$65 { return TK_FALSE }   ; false
    if name_buf[0]==$75 and name_buf[1]==$62 and name_buf[2]==$79 and name_buf[3]==$74 and name_buf[4]==$65 { return TK_KUBYTE }   ; ubyte
    if name_buf[0]==$75 and name_buf[1]==$77 and name_buf[2]==$6f and name_buf[3]==$72 and name_buf[4]==$64 { return TK_KUWORD }   ; uword
    if name_buf[0]==$77 and name_buf[1]==$68 and name_buf[2]==$69 and name_buf[3]==$6c and name_buf[4]==$65 { return TK_KWHILE }   ; while
    return TK_IDENT
}
sub cn_len6() -> ubyte {
    if name_buf[0]==$61 and name_buf[1]==$73 and name_buf[2]==$6d and name_buf[3]==$73 and name_buf[4]==$75 and name_buf[5]==$62 { return TK_KASMSUB }   ; asmsub
    if name_buf[0]==$69 and name_buf[1]==$6e and name_buf[2]==$6c and name_buf[3]==$69 and name_buf[4]==$6e and name_buf[5]==$65 { return TK_KINLINE }   ; inline
    if name_buf[0]==$72 and name_buf[1]==$65 and name_buf[2]==$70 and name_buf[3]==$65 and name_buf[4]==$61 and name_buf[5]==$74 { return TK_KREPEAT }   ; repeat
    if name_buf[0]==$72 and name_buf[1]==$65 and name_buf[2]==$74 and name_buf[3]==$75 and name_buf[4]==$72 and name_buf[5]==$6e { return TK_KRETURN }   ; return
    if name_buf[0]==$73 and name_buf[1]==$74 and name_buf[2]==$72 and name_buf[3]==$75 and name_buf[4]==$63 and name_buf[5]==$74 { return TK_KSTRUCT }   ; struct
    return TK_IDENT
}
sub cn_len8() -> ubyte {
    if name_buf[0]==$63 and name_buf[1]==$6f and name_buf[2]==$6e and name_buf[3]==$74 and name_buf[4]==$69 and name_buf[5]==$6e and name_buf[6]==$75 and name_buf[7]==$65 { return TK_KCONTINUE }   ; continue
    return TK_IDENT
}
sub classify_name() -> ubyte {
    when name_len {
        2 -> { return cn_len2() }
        3 -> { return cn_len3() }
        4 -> { return cn_len4() }
        5 -> { return cn_len5() }
        6 -> { return cn_len6() }
        8 -> { return cn_len8() }
    }
    return TK_IDENT
}

; classify a directive name (already copied into name_buf):
; 0=address, 1=output, 2=import, 3=target, 4=other.
sub dir_classify() -> ubyte {
    when name_len {
        6 -> {
            if name_buf[0]==$69 and name_buf[1]==$6d and name_buf[2]==$70 and name_buf[3]==$6f and name_buf[4]==$72 and name_buf[5]==$74 { return 2 }   ; import
            if name_buf[0]==$6f and name_buf[1]==$75 and name_buf[2]==$74 and name_buf[3]==$70 and name_buf[4]==$75 and name_buf[5]==$74 { return 1 }   ; output
            if name_buf[0]==$74 and name_buf[1]==$61 and name_buf[2]==$72 and name_buf[3]==$67 and name_buf[4]==$65 and name_buf[5]==$74 { return 3 }   ; target
        }
        7 -> {
            if name_buf[0]==$61 and name_buf[1]==$64 and name_buf[2]==$64 and name_buf[3]==$72 and name_buf[4]==$65 and name_buf[5]==$73 and name_buf[6]==$73 { return 0 }   ; address
        }
    }
    return 4
}

; ---- token storage + lexer ----
sub push_token(ubyte kind, uword val) {
    ntok_kind = kind
    ntok_val = val
}

; produce one token into ntok_kind / ntok_val (TK_EOF at end of input).
sub next_raw_token() {
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            ntok_kind = TK_EOF
            ntok_val = 0
            return
        }
        if c == $20 { c = read_src()  continue }
        if c == $09 { c = read_src()  continue }
        if c == $0a { c = read_src()  continue }
        if c == $0d { c = read_src()  continue }
        if c == $3b {
            repeat {
                c = read_src()
                if src_eof != 0 { break }
                if c == $0a { break }
            }
            continue
        }
        if c == $25 {                              ; '%'
            c = read_src()
            ubyte c2
            c2 = peek_src()
            if src_eof == 0 {
                if c2 == $30 { read_bin()  push_token(TK_INT, int_val)  return }
                if c2 == $31 { read_bin()  push_token(TK_INT, int_val)  return }
                if is_alpha_us(c2) != 0 {
                    read_ident()
                    push_token(TK_DIRECTIVE, intern_name())
                    return
                }
            }
            push_token(TK_OTHER, 0)
            return
        }
        if c == $24 {
            c = read_src()
            read_hex()
            push_token(TK_INT, int_val)
            return
        }
        if is_digit(c) != 0 {
            read_dec()
            push_token(TK_INT, int_val)
            return
        }
        if c == $27 {
            c = read_src()
            c = read_src()
            if c == $5c {
                ubyte e
                e = read_src()
                int_val = decode_escape_val(e)
            } else {
                int_val = c
            }
            c = read_src()
            push_token(TK_INT, int_val)
            return
        }
        if c == $22 {
            c = read_src()
            str_off[str_count] = str_pool_len
            repeat {
                c = read_src()
                if src_eof != 0 { break }
                if c == $22 { break }
                ubyte rb
                if c == $5c {
                    ubyte se
                    se = read_src()
                    rb = decode_escape_val(se)
                } else {
                    rb = c
                }
                str_pool[str_pool_len] = rb
                str_pool_len = str_pool_len + 1
            }
            str_len[str_count] = str_pool_len - str_off[str_count]
            push_token(TK_STR, str_count)
            str_count = str_count + 1
            return
        }
        if is_alpha_us(c) != 0 {
            read_ident()
            ubyte k
            k = classify_name()
            if k == TK_IDENT {
                push_token(TK_IDENT, intern_name())
            } else {
                push_token(k, 0)
            }
            return
        }
        c = read_src()
        lex_operator(c)
        return
    }
}

sub lex_operator(ubyte c) {
    ubyte c2
    if c == $28 { push_token(TK_LPAREN, 0)  return }
    if c == $29 { push_token(TK_RPAREN, 0)  return }
    if c == $5b { push_token(TK_LBRACK, 0)  return }
    if c == $5d { push_token(TK_RBRACK, 0)  return }
    if c == $7b { push_token(TK_LBRACE, 0)  return }
    if c == $7d { push_token(TK_RBRACE, 0)  return }
    if c == $2c { push_token(TK_COMMA, 0)  return }
    if c == $40 { push_token(TK_AT, 0)  return }
    if c == $2e { push_token(TK_DOT, 0)  return }
    if c == $7e { push_token(TK_TILDE, 0)  return }
    if c == $2a {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_OTHER, 0)  return }   ; *=
        push_token(TK_STAR, 0)
        return
    }
    if c == $2b {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_PLUSEQ, 0)  return }
        if c2 == $2b { c2 = read_src()  push_token(TK_OTHER, 0)  return }
        push_token(TK_PLUS, 0)
        return
    }
    if c == $26 {
        c2 = peek_src()
        if c2 == $26 { c2 = read_src()  push_token(TK_OTHER, 0)  return }
        if c2 == $3d { c2 = read_src()  push_token(TK_ANDEQ, 0)  return }
        push_token(TK_AMP, 0)
        return
    }
    if c == $7c {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_OREQ, 0)  return }
        push_token(TK_PIPE, 0)
        return
    }
    if c == $5e {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_XOREQ, 0)  return }
        push_token(TK_CARET, 0)
        return
    }
    if c == $2d {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_MINUSEQ, 0)  return }
        if c2 == $3e { c2 = read_src()  push_token(TK_ARROW, 0)  return }
        if c2 == $2d { c2 = read_src()  push_token(TK_OTHER, 0)  return }
        push_token(TK_MINUS, 0)
        return
    }
    if c == $3c {
        c2 = peek_src()
        if c2 == $3c {
            c2 = read_src()
            c2 = peek_src()
            if c2 == $3d { c2 = read_src()  push_token(TK_SHLEQ, 0)  return }
            push_token(TK_SHL, 0)
            return
        }
        if c2 == $3d { c2 = read_src()  push_token(TK_LE, 0)  return }
        push_token(TK_LT, 0)
        return
    }
    if c == $3e {
        c2 = peek_src()
        if c2 == $3e {
            c2 = read_src()
            c2 = peek_src()
            if c2 == $3d { c2 = read_src()  push_token(TK_SHREQ, 0)  return }
            push_token(TK_SHR, 0)
            return
        }
        if c2 == $3d { c2 = read_src()  push_token(TK_GE, 0)  return }
        push_token(TK_GT, 0)
        return
    }
    if c == $3d {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_EQ, 0)  return }
        push_token(TK_ASSIGN, 0)
        return
    }
    if c == $21 {
        c2 = peek_src()
        if c2 == $3d { c2 = read_src()  push_token(TK_NE, 0)  return }
        push_token(TK_OTHER, 0)
        return
    }
    push_token(TK_OTHER, 0)
}

; ---- token cursor (over the streaming 2-token window) ----
sub cur_kind() -> ubyte {
    return tk0_kind
}
sub cur_val() -> uword {
    return tk0_val
}
sub peek1_kind() -> ubyte {
    return tk1_kind
}
sub advance() {
    tk0_kind = tk1_kind
    tk0_val = tk1_val
    next_raw_token()
    tk1_kind = ntok_kind
    tk1_val = ntok_val
}
sub lex_init() {
    next_raw_token()
    tk0_kind = ntok_kind
    tk0_val = ntok_val
    next_raw_token()
    tk1_kind = ntok_kind
    tk1_val = ntok_val
}

; ---- node arena ----
sub new_node(ubyte kind, ubyte op, uword a, uword b) -> uword {
    uword id
    id = node_count
    node_kind[id] = kind
    node_op[id] = op
    node_a[id] = a
    node_b[id] = b
    node_c[id] = 0
    node_d[id] = 0
    node_count = node_count + 1
    return id
}

; ---- cons cells ----
sub cons_prepend(uword head, uword val) -> uword {
    uword c
    c = cons_count
    cons_val[c] = val
    cons_next[c] = head
    cons_count = cons_count + 1
    return c
}

; ---- operator precedence ----
sub bin_prec(ubyte k) -> ubyte {
    if k == TK_KOR { return 0 }
    if k == TK_KXOR { return 0 }
    if k == TK_KAND { return 1 }
    if k == TK_EQ { return 2 }
    if k == TK_NE { return 2 }
    if k == TK_LT { return 3 }
    if k == TK_LE { return 3 }
    if k == TK_GT { return 3 }
    if k == TK_GE { return 3 }
    if k == TK_PIPE { return 4 }
    if k == TK_CARET { return 5 }
    if k == TK_AMP { return 6 }
    if k == TK_SHL { return 7 }
    if k == TK_SHR { return 7 }
    if k == TK_PLUS { return 8 }
    if k == TK_MINUS { return 8 }
    if k == TK_STAR { return 9 }
    return 255
}
sub is_binop(ubyte k) -> ubyte {
    if bin_prec(k) == 255 {
        return 0
    }
    return 1
}

; ---- shunting-yard ----
sub push_operand(uword node) {
    operand_stack[operand_sp] = node
    operand_sp = operand_sp + 1
}
sub push_op(ubyte k, ubyte op, ubyte prec) {
    op_kind[op_sp] = k
    op_op[op_sp] = op
    op_prec[op_sp] = prec
    op_sp = op_sp + 1
}
sub push_marker(ubyte k, uword floor) {
    op_kind[op_sp] = k
    op_floor[op_sp] = floor
    op_b[op_sp] = 0
    op_sp = op_sp + 1
}
sub apply_top() {
    op_sp = op_sp - 1
    ubyte k
    k = op_kind[op_sp]
    if k == OPK_BINOP {
        operand_sp = operand_sp - 1
        uword rhs
        rhs = operand_stack[operand_sp]
        operand_sp = operand_sp - 1
        uword lhs
        lhs = operand_stack[operand_sp]
        operand_stack[operand_sp] = new_node(ND_BINOP, op_op[op_sp], lhs, rhs)
        operand_sp = operand_sp + 1
    } else {
        operand_sp = operand_sp - 1
        uword operand
        operand = operand_stack[operand_sp]
        operand_stack[operand_sp] = new_node(ND_UNOP, op_op[op_sp], operand, 0)
        operand_sp = operand_sp + 1
    }
}
sub top_prec() -> ubyte {
    if op_kind[op_sp - 1] == OPK_UNOP {
        return UNARY_PREC
    }
    return op_prec[op_sp - 1]
}
sub reduce_to_marker() {
    repeat {
        if op_sp == 0 {
            return
        }
        if op_kind[op_sp - 1] >= OPK_LPAREN {
            return
        }
        apply_top()
    }
}

sub append_ident_to_namebuf(uword id) {
    uword off
    uword n
    uword j
    off = ident_off[id]
    n = ident_len[id]
    j = 0
    repeat {
        if j >= n {
            break
        }
        name_buf[name_len] = ident_pool[off + j]
        name_len = name_len + 1
        j = j + 1
    }
}
; append the (possibly dotted) ident currently at the cursor into path_buf.
sub append_ident_to_pathbuf(uword id) {
    uword off
    uword n
    uword j
    off = ident_off[id]
    n = ident_len[id]
    j = 0
    repeat {
        if j >= n {
            break
        }
        path_buf[path_len] = ident_pool[off + j]
        path_len = path_len + 1
        j = j + 1
    }
}
; Read IDENT (DOT IDENT)* at the cursor, returning the interned id of the
; full (possibly dotted) text. Builds into path_buf, NOT name_buf: each
; advance() lexes a token ahead, and the lexer reuses name_buf, so using
; name_buf across the advances would intern a clobbered (wrong) name.
sub read_dotted_path() -> uword {
    path_len = 0
    append_ident_to_pathbuf(cur_val())
    advance()
    repeat {
        if cur_kind() != TK_DOT {
            break
        }
        if peek1_kind() != TK_IDENT {
            break
        }
        advance()
        path_buf[path_len] = $2e
        path_len = path_len + 1
        append_ident_to_pathbuf(cur_val())
        advance()
    }
    ; copy into name_buf right before interning (now immune to lookahead)
    name_len = path_len
    uword i
    i = 0
    repeat {
        if i >= path_len {
            break
        }
        name_buf[i] = path_buf[i]
        i = i + 1
    }
    return intern_name()
}

sub close_index() {
    op_sp = op_sp - 1
    operand_sp = operand_sp - 1
    uword index
    index = operand_stack[operand_sp]
    operand_sp = operand_sp - 1
    uword array
    array = operand_stack[operand_sp]
    advance()
    uword node
    node = new_node(ND_INDEX, 0, array, index)
    if cur_kind() == TK_DOT {
        if peek1_kind() == TK_IDENT {
            advance()
            node_c[node] = cur_val()
            node_op[node] = 1
            advance()
        }
    }
    push_operand(node)
}
sub close_call() {
    uword head
    uword path
    uword floor
    head = op_b[op_sp - 1]
    path = op_a[op_sp - 1]
    floor = op_floor[op_sp - 1]
    if operand_sp > floor {
        operand_sp = operand_sp - 1
        head = cons_prepend(head, operand_stack[operand_sp])
    }
    op_sp = op_sp - 1
    uword node
    node = new_node(ND_CALL, 0, path, head)
    push_operand(node)
}

sub parse_expr() -> uword {
    operand_sp = 0
    op_sp = 0
    ubyte expect_operand
    ubyte index_ok
    expect_operand = 1
    index_ok = 0

    repeat {
        ubyte t
        t = cur_kind()

        if t == TK_RPAREN {
            reduce_to_marker()
            if op_sp == 0 {
                break
            }
            ubyte mk
            mk = op_kind[op_sp - 1]
            if mk == OPK_LPAREN {
                op_sp = op_sp - 1
                advance()
                expect_operand = 0
                index_ok = 0
                continue
            }
            if mk == OPK_MEMAT {
                op_sp = op_sp - 1
                operand_sp = operand_sp - 1
                push_operand(new_node(ND_MEMAT, 0, operand_stack[operand_sp], 0))
                advance()
                expect_operand = 0
                index_ok = 0
                continue
            }
            if mk == OPK_CALL {
                close_call()
                advance()
                expect_operand = 0
                index_ok = 0
                continue
            }
            break
        }
        if t == TK_RBRACK {
            reduce_to_marker()
            if op_sp == 0 {
                break
            }
            if op_kind[op_sp - 1] != OPK_LBRACK {
                break
            }
            close_index()
            expect_operand = 0
            index_ok = 0
            continue
        }
        if t == TK_COMMA {
            reduce_to_marker()
            if op_sp == 0 {
                break
            }
            if op_kind[op_sp - 1] != OPK_CALL {
                break
            }
            operand_sp = operand_sp - 1
            op_b[op_sp - 1] = cons_prepend(op_b[op_sp - 1], operand_stack[operand_sp])
            advance()
            expect_operand = 1
            index_ok = 0
            continue
        }

        if expect_operand != 0 {
            index_ok = 0
            if t == TK_INT {
                push_operand(new_node(ND_INT, 0, cur_val(), 0))
                advance()
                expect_operand = 0
                continue
            }
            if t == TK_STR {
                push_operand(new_node(ND_STR, 0, cur_val(), 0))
                advance()
                expect_operand = 0
                continue
            }
            if t == TK_TRUE {
                push_operand(new_node(ND_BOOL, 0, 1, 0))
                advance()
                expect_operand = 0
                continue
            }
            if t == TK_FALSE {
                push_operand(new_node(ND_BOOL, 0, 0, 0))
                advance()
                expect_operand = 0
                continue
            }
            if t == TK_KNOT {
                push_op(OPK_UNOP, UN_NOT, 0)
                advance()
                continue
            }
            if t == TK_TILDE {
                push_op(OPK_UNOP, UN_INV, 0)
                advance()
                continue
            }
            if t == TK_MINUS {
                push_op(OPK_UNOP, UN_NEG, 0)
                advance()
                continue
            }
            if t == TK_AMP {
                advance()
                if cur_kind() == TK_IDENT {
                    uword nid
                    nid = cur_val()
                    advance()
                    push_operand(new_node(ND_ADDROF, 0, nid, 0))
                    expect_operand = 0
                }
                continue
            }
            if t == TK_AT {
                advance()
                if cur_kind() == TK_LPAREN {
                    advance()
                }
                push_marker(OPK_MEMAT, operand_sp)
                continue
            }
            if t == TK_LPAREN {
                push_marker(OPK_LPAREN, operand_sp)
                advance()
                continue
            }
            if t == TK_IDENT {
                uword path
                path = read_dotted_path()
                if cur_kind() == TK_LPAREN {
                    advance()
                    push_marker(OPK_CALL, operand_sp)
                    op_a[op_sp - 1] = path
                } else {
                    push_operand(new_node(ND_IDENT, 0, path, 0))
                    expect_operand = 0
                    index_ok = 1
                }
                continue
            }
            break
        }

        if is_binop(t) != 0 {
            ubyte prec
            prec = bin_prec(t)
            repeat {
                if op_sp == 0 {
                    break
                }
                if op_kind[op_sp - 1] >= OPK_LPAREN {
                    break
                }
                if top_prec() < prec {
                    break
                }
                apply_top()
            }
            push_op(OPK_BINOP, t, prec)
            advance()
            expect_operand = 1
            index_ok = 0
            continue
        }
        if t == TK_LBRACK {
            if index_ok != 0 {
                push_marker(OPK_LBRACK, operand_sp)
                advance()
                expect_operand = 1
                index_ok = 0
                continue
            }
            break
        }
        break
    }

    repeat {
        if op_sp == 0 {
            break
        }
        apply_top()
    }
    operand_sp = operand_sp - 1
    return operand_stack[operand_sp]
}


; ---- type keyword -> type tag ----
sub type_tag(ubyte k) -> ubyte {
    if k == TK_KUBYTE { return TY_UBYTE }
    if k == TK_KBYTE { return TY_BYTE }
    if k == TK_KUWORD { return TY_UWORD }
    if k == TK_KBOOL { return TY_BOOL }
    if k == TK_KVOID { return TY_VOID }
    if k == TK_KSTR { return TY_STR }
    return TY_UBYTE
}
sub is_type_kw(ubyte k) -> ubyte {
    if k == TK_KUBYTE { return 1 }
    if k == TK_KBYTE { return 1 }
    if k == TK_KUWORD { return 1 }
    return 0
}
sub assign_code(ubyte k) -> ubyte {
    return k
}

; ---- leaf statements ----
uword last_simple

; parse a var decl (type kw already current). Returns vardecl node.
sub parse_var_decl() -> uword {
    ubyte tag
    tag = type_tag(cur_kind())
    advance()
    uword arrsize
    arrsize = 0
    if cur_kind() == TK_LBRACK {
        advance()
        arrsize = cur_val()                 ; INT
        advance()                           ; consume INT
        advance()                           ; consume ']'
    }
    uword nameid
    nameid = cur_val()
    advance()                               ; consume name IDENT
    uword init
    init = 0
    if cur_kind() == TK_ASSIGN {
        advance()
        init = parse_expr()
    }
    uword node
    node = new_node(ND_VARDECL, tag, nameid, init)
    node_c[node] = arrsize
    return node
}

; parse `%asm{{ "text" }}` -> inline asm node.
sub parse_inline_asm() -> uword {
    advance()                               ; consume DIRECTIVE asm
    advance()                               ; {
    advance()                               ; {
    uword sid
    sid = cur_val()                         ; STR
    advance()
    advance()                               ; }
    advance()                               ; }
    return new_node(ND_INLINEASM, 0, sid, 0)
}

; parse assignment-or-expression statement -> node (Assign or ExprStmt).
; Rewind-free: parse the whole LHS as an expression (which already yields
; an Ident / Index / MemAt target, or a Call etc.), then check whether an
; assignment operator follows. Assignment operators are not expression
; operators, so parse_expr stops right before them -- no backtracking
; needed (the streaming lexer has no rewind).
sub parse_assign_or_expr() -> uword {
    uword e
    e = parse_expr()
    ubyte k
    k = cur_kind()
    if k == TK_ASSIGN {
        advance()
        return new_node(ND_ASSIGN, TK_ASSIGN, e, parse_expr())
    }
    if k >= TK_PLUSEQ {
        if k <= TK_SHREQ {
            advance()
            return new_node(ND_ASSIGN, k, e, parse_expr())
        }
    }
    return new_node(ND_EXPRSTMT, 0, e, 0)
}

; ---- frame stack ----
sub fr_attach(uword node) {
    fr_stmts[fr_sp - 1] = cons_prepend(fr_stmts[fr_sp - 1], node)
}
sub fr_push_block(ubyte kind, ubyte deferflag) {
    fr_kind[fr_sp] = kind
    fr_mode[fr_sp] = 0
    fr_stmts[fr_sp] = 0
    fr_defer[fr_sp] = deferflag
    fr_sp = fr_sp + 1
}

; dispatch one statement; returns 1 if it opened a compound (pushed a
; frame), else parses a leaf into last_simple and returns 0.
sub stmt_dispatch(ubyte deferflag) -> ubyte {
    ubyte t
    t = cur_kind()
    if t == TK_DIRECTIVE {
        last_simple = parse_inline_asm()
        return 0
    }
    if is_type_kw(t) != 0 {
        last_simple = parse_var_decl()
        return 0
    }
    if t == TK_KIF {
        advance()
        uword cond
        cond = parse_expr()
        advance()                           ; '{'
        fr_push_block(FR_THEN, deferflag)
        fr_cond[fr_sp - 1] = cond
        return 1
    }
    if t == TK_KWHILE {
        advance()
        uword wcond
        wcond = parse_expr()
        advance()
        fr_push_block(FR_WHILE, deferflag)
        fr_cond[fr_sp - 1] = wcond
        return 1
    }
    if t == TK_KWHEN {
        advance()
        uword wexpr
        wexpr = parse_expr()
        advance()                           ; '{'
        fr_kind[fr_sp] = FR_WHEN
        fr_mode[fr_sp] = 1
        fr_defer[fr_sp] = deferflag
        fr_cond[fr_sp] = wexpr
        fr_choices[fr_sp] = 0
        fr_sp = fr_sp + 1
        return 1
    }
    if t == TK_KREPEAT {
        advance()
        uword count
        count = 0
        if cur_kind() != TK_LBRACE {
            count = parse_expr()
        }
        advance()                           ; '{'
        fr_push_block(FR_REPEAT, deferflag)
        fr_cond[fr_sp - 1] = count
        return 1
    }
    if t == TK_KFOR {
        advance()
        uword varid
        varid = cur_val()
        advance()                           ; IDENT
        advance()                           ; 'in'
        uword lo
        lo = parse_expr()
        advance()                           ; 'to'
        uword hi
        hi = parse_expr()
        advance()                           ; '{'
        fr_push_block(FR_FOR, deferflag)
        fr_var[fr_sp - 1] = varid
        fr_lo[fr_sp - 1] = lo
        fr_hi[fr_sp - 1] = hi
        return 1
    }
    if t == TK_KBREAK {
        advance()
        last_simple = new_node(ND_BREAK, 0, 0, 0)
        return 0
    }
    if t == TK_KCONTINUE {
        advance()
        last_simple = new_node(ND_CONTINUE, 0, 0, 0)
        return 0
    }
    if t == TK_KRETURN {
        advance()
        uword val
        val = 0
        ubyte nk
        nk = cur_kind()
        ; a value follows unless next is '}' or a keyword (except true/false)
        if nk == TK_RBRACE {
            last_simple = new_node(ND_RETURN, 0, 0, 0)
            return 0
        }
        if nk == TK_TRUE {
            val = parse_expr()
        } else {
            if nk == TK_FALSE {
                val = parse_expr()
            } else {
                if nk >= TK_KUBYTE {
                    ; a keyword that isn't true/false ends the return
                    last_simple = new_node(ND_RETURN, 0, 0, 0)
                    return 0
                }
                val = parse_expr()
            }
        }
        last_simple = new_node(ND_RETURN, 0, val, 0)
        return 0
    }
    last_simple = parse_assign_or_expr()
    return 0
}

; the frame-stack block driver: parse a `{ ... }` block (and everything
; nested) into a Block node; returns its node id.
sub parse_block() -> uword {
    advance()                               ; consume opening '{'
    fr_sp = 0
    pending_defer = 0
    fr_kind[fr_sp] = FR_ROOT
    fr_mode[fr_sp] = 0
    fr_stmts[fr_sp] = 0
    fr_defer[fr_sp] = 0
    fr_sp = fr_sp + 1
    uword result
    result = 0

    repeat {
        if fr_sp == 0 {
            break
        }
        ubyte fi
        fi = fr_sp - 1
        ubyte t
        uword node

        if fr_mode[fi] == 1 {               ; when body (choices)
            t = cur_kind()
            if t == TK_RBRACE {
                advance()
                node = new_node(ND_WHEN, 0, fr_cond[fi], fr_choices[fi])
                ubyte df
                df = fr_defer[fi]
                fr_sp = fr_sp - 1
                if df != 0 {
                    node = new_node(ND_DEFER, 0, node, 0)
                }
                fr_attach(node)
                continue
            }
            uword vals
            vals = 0
            if t == TK_KELSE {
                advance()
            } else {
                vals = cons_prepend(vals, parse_expr())
                repeat {
                    if cur_kind() != TK_COMMA {
                        break
                    }
                    advance()
                    vals = cons_prepend(vals, parse_expr())
                }
            }
            advance()                       ; '->'
            advance()                       ; '{'
            fr_kind[fr_sp] = FR_CHOICE
            fr_mode[fr_sp] = 0
            fr_stmts[fr_sp] = 0
            fr_defer[fr_sp] = 0
            fr_values[fr_sp] = vals
            fr_sp = fr_sp + 1
            continue
        }

        t = cur_kind()
        if t == TK_RBRACE {
            advance()
            uword block
            block = new_node(ND_BLOCK, 0, fr_stmts[fi], 0)
            ubyte kind
            kind = fr_kind[fi]
            fr_sp = fr_sp - 1
            if kind == FR_ROOT {
                result = block
                continue
            }
            if kind == FR_CHOICE {
                uword chvals
                chvals = fr_values[fi]
                uword ch
                ch = new_node(ND_WHENCHOICE, 0, chvals, block)
                uword pch
                pch = cons_prepend(fr_choices[fr_sp - 1], ch)
                fr_choices[fr_sp - 1] = pch
                continue
            }
            node = 0
            if kind == FR_THEN {
                if cur_kind() == TK_KELSE {
                    advance()
                    advance()               ; '{'
                    fr_kind[fr_sp] = FR_ELSE
                    fr_mode[fr_sp] = 0
                    fr_stmts[fr_sp] = 0
                    fr_defer[fr_sp] = fr_defer[fi]
                    fr_cond[fr_sp] = fr_cond[fi]
                    fr_then[fr_sp] = block
                    fr_sp = fr_sp + 1
                    continue
                }
                node = new_node(ND_IF, 0, fr_cond[fi], block)
            } else {
                if kind == FR_ELSE {
                    node = new_node(ND_IF, 0, fr_cond[fi], fr_then[fi])
                    node_c[node] = block
                } else {
                    if kind == FR_WHILE {
                        node = new_node(ND_WHILE, 0, fr_cond[fi], block)
                    } else {
                        if kind == FR_FOR {
                            node = new_node(ND_FOR, 0, fr_var[fi], fr_lo[fi])
                            node_c[node] = fr_hi[fi]
                            node_d[node] = block
                        } else {
                            ; FR_REPEAT
                            node = new_node(ND_REPEAT, 0, fr_cond[fi], block)
                        }
                    }
                }
            }
            if fr_defer[fi] != 0 {
                node = new_node(ND_DEFER, 0, node, 0)
            }
            fr_attach(node)
            continue
        }

        if t == TK_KDEFER {
            advance()
            pending_defer = 1
            continue
        }
        ubyte mod
        mod = pending_defer
        pending_defer = 0
        ubyte opened
        opened = stmt_dispatch(mod)
        if opened == 0 {
            node = last_simple
            if mod != 0 {
                node = new_node(ND_DEFER, 0, node, 0)
            }
            fr_attach(node)
        } else {
            ; the freshly pushed frame inherits the defer flag via
            ; fr_push_block(.., mod) already; nothing to do here.
        }
    }
    return result
}


; ---- top-level program parser ----
sub parse_sub(ubyte kind) -> uword {
    ; current token is the name (IDENT or main keyword handled by caller)
    uword nameid
    nameid = cur_val()
    advance()                               ; consume name
    advance()                               ; '('
    uword params
    params = 0
    repeat {
        if cur_kind() == TK_RPAREN {
            break
        }
        ubyte ptag
        ptag = type_tag(cur_kind())
        advance()                           ; type
        uword pname
        pname = cur_val()
        advance()                           ; name
        uword pnode
        pnode = new_node(ND_PARAM, ptag, pname, 0)
        params = cons_prepend(params, pnode)
        if cur_kind() != TK_COMMA {
            break
        }
        advance()
    }
    advance()                               ; ')'
    ubyte rettag
    rettag = TY_VOID
    if cur_kind() == TK_ARROW {
        advance()
        rettag = type_tag(cur_kind())
        advance()
    }
    uword body
    body = parse_block()
    uword node
    node = new_node(ND_SUB, kind, nameid, params)
    node_c[node] = body
    node_d[node] = rettag
    return node
}

sub const_type_tag(ubyte k) -> ubyte {
    if k == TK_KBYTE { return TY_CONST_BYTE }
    if k == TK_KUWORD { return TY_CONST_UWORD }
    return TY_CONST_UBYTE
}

sub parse_const_decl() -> uword {
    advance()                               ; 'const'
    ubyte ctag
    ctag = const_type_tag(cur_kind())
    advance()                               ; type
    uword nameid
    nameid = cur_val()
    advance()                               ; name
    advance()                               ; '='
    return new_node(ND_VARDECL, ctag, nameid, parse_expr())
}

sub parse_enum_decl() -> uword {
    advance()                               ; 'enum'
    uword ename
    ename = cur_val()
    advance()                               ; name
    advance()                               ; '{'
    uword members
    members = 0
    repeat {
        if cur_kind() == TK_RBRACE {
            break
        }
        uword mname
        mname = cur_val()
        advance()                           ; member name
        ubyte hasval
        uword mval
        hasval = 0
        mval = 0
        if cur_kind() == TK_ASSIGN {
            advance()
            mval = cur_val()
            advance()
            hasval = 1
        }
        members = cons_prepend(members, new_node(ND_ENUMMEMBER, hasval, mname, mval))
        if cur_kind() != TK_COMMA {
            break
        }
        advance()
    }
    advance()                               ; '}'
    return new_node(ND_ENUM, 0, ename, members)
}

sub parse_struct_decl() -> uword {
    advance()                               ; 'struct'
    uword sname
    sname = cur_val()
    advance()                               ; name
    advance()                               ; '{'
    uword fields
    fields = 0
    repeat {
        if cur_kind() == TK_RBRACE {
            break
        }
        ubyte ftag
        ftag = type_tag(cur_kind())
        advance()                           ; field type
        uword fname
        fname = cur_val()
        advance()                           ; field name
        fields = cons_prepend(fields, new_node(ND_FIELD, ftag, fname, 0))
        if cur_kind() == TK_COMMA {         ; ';' is a comment in the lexer
            advance()
        }
    }
    advance()                               ; '}'
    return new_node(ND_STRUCT, 0, sname, fields)
}

sub parse_asmsub() -> uword {
    advance()                               ; 'asmsub'
    uword nameid
    nameid = cur_val()
    advance()                               ; name
    advance()                               ; '('
    uword params
    params = 0
    repeat {
        if cur_kind() == TK_RPAREN {
            break
        }
        ubyte ptag
        ptag = type_tag(cur_kind())
        advance()
        uword pname
        pname = cur_val()
        advance()
        params = cons_prepend(params, new_node(ND_PARAM, ptag, pname, 0))
        if cur_kind() != TK_COMMA {
            break
        }
        advance()
    }
    advance()                               ; ')'
    ubyte rettag
    rettag = TY_VOID
    if cur_kind() == TK_ARROW {
        advance()
        rettag = type_tag(cur_kind())
        advance()
    }
    advance()                               ; '='
    uword addr
    addr = cur_val()                        ; $ADDR (INT)
    advance()
    uword node
    node = new_node(ND_SUB, SUBK_ASMSUB, nameid, params)
    node_c[node] = addr
    node_d[node] = rettag
    return node
}

sub is_struct_name(uword id) -> ubyte {
    uword cell
    cell = prog_structs
    repeat {
        if cell == 0 {
            return 0
        }
        if node_a[cons_val[cell]] == id {
            return 1
        }
        cell = cons_next[cell]
    }
}

sub parse_struct_var() -> uword {
    uword sname
    sname = cur_val()                       ; struct type name (IDENT)
    advance()
    uword arrsize
    arrsize = 0
    if cur_kind() == TK_LBRACK {
        advance()
        arrsize = cur_val()
        advance()                           ; INT
        advance()                           ; ']'
    }
    uword nameid
    nameid = cur_val()
    advance()                               ; instance name
    uword node
    node = new_node(ND_VARDECL, TY_STRUCT, nameid, 0)
    node_c[node] = arrsize
    node_d[node] = sname
    return node
}

; ---- streaming support ----
; Full reset (between passes): node arena + cons + text pools.
sub reset_arena() {
    reset_nodes()
    ident_count = 0
    ident_pool_len = 0
    str_count = 0
    str_pool_len = 0
}
; Per-unit reset (between subs in pass B): only the node arena + cons
; cells. The text pools are NOT reset -- the 2-token lookahead window
; holds tokens whose ident/str ids were interned during the previous
; unit, so resetting the pools would invalidate them. The pools persist
; across pass B (their total fits; idents dedupe).
sub reset_nodes() {
    node_count = 1
    cons_count = 1
}
sub reset_source() {
    ; the emulator rewinds the input to offset 0 on EOF, so clearing the
    ; sticky-EOF / peek flags makes the next read start over from the top.
    peek_ok = 0
    src_eof = 0
}

; process one directive (cursor on the DIRECTIVE token), updating program
; header state.
sub handle_directive() {
    name_len = 0
    append_ident_to_namebuf(cur_val())
    ubyte dk
    dk = dir_classify()
    advance()                               ; consume the directive
    if dk == 0 {                            ; %address
        prog_address = cur_val()
        advance()
        return
    }
    if dk == 2 {                            ; %import
        prog_imports = cons_prepend(prog_imports, cur_val())
        advance()
        return
    }
    if dk == 3 {                            ; %target
        name_len = 0
        append_ident_to_namebuf(cur_val())
        if name_len == 4 {                  ; "nmos"
            if name_buf[0]==$6e and name_buf[1]==$6d and name_buf[2]==$6f and name_buf[3]==$73 {
                prog_target = 1
                if prog_address == $4000 {
                    prog_address = $0200
                }
            }
        }
        advance()
        return
    }
    ; %output (or other): consume a single ident arg if present
    if cur_kind() == TK_IDENT {
        advance()
    }
}

; skip a `{ ... }` block (cursor on the opening '{'), brace-matched.
sub skip_braced_block() {
    advance()                               ; consume '{'
    uword depth
    depth = 1
    repeat {
        ubyte t
        t = cur_kind()
        if t == TK_EOF {
            return
        }
        if t == TK_LBRACE {
            depth = depth + 1
        }
        if t == TK_RBRACE {
            depth = depth - 1
            if depth == 0 {
                advance()                   ; consume the matching '}'
                return
            }
        }
        advance()
    }
}
; skip a sub: advance to its body '{', then skip the braced block.
sub skip_sub_body() {
    repeat {
        ubyte t
        t = cur_kind()
        if t == TK_EOF {
            return
        }
        if t == TK_LBRACE {
            break
        }
        advance()
    }
    skip_braced_block()
}
; skip an asmsub (no body): advance to '=', then past it and the $ADDR.
sub skip_asmsub() {
    advance()                               ; 'asmsub'
    repeat {
        ubyte t
        t = cur_kind()
        if t == TK_EOF {
            return
        }
        if t == TK_ASSIGN {
            break
        }
        if t == TK_LBRACE {
            return
        }
        advance()
    }
    advance()                               ; '='
    advance()                               ; $ADDR
}

; PASS A: collect directives + module decls into the program lists;
; skip sub / main / inline-sub / asmsub bodies.
sub parse_decls_pass() {
    repeat {
        ubyte t
        t = cur_kind()
        if t == TK_EOF {
            break
        }
        if t == TK_DIRECTIVE {
            handle_directive()
            continue
        }
        if is_type_kw(t) != 0 {
            prog_vars = cons_prepend(prog_vars, parse_var_decl())
            continue
        }
        if t == TK_KCONST {
            prog_vars = cons_prepend(prog_vars, parse_const_decl())
            continue
        }
        if t == TK_KENUM {
            prog_enums = cons_prepend(prog_enums, parse_enum_decl())
            continue
        }
        if t == TK_KSTRUCT {
            prog_structs = cons_prepend(prog_structs, parse_struct_decl())
            continue
        }
        if t == TK_KMAIN {
            skip_sub_body()
            continue
        }
        if t == TK_KSUB {
            skip_sub_body()
            continue
        }
        if t == TK_KINLINE {
            skip_sub_body()
            continue
        }
        if t == TK_KASMSUB {
            skip_asmsub()
            continue
        }
        if t == TK_IDENT {
            if is_struct_name(cur_val()) != 0 {
                prog_vars = cons_prepend(prog_vars, parse_struct_var())
                continue
            }
        }
        advance()                           ; skip an unknown token
    }
}

; main is `main { ... }` -- no params, void return, kind=main.
sub parse_main() -> uword {
    uword nameid
    name_len = 0
    name_buf[0] = $6d
    name_buf[1] = $61
    name_buf[2] = $69
    name_buf[3] = $6e
    name_len = 4
    nameid = intern_name()
    advance()                               ; consume 'main'
    uword body
    body = parse_block()
    uword node
    node = new_node(ND_SUB, SUBK_MAIN, nameid, 0)
    node_c[node] = body
    node_d[node] = TY_VOID
    return node
}


; ---- serialization ----
sub ws_push_node(uword node, ubyte depth) {
    ws_type[ws_sp] = 0
    ws_node[ws_sp] = node
    ws_depth[ws_sp] = depth
    ws_sp = ws_sp + 1
}
sub ws_push_simple(ubyte typ) {
    ws_type[ws_sp] = typ
    ws_sp = ws_sp + 1
}
sub ws_push_field(uword field_id, ubyte depth) {
    ws_type[ws_sp] = 3
    ws_node[ws_sp] = field_id
    ws_depth[ws_sp] = depth
    ws_sp = ws_sp + 1
}

sub out_indent(ubyte depth) {
    ubyte i
    i = 0
    repeat {
        if i >= depth {
            break
        }
        out_byte($20)
        out_byte($20)
        i = i + 1
    }
}
sub out_ident_text(uword id) {
    uword off
    uword n
    uword j
    off = ident_off[id]
    n = ident_len[id]
    j = 0
    repeat {
        if j >= n {
            break
        }
        out_byte(ident_pool[off + j])
        j = j + 1
    }
}
sub out_str_escaped(uword id) {
    uword off
    uword n
    uword j
    off = str_off[id]
    n = str_len[id]
    j = 0
    repeat {
        if j >= n {
            break
        }
        ubyte rb
        rb = str_pool[off + j]
        if rb == $5c { out_byte($5c)  out_byte($5c) }
        else {
            if rb == $22 { out_byte($5c)  out_byte($22) }
            else {
                if rb == $0a { out_byte($5c)  out_byte($6e) }
                else {
                    if rb == $0d { out_byte($5c)  out_byte($72) }
                    else {
                        if rb == $09 { out_byte($5c)  out_byte($74) }
                        else { out_byte(rb) }
                    }
                }
            }
        }
        j = j + 1
    }
}
sub out_binop_spelling(ubyte op) {
    if op == TK_PLUS  { out_byte($2b)  return }
    if op == TK_MINUS { out_byte($2d)  return }
    if op == TK_STAR  { out_byte($2a)  return }
    if op == TK_AMP   { out_byte($26)  return }
    if op == TK_PIPE  { out_byte($7c)  return }
    if op == TK_CARET { out_byte($5e)  return }
    if op == TK_SHL   { out_byte($3c)  out_byte($3c)  return }
    if op == TK_SHR   { out_byte($3e)  out_byte($3e)  return }
    if op == TK_EQ    { out_byte($3d)  out_byte($3d)  return }
    if op == TK_NE    { out_byte($21)  out_byte($3d)  return }
    if op == TK_LT    { out_byte($3c)  return }
    if op == TK_LE    { out_byte($3c)  out_byte($3d)  return }
    if op == TK_GT    { out_byte($3e)  return }
    if op == TK_GE    { out_byte($3e)  out_byte($3d)  return }
    if op == TK_KAND  { out_byte($61) out_byte($6e) out_byte($64)  return }
    if op == TK_KOR   { out_byte($6f) out_byte($72)  return }
    if op == TK_KXOR  { out_byte($78) out_byte($6f) out_byte($72)  return }
}
sub out_assign_spelling(ubyte op) {
    if op == TK_ASSIGN { out_byte($3d)  return }
    if op == TK_PLUSEQ { out_byte($2b) out_byte($3d)  return }
    if op == TK_MINUSEQ{ out_byte($2d) out_byte($3d)  return }
    if op == TK_ANDEQ  { out_byte($26) out_byte($3d)  return }
    if op == TK_OREQ   { out_byte($7c) out_byte($3d)  return }
    if op == TK_XOREQ  { out_byte($5e) out_byte($3d)  return }
    if op == TK_SHLEQ  { out_byte($3c) out_byte($3c) out_byte($3d)  return }
    if op == TK_SHREQ  { out_byte($3e) out_byte($3e) out_byte($3d)  return }
}
sub out_unop_spelling(ubyte op) {
    if op == UN_NEG { out_byte($75)  out_byte($2d)  return }
    if op == UN_INV { out_byte($7e)  return }
    if op == UN_NOT { out_byte($6e) out_byte($6f) out_byte($74)  return }
}
sub out_type_name(ubyte tag) {
    if tag == TY_UBYTE { out_byte($75) out_byte($62) out_byte($79) out_byte($74) out_byte($65)  return }   ; ubyte
    if tag == TY_BYTE  { out_byte($62) out_byte($79) out_byte($74) out_byte($65)  return }                 ; byte
    if tag == TY_UWORD { out_byte($75) out_byte($77) out_byte($6f) out_byte($72) out_byte($64)  return }   ; uword
    if tag == TY_BOOL  { out_byte($62) out_byte($6f) out_byte($6f) out_byte($6c)  return }                 ; bool
    if tag == TY_VOID  { out_byte($76) out_byte($6f) out_byte($69) out_byte($64)  return }                 ; void
    if tag == TY_STR   { out_byte($73) out_byte($74) out_byte($72)  return }                               ; str
    if tag == TY_CONST_UBYTE { out_str_lit_const() out_byte($75) out_byte($62) out_byte($79) out_byte($74) out_byte($65)  return }  ; const-ubyte
    if tag == TY_CONST_BYTE  { out_str_lit_const() out_byte($62) out_byte($79) out_byte($74) out_byte($65)  return }                ; const-byte
    if tag == TY_CONST_UWORD { out_str_lit_const() out_byte($75) out_byte($77) out_byte($6f) out_byte($72) out_byte($64)  return }  ; const-uword
}
; "const-" prefix
sub out_str_lit_const() {
    out_byte($63) out_byte($6f) out_byte($6e) out_byte($73) out_byte($74) out_byte($2d)
}

; emit one node's opening; push children/close onto the work stack.
sub emit_node(uword node, ubyte depth) {
    out_indent(depth)
    out_byte($28)
    ubyte k
    k = node_kind[node]
    if k == ND_INT {
        out_byte($69) out_byte($6e) out_byte($74) out_byte($20)
        out_dec(node_a[node])
        out_byte($29)
        return
    }
    if k == ND_BOOL {
        out_byte($62) out_byte($6f) out_byte($6f) out_byte($6c) out_byte($20)
        if node_a[node] != 0 {
            out_byte($74) out_byte($72) out_byte($75) out_byte($65)
        } else {
            out_byte($66) out_byte($61) out_byte($6c) out_byte($73) out_byte($65)
        }
        out_byte($29)
        return
    }
    if k == ND_IDENT {
        out_byte($69) out_byte($64) out_byte($20)
        out_ident_text(node_a[node])
        out_byte($29)
        return
    }
    if k == ND_STR {
        out_byte($73) out_byte($74) out_byte($72) out_byte($20) out_byte($22)
        out_str_escaped(node_a[node])
        out_byte($22)
        out_byte($29)
        return
    }
    if k == ND_ADDROF {
        out_byte($61) out_byte($64) out_byte($64) out_byte($72) out_byte($20)
        out_ident_text(node_a[node])
        out_byte($29)
        return
    }
    if k == ND_BINOP {
        out_binop_spelling(node_op[node])
        ws_push_simple(1)
        ws_push_node(node_b[node], depth + 1)
        ws_push_simple(2)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_UNOP {
        out_unop_spelling(node_op[node])
        ws_push_simple(1)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_MEMAT {
        out_byte($6d) out_byte($65) out_byte($6d)
        ws_push_simple(1)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_INDEX {
        out_byte($69) out_byte($64) out_byte($78)
        ws_push_simple(1)
        if node_op[node] != 0 {
            ws_push_field(node_c[node], depth + 1)
            ws_push_simple(2)
        }
        ws_push_node(node_b[node], depth + 1)
        ws_push_simple(2)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_CALL {
        out_byte($63) out_byte($61) out_byte($6c) out_byte($6c) out_byte($20)
        out_ident_text(node_a[node])
        ws_push_simple(1)
        uword cell
        cell = node_b[node]
        repeat {
            if cell == 0 {
                break
            }
            ws_push_node(cons_val[cell], depth + 1)
            ws_push_simple(2)
            cell = cons_next[cell]
        }
        return
    }
    if k == ND_BLOCK {
        out_byte($62) out_byte($6c) out_byte($6f) out_byte($63) out_byte($6b)  ; block
        ws_push_simple(1)
        emit_cons_children(node_a[node], depth)
        return
    }
    if k == ND_EXPRSTMT {
        out_byte($65) out_byte($78) out_byte($70) out_byte($72) out_byte($73) out_byte($74) out_byte($6d) out_byte($74)  ; exprstmt
        ws_push_simple(1)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_VARDECL {
        out_byte($76) out_byte($61) out_byte($72) out_byte($20)               ; "var "
        if node_op[node] == TY_STRUCT {
            out_ident_text(node_d[node])                                      ; struct type name
        } else {
            out_type_name(node_op[node])
        }
        if node_c[node] != 0 {
            out_byte($5b)                                                     ; '['
            out_dec(node_c[node])
            out_byte($5d)                                                     ; ']'
        }
        out_byte($20)
        out_ident_text(node_a[node])
        if node_b[node] != 0 {
            ws_push_simple(1)
            ws_push_node(node_b[node], depth + 1)
            ws_push_simple(2)
        } else {
            out_byte($29)
        }
        return
    }
    if k == ND_ASSIGN {
        out_byte($61) out_byte($73) out_byte($73) out_byte($69) out_byte($67) out_byte($6e) out_byte($20)  ; "assign "
        out_assign_spelling(node_op[node])
        ws_push_simple(1)
        ws_push_node(node_b[node], depth + 1)
        ws_push_simple(2)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_IF {
        out_byte($69) out_byte($66)                                          ; "if"
        ws_push_simple(1)
        if node_c[node] != 0 {
            ws_push_node(node_c[node], depth + 1)
            ws_push_simple(2)
        }
        ws_push_node(node_b[node], depth + 1)
        ws_push_simple(2)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_WHILE {
        out_byte($77) out_byte($68) out_byte($69) out_byte($6c) out_byte($65)  ; "while"
        ws_push_simple(1)
        ws_push_node(node_b[node], depth + 1)
        ws_push_simple(2)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_FOR {
        out_byte($66) out_byte($6f) out_byte($72) out_byte($20)              ; "for "
        out_ident_text(node_a[node])
        ws_push_simple(1)
        ws_push_node(node_d[node], depth + 1)                                ; body
        ws_push_simple(2)
        ws_push_node(node_c[node], depth + 1)                                ; hi
        ws_push_simple(2)
        ws_push_node(node_b[node], depth + 1)                                ; lo
        ws_push_simple(2)
        return
    }
    if k == ND_REPEAT {
        out_byte($72) out_byte($65) out_byte($70) out_byte($65) out_byte($61) out_byte($74)  ; "repeat"
        ws_push_simple(1)
        ws_push_node(node_b[node], depth + 1)                                ; body
        ws_push_simple(2)
        if node_a[node] != 0 {
            ws_push_node(node_a[node], depth + 1)                            ; count
            ws_push_simple(2)
        }
        return
    }
    if k == ND_WHEN {
        out_byte($77) out_byte($68) out_byte($65) out_byte($6e)              ; "when"
        ws_push_simple(1)
        emit_cons_children(node_b[node], depth)                              ; choices
        ws_push_node(node_a[node], depth + 1)                               ; expr
        ws_push_simple(2)
        return
    }
    if k == ND_WHENCHOICE {
        out_byte($63) out_byte($68) out_byte($6f) out_byte($69) out_byte($63) out_byte($65)  ; "choice"
        ws_push_simple(1)
        ws_push_node(node_b[node], depth + 1)                                ; body block
        ws_push_simple(2)
        ; (vals ...) group at depth+1
        ws_push_vals(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_BREAK {
        out_byte($62) out_byte($72) out_byte($65) out_byte($61) out_byte($6b) out_byte($29)  ; "break)"
        return
    }
    if k == ND_CONTINUE {
        out_byte($63) out_byte($6f) out_byte($6e) out_byte($74) out_byte($69) out_byte($6e) out_byte($75) out_byte($65) out_byte($29)
        return
    }
    if k == ND_RETURN {
        out_byte($72) out_byte($65) out_byte($74) out_byte($75) out_byte($72) out_byte($6e)  ; "return"
        if node_a[node] != 0 {
            ws_push_simple(1)
            ws_push_node(node_a[node], depth + 1)
            ws_push_simple(2)
        } else {
            out_byte($29)
        }
        return
    }
    if k == ND_DEFER {
        out_byte($64) out_byte($65) out_byte($66) out_byte($65) out_byte($72)  ; "defer"
        ws_push_simple(1)
        ws_push_node(node_a[node], depth + 1)
        ws_push_simple(2)
        return
    }
    if k == ND_INLINEASM {
        out_byte($61) out_byte($73) out_byte($6d) out_byte($20) out_byte($22)  ; asm "
        out_str_escaped(node_a[node])
        out_byte($22)
        out_byte($29)
        return
    }
}

; push a reversed cons list of child nodes so they pop in source order
; (each preceded by a newline), already inside an open form.
sub emit_cons_children(uword head, ubyte depth) {
    uword cell
    cell = head
    repeat {
        if cell == 0 {
            break
        }
        ws_push_node(cons_val[cell], depth + 1)
        ws_push_simple(2)
        cell = cons_next[cell]
    }
}

; push a `(vals E E ...)` group (work-stack literal form). We emit it as
; its own mini-walk: open line, children, close.
sub ws_push_vals(uword head, ubyte depth) {
    ws_type[ws_sp] = 5                       ; vals group
    ws_node[ws_sp] = head
    ws_depth[ws_sp] = depth
    ws_sp = ws_sp + 1
}

sub serialize_node_tree(uword root) {
    ws_sp = 0
    ws_push_node(root, 0)
    drain_ws()
}

sub drain_ws() {
    repeat {
        if ws_sp == 0 {
            break
        }
        ws_sp = ws_sp - 1
        ubyte typ
        typ = ws_type[ws_sp]
        if typ == 0 {
            emit_node(ws_node[ws_sp], ws_depth[ws_sp])
        } else {
            if typ == 1 {
                out_byte($29)
            } else {
                if typ == 2 {
                    out_byte($0a)
                } else {
                    if typ == 3 {
                        out_indent(ws_depth[ws_sp])
                        out_byte($2e)
                        out_ident_text(ws_node[ws_sp])
                    } else {
                        ; typ == 5: (vals E E ...) group. Capture head and
                        ; depth BEFORE ws_push_simple, which increments
                        ; ws_sp and would shift ws_node[ws_sp].
                        ubyte d
                        uword head
                        d = ws_depth[ws_sp]
                        head = ws_node[ws_sp]
                        out_indent(d)
                        out_byte($28) out_byte($76) out_byte($61) out_byte($6c) out_byte($73)  ; "(vals"
                        ws_push_simple(1)
                        emit_cons_children(head, d)
                    }
                }
            }
        }
    }
}

; ---- whole-program serialization (streaming) ----
; emit (program (address)(output)(target)(imports)(vars)(enums)(structs);
; the (subs ...) section and the closing ')' are emitted separately
; (pass B) so the big sub bodies never coexist in the arena.
sub serialize_head_and_decls() {
    ; (program
    out_byte($28) out_byte($70) out_byte($72) out_byte($6f) out_byte($67) out_byte($72) out_byte($61) out_byte($6d) out_byte($0a)
    ; (address $XXXX)
    out_byte($20) out_byte($20)
    out_byte($28) out_byte($61) out_byte($64) out_byte($64) out_byte($72) out_byte($65) out_byte($73) out_byte($73) out_byte($20) out_byte($24)
    out_hex4(prog_address)
    out_byte($29) out_byte($0a)
    ; (output raw)
    out_byte($20) out_byte($20)
    out_byte($28) out_byte($6f) out_byte($75) out_byte($74) out_byte($70) out_byte($75) out_byte($74) out_byte($20) out_byte($72) out_byte($61) out_byte($77) out_byte($29) out_byte($0a)
    ; (target X)
    out_byte($20) out_byte($20)
    out_byte($28) out_byte($74) out_byte($61) out_byte($72) out_byte($67) out_byte($65) out_byte($74) out_byte($20)
    if prog_target == 1 {
        out_byte($6e) out_byte($6d) out_byte($6f) out_byte($73)              ; nmos
    } else {
        out_byte($77) out_byte($65) out_byte($6e) out_byte($64) out_byte($79) out_byte($32) out_byte($63)  ; wendy2c
    }
    out_byte($29) out_byte($0a)
    ; (imports (import NAME) ...)
    serialize_imports()
    ; (vars VARDECL ...)
    serialize_list_section(prog_vars, 1)
    serialize_enums()
    serialize_structs()
}

; PASS B: emit `(subs SUBDEF ...)`, parsing + serializing each sub in
; turn and resetting the arena between, so only one sub's nodes (the
; biggest) ever live at once. Non-sub top-level units are re-parsed and
; discarded. The cursor starts at the top of the (rewound) source.
sub serialize_subs_streaming() {
    out_byte($20) out_byte($20)
    out_byte($28) out_byte($73) out_byte($75) out_byte($62) out_byte($73)    ; "(subs"
    repeat {
        ubyte t
        t = cur_kind()
        if t == TK_EOF {
            break
        }
        uword snode
        ubyte issub
        issub = 1
        if t == TK_KMAIN {
            snode = parse_main()
        } else {
            if t == TK_KSUB {
                advance()
                snode = parse_sub(SUBK_SUB)
            } else {
                if t == TK_KINLINE {
                    advance()
                    advance()
                    snode = parse_sub(SUBK_INLINE)
                } else {
                    if t == TK_KASMSUB {
                        snode = parse_asmsub()
                    } else {
                        issub = 0
                        skip_decl_pass_b()
                    }
                }
            }
        }
        if issub != 0 {
            out_byte($0a)
            serialize_sub(snode, 2)
            reset_nodes()
        }
    }
    out_byte($29)                           ; close (subs
}

; pass B: consume one non-sub top-level unit (directive / var / const /
; enum / struct / struct-var) without emitting it; reset the arena after
; any that allocated nodes.
sub skip_decl_pass_b() {
    ubyte t
    uword dummy
    t = cur_kind()
    if t == TK_DIRECTIVE {
        advance()                           ; directive
        ubyte a
        a = cur_kind()
        if a == TK_INT {
            advance()
        } else {
            if a == TK_IDENT {
                advance()
            }
        }
        return
    }
    if is_type_kw(t) != 0 {
        dummy = parse_var_decl()
        reset_nodes()
        return
    }
    if t == TK_KCONST {
        dummy = parse_const_decl()
        reset_nodes()
        return
    }
    if t == TK_KENUM {
        dummy = parse_enum_decl()
        reset_nodes()
        return
    }
    if t == TK_KSTRUCT {
        dummy = parse_struct_decl()
        reset_nodes()
        return
    }
    advance()                               ; struct-var idents / unknowns
}

; helper: emit a `(<kw>` section header whose children are a reversed
; cons list of nodes, then the nodes (each indented), then close.
; section_kw: 1 = "vars".
sub serialize_list_section(uword head, ubyte which) {
    out_byte($20) out_byte($20)
    if head == 0 {
        ; empty -> "(vars)\n"
        out_byte($28) out_byte($76) out_byte($61) out_byte($72) out_byte($73) out_byte($29) out_byte($0a)
        return
    }
    out_byte($28) out_byte($76) out_byte($61) out_byte($72) out_byte($73)    ; "(vars"
    ; reverse the cons list into source order, then serialize each at depth 2
    uword rev
    rev = reverse_cons(head)
    uword cell
    cell = rev
    repeat {
        if cell == 0 {
            break
        }
        out_byte($0a)
        ws_sp = 0
        ws_push_node(cons_val[cell], 2)
        drain_ws()
        cell = cons_next[cell]
    }
    out_byte($29) out_byte($0a)
}

sub serialize_imports() {
    out_byte($20) out_byte($20)
    if prog_imports == 0 {
        out_byte($28) out_byte($69) out_byte($6d) out_byte($70) out_byte($6f) out_byte($72) out_byte($74) out_byte($73) out_byte($29) out_byte($0a)  ; "(imports)\n"
        return
    }
    out_byte($28) out_byte($69) out_byte($6d) out_byte($70) out_byte($6f) out_byte($72) out_byte($74) out_byte($73)  ; "(imports"
    uword rev
    rev = reverse_cons(prog_imports)
    uword cell
    cell = rev
    repeat {
        if cell == 0 {
            break
        }
        out_byte($0a)
        out_indent(2)
        out_byte($28) out_byte($69) out_byte($6d) out_byte($70) out_byte($6f) out_byte($72) out_byte($74) out_byte($20)  ; "(import "
        out_ident_text(cons_val[cell])
        out_byte($29)
        cell = cons_next[cell]
    }
    out_byte($29) out_byte($0a)
}

sub serialize_enums() {
    out_byte($20) out_byte($20)
    if prog_enums == 0 {
        out_byte($28) out_byte($65) out_byte($6e) out_byte($75) out_byte($6d) out_byte($73) out_byte($29) out_byte($0a)  ; "(enums)\n"
        return
    }
    out_byte($28) out_byte($65) out_byte($6e) out_byte($75) out_byte($6d) out_byte($73)  ; "(enums"
    uword rev
    rev = reverse_cons(prog_enums)
    uword cell
    cell = rev
    repeat {
        if cell == 0 {
            break
        }
        out_byte($0a)
        serialize_enum(cons_val[cell], 2)
        cell = cons_next[cell]
    }
    out_byte($29) out_byte($0a)
}

sub serialize_enum(uword node, ubyte depth) {
    out_indent(depth)
    out_byte($28) out_byte($65) out_byte($6e) out_byte($75) out_byte($6d) out_byte($20)  ; "(enum "
    out_ident_text(node_a[node])
    out_byte($0a)
    out_indent(depth + 1)
    uword mhead
    mhead = node_b[node]
    if mhead == 0 {
        out_byte($28) out_byte($6d) out_byte($65) out_byte($6d) out_byte($62) out_byte($65) out_byte($72) out_byte($73) out_byte($29)  ; "(members)"
    } else {
        out_byte($28) out_byte($6d) out_byte($65) out_byte($6d) out_byte($62) out_byte($65) out_byte($72) out_byte($73)  ; "(members"
        uword rev
        rev = reverse_cons(mhead)
        uword cell
        cell = rev
        repeat {
            if cell == 0 {
                break
            }
            out_byte($0a)
            uword m
            m = cons_val[cell]
            out_indent(depth + 2)
            out_byte($28)
            out_ident_text(node_a[m])
            out_byte($20)
            if node_op[m] != 0 {
                out_dec(node_b[m])
            } else {
                out_byte($2d)               ; '-'
            }
            out_byte($29)
            cell = cons_next[cell]
        }
        out_byte($29)                       ; close (members
    }
    out_byte($29)                           ; close (enum
}

sub serialize_structs() {
    out_byte($20) out_byte($20)
    if prog_structs == 0 {
        out_byte($28) out_byte($73) out_byte($74) out_byte($72) out_byte($75) out_byte($63) out_byte($74) out_byte($73) out_byte($29) out_byte($0a)  ; "(structs)\n"
        return
    }
    out_byte($28) out_byte($73) out_byte($74) out_byte($72) out_byte($75) out_byte($63) out_byte($74) out_byte($73)  ; "(structs"
    uword rev
    rev = reverse_cons(prog_structs)
    uword cell
    cell = rev
    repeat {
        if cell == 0 {
            break
        }
        out_byte($0a)
        serialize_struct(cons_val[cell], 2)
        cell = cons_next[cell]
    }
    out_byte($29) out_byte($0a)
}

sub serialize_struct(uword node, ubyte depth) {
    out_indent(depth)
    out_byte($28) out_byte($73) out_byte($74) out_byte($72) out_byte($75) out_byte($63) out_byte($74) out_byte($20)  ; "(struct "
    out_ident_text(node_a[node])
    out_byte($0a)
    out_indent(depth + 1)
    uword fhead
    fhead = node_b[node]
    if fhead == 0 {
        out_byte($28) out_byte($66) out_byte($69) out_byte($65) out_byte($6c) out_byte($64) out_byte($73) out_byte($29)  ; "(fields)"
    } else {
        out_byte($28) out_byte($66) out_byte($69) out_byte($65) out_byte($6c) out_byte($64) out_byte($73)  ; "(fields"
        uword rev
        rev = reverse_cons(fhead)
        uword cell
        cell = rev
        repeat {
            if cell == 0 {
                break
            }
            out_byte($0a)
            uword fnode
            fnode = cons_val[cell]
            out_indent(depth + 2)
            out_byte($28)
            out_type_name(node_op[fnode])
            out_byte($20)
            out_ident_text(node_a[fnode])
            out_byte($29)
            cell = cons_next[cell]
        }
        out_byte($29)                       ; close (fields
    }
    out_byte($29)                           ; close (struct
}

; serialize one (subdef NAME KIND RET (params ...) BODY) at `depth`.
sub serialize_sub(uword node, ubyte depth) {
    out_indent(depth)
    out_byte($28) out_byte($73) out_byte($75) out_byte($62) out_byte($64) out_byte($65) out_byte($66) out_byte($20)  ; "(subdef "
    out_ident_text(node_a[node])
    out_byte($20)
    ubyte sk
    sk = node_op[node]
    if sk == SUBK_MAIN { out_byte($6d) out_byte($61) out_byte($69) out_byte($6e) }
    else {
        if sk == SUBK_INLINE { out_byte($69) out_byte($6e) out_byte($6c) out_byte($69) out_byte($6e) out_byte($65) }
        else {
            if sk == SUBK_ASMSUB { out_byte($61) out_byte($73) out_byte($6d) out_byte($73) out_byte($75) out_byte($62) }
            else { out_byte($73) out_byte($75) out_byte($62) }
        }
    }
    out_byte($20)
    out_type_name(lsb(node_d[node]))
    ; (params ...) at depth+1
    out_byte($0a)
    serialize_params(node_b[node], depth + 1)
    out_byte($0a)
    if sk == SUBK_ASMSUB {
        ; (asmtarget $XXXX) instead of a body
        out_indent(depth + 1)
        out_byte($28) out_byte($61) out_byte($73) out_byte($6d) out_byte($74) out_byte($61) out_byte($72) out_byte($67) out_byte($65) out_byte($74) out_byte($20) out_byte($24)  ; "(asmtarget $"
        out_hex4(node_c[node])
        out_byte($29)
    } else {
        ; body at depth+1
        ws_sp = 0
        ws_push_node(node_c[node], depth + 1)
        drain_ws()
    }
    out_byte($29)                            ; close (subdef
}

sub serialize_params(uword head, ubyte depth) {
    out_indent(depth)
    if head == 0 {
        out_byte($28) out_byte($70) out_byte($61) out_byte($72) out_byte($61) out_byte($6d) out_byte($73) out_byte($29)  ; "(params)"
        return
    }
    out_byte($28) out_byte($70) out_byte($61) out_byte($72) out_byte($61) out_byte($6d) out_byte($73)  ; "(params"
    uword rev
    rev = reverse_cons(head)
    uword cell
    cell = rev
    repeat {
        if cell == 0 {
            break
        }
        out_byte($0a)
        uword pn
        pn = cons_val[cell]
        out_indent(depth + 1)
        out_byte($28) out_byte($70) out_byte($61) out_byte($72) out_byte($61) out_byte($6d) out_byte($20)  ; "(param "
        out_type_name(node_op[pn])
        out_byte($20)
        out_ident_text(node_a[pn])
        out_byte($29)
        cell = cons_next[cell]
    }
    out_byte($29)
}

; reverse a cons list (returns new head; consumes fresh cells).
sub reverse_cons(uword head) -> uword {
    uword rev
    rev = 0
    uword cell
    cell = head
    repeat {
        if cell == 0 {
            break
        }
        rev = cons_prepend(rev, cons_val[cell])
        cell = cons_next[cell]
    }
    return rev
}

sub out_hex4(uword v) {
    out_hex_nib(lsb(v >> 12))
    out_hex_nib(lsb(v >> 8))
    out_hex_nib(lsb(v >> 4))
    out_hex_nib(lsb(v))
}
sub out_hex_nib(ubyte n) {
    n = n & $0f
    if n >= $0a {
        out_byte(n + $57)
    } else {
        out_byte(n + $30)
    }
}


; ---- main ----
main {
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
    serialize_head_and_decls()

    ; ---- pass B: stream the subs (the emulator rewound the file at EOF) ----
    reset_source()
    reset_arena()
    lex_init()
    serialize_subs_streaming()

    ; close (program
    out_byte($29) out_byte($0a)

    _close(src_hand)
    _close(dst_hand)
}

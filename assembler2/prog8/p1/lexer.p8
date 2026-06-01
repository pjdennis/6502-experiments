; lexer.p8 -- the Prog8 lexer port (Phase 6, M1, on-target).
;
; Reads a .p8 source file (argv[0]) and writes the canonical token-stream
; dump (argv[1]) -- the exact format frozen by p8c/serialize.py's
; serialize_tokens() and `p8c --dump-tokens`. One token per line:
;
;     INT <decimal>            ; value normalized ($ff/%1010/'A' -> decimal)
;     STR "<escaped>"          ; same escape set as the AST string contract
;     IDENT <text>   KW <text>   DIRECTIVE <text>
;     PUNCT <spelling>         ; punctuation / operator (kind == value)
;     EOF
;
; This is the M1 on-target milestone: it must byte-match the Python
; token-dump for the same input. It runs on the emulator's nmos-default
; machine and uses the same file-I/O shim as tinyp8 (syscalls at
; $F006..$F03C). Source line/col are not emitted -- positions are not
; part of the structural contract (see PARSER_PORT_DESIGN.md section 4).
;
; Integer values are accumulated into a uword, so literals must fit in
; 16 bits (the realistic corpus does); decimal output uses power-of-ten
; subtraction because host p8c has no '/' or '%'. The decimal accumulator
; `(int_val << 3) + (int_val << 1) + (c - $30)` doubles as a regression
; test for the host-p8c codegen fix that lets both operands of a binary
; op each use scratch without clobbering each other.

%target nmos
%address $0200

; ---- module-level state ----
ubyte src_hand
ubyte dst_hand
ubyte peek_buf
ubyte peek_ok
ubyte src_eof

ubyte[40] name_buf      ; current identifier / directive name
ubyte name_len

uword int_val           ; accumulated value of the current numeric literal

uword dec_v             ; out_dec scratch
ubyte dec_started


; ---- syscall asmsubs (nmos-default file I/O stubs) ----
asmsub _exit(ubyte code) = $F00F
asmsub _close(ubyte handle) = $F015

; argv(i) -> uword: emulator returns A=low, X=high; Prog8 wants A:Y.
sub _argv(ubyte i) -> uword {
    %asm{{ "lda p8v__argv_arg_i\njsr $f01e\npha\ntxa\ntay\npla\nrts" }}
}

sub _open(uword filename) -> ubyte {
    %asm{{ "lda p8v__open_arg_filename\nldx p8v__open_arg_filename+1\njsr $f012\nrts" }}
}

sub _openout(uword filename) -> ubyte {
    %asm{{ "lda p8v__openout_arg_filename\nldx p8v__openout_arg_filename+1\njsr $f021\nrts" }}
}

; read(handle) -> byte. EOF via carry -> stash in src_eof (0=ok, 1=eof).
sub _read(ubyte handle) -> ubyte {
    %asm{{ "lda p8v__read_arg_handle\njsr $f018\nbcc .ok\nlda #1\nsta p8v_src_eof\nlda #0\nrts\n.ok:\nsta __p8c_tmp0\nlda #0\nsta p8v_src_eof\nlda __p8c_tmp0\nrts" }}
}

; write(byte, handle). Emulator: A=byte, X=handle.
sub _write(ubyte b, ubyte handle) {
    %asm{{ "ldx p8v__write_arg_handle\nlda p8v__write_arg_b\njsr $f024\nrts" }}
}


; ---- source / destination I/O ----

sub read_src() -> ubyte {
    if peek_ok != 0 {
        peek_ok = 0
        return peek_buf
    }
    return _read(src_hand)
}

sub peek_src() -> ubyte {
    if peek_ok == 0 {
        ubyte b
        b = _read(src_hand)
        if src_eof != 0 {
            return 0
        }
        peek_buf = b
        peek_ok = 1
    }
    return peek_buf
}

sub out_byte(ubyte b) {
    _write(b, dst_hand)
}

sub out_nl() {
    out_byte($0a)
}


; ---- character-class helpers (return 1/0) ----

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
        return c - $57                                   ; 'a'-10
    }
    if c >= $41 {
        return c - $37                                   ; 'A'-10
    }
    return c - $30
}


; ---- decimal output (power-of-ten subtraction; no '/' in host p8c) ----

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
    out_byte(lsb(dec_v) + $30)                           ; ones place (dec_v < 10)
}


; ---- numeric literal scanners (accumulate into int_val) ----

sub read_hex() {                                         ; '$' already consumed
    int_val = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $5f {                                    ; '_' separator
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

sub read_bin() {                                         ; '%' already consumed
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

sub read_dec() {                                         ; first digit still peeked
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


; ---- escape decoding (shared by char + string literals) ----
;
; Decodes the char AFTER a backslash to its byte value, mirroring the
; host lexer. For '\xHH' it consumes the two hex digits from the source.

sub decode_escape_val(ubyte e) -> ubyte {
    if e == $6e { return $0a }                           ; \n
    if e == $72 { return $0d }                           ; \r
    if e == $74 { return $09 }                           ; \t
    if e == $30 { return $00 }                           ; \0
    if e == $27 { return $27 }                           ; \'
    if e == $5c { return $5c }                           ; backslash
    if e == $22 { return $22 }                           ; \"
    if e == $78 {                                        ; \xHH
        ubyte h1
        ubyte h2
        h1 = read_src()
        h2 = read_src()
        return (hex_nibble(h1) << 4) + hex_nibble(h2)
    }
    return e                                             ; fallback: literal
}


; ---- identifier reading ----

sub read_ident() {                                       ; next peeked char starts an ident
    name_len = 0
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if is_alnum_us(c) != 0 {
            c = read_src()
            if name_len < 40 {
                name_buf[name_len] = c
                name_len = name_len + 1
            }
        } else {
            return
        }
    }
}

; kw_match: returns 1 if name_buf[0..name_len-1] is a Prog8
; keyword, else 0. Generated from p8c.lex.KEYWORDS, grouped by
; length; each arm is a flat list of full char-by-char compares.
sub kw_match() -> ubyte {
    when name_len {
        2 -> {
            if name_buf[0]==$61 and name_buf[1]==$73 { return 1 }   ; as
            if name_buf[0]==$64 and name_buf[1]==$6f { return 1 }   ; do
            if name_buf[0]==$69 and name_buf[1]==$66 { return 1 }   ; if
            if name_buf[0]==$69 and name_buf[1]==$6e { return 1 }   ; in
            if name_buf[0]==$6f and name_buf[1]==$72 { return 1 }   ; or
            if name_buf[0]==$74 and name_buf[1]==$6f { return 1 }   ; to
        }
        3 -> {
            if name_buf[0]==$61 and name_buf[1]==$6e and name_buf[2]==$64 { return 1 }   ; and
            if name_buf[0]==$66 and name_buf[1]==$6f and name_buf[2]==$72 { return 1 }   ; for
            if name_buf[0]==$6e and name_buf[1]==$6f and name_buf[2]==$74 { return 1 }   ; not
            if name_buf[0]==$73 and name_buf[1]==$74 and name_buf[2]==$72 { return 1 }   ; str
            if name_buf[0]==$73 and name_buf[1]==$75 and name_buf[2]==$62 { return 1 }   ; sub
            if name_buf[0]==$78 and name_buf[1]==$6f and name_buf[2]==$72 { return 1 }   ; xor
        }
        4 -> {
            if name_buf[0]==$62 and name_buf[1]==$6f and name_buf[2]==$6f and name_buf[3]==$6c { return 1 }   ; bool
            if name_buf[0]==$62 and name_buf[1]==$79 and name_buf[2]==$74 and name_buf[3]==$65 { return 1 }   ; byte
            if name_buf[0]==$65 and name_buf[1]==$6c and name_buf[2]==$73 and name_buf[3]==$65 { return 1 }   ; else
            if name_buf[0]==$65 and name_buf[1]==$6e and name_buf[2]==$75 and name_buf[3]==$6d { return 1 }   ; enum
            if name_buf[0]==$67 and name_buf[1]==$6f and name_buf[2]==$74 and name_buf[3]==$6f { return 1 }   ; goto
            if name_buf[0]==$6d and name_buf[1]==$61 and name_buf[2]==$69 and name_buf[3]==$6e { return 1 }   ; main
            if name_buf[0]==$73 and name_buf[1]==$74 and name_buf[2]==$65 and name_buf[3]==$70 { return 1 }   ; step
            if name_buf[0]==$74 and name_buf[1]==$72 and name_buf[2]==$75 and name_buf[3]==$65 { return 1 }   ; true
            if name_buf[0]==$76 and name_buf[1]==$6f and name_buf[2]==$69 and name_buf[3]==$64 { return 1 }   ; void
            if name_buf[0]==$77 and name_buf[1]==$68 and name_buf[2]==$65 and name_buf[3]==$6e { return 1 }   ; when
            if name_buf[0]==$77 and name_buf[1]==$6f and name_buf[2]==$72 and name_buf[3]==$64 { return 1 }   ; word
        }
        5 -> {
            if name_buf[0]==$62 and name_buf[1]==$72 and name_buf[2]==$65 and name_buf[3]==$61 and name_buf[4]==$6b { return 1 }   ; break
            if name_buf[0]==$63 and name_buf[1]==$6f and name_buf[2]==$6e and name_buf[3]==$73 and name_buf[4]==$74 { return 1 }   ; const
            if name_buf[0]==$64 and name_buf[1]==$65 and name_buf[2]==$66 and name_buf[3]==$65 and name_buf[4]==$72 { return 1 }   ; defer
            if name_buf[0]==$66 and name_buf[1]==$61 and name_buf[2]==$6c and name_buf[3]==$73 and name_buf[4]==$65 { return 1 }   ; false
            if name_buf[0]==$75 and name_buf[1]==$62 and name_buf[2]==$79 and name_buf[3]==$74 and name_buf[4]==$65 { return 1 }   ; ubyte
            if name_buf[0]==$75 and name_buf[1]==$6e and name_buf[2]==$74 and name_buf[3]==$69 and name_buf[4]==$6c { return 1 }   ; until
            if name_buf[0]==$75 and name_buf[1]==$77 and name_buf[2]==$6f and name_buf[3]==$72 and name_buf[4]==$64 { return 1 }   ; uword
            if name_buf[0]==$77 and name_buf[1]==$68 and name_buf[2]==$69 and name_buf[3]==$6c and name_buf[4]==$65 { return 1 }   ; while
        }
        6 -> {
            if name_buf[0]==$61 and name_buf[1]==$73 and name_buf[2]==$6d and name_buf[3]==$73 and name_buf[4]==$75 and name_buf[5]==$62 { return 1 }   ; asmsub
            if name_buf[0]==$64 and name_buf[1]==$6f and name_buf[2]==$77 and name_buf[3]==$6e and name_buf[4]==$74 and name_buf[5]==$6f { return 1 }   ; downto
            if name_buf[0]==$65 and name_buf[1]==$78 and name_buf[2]==$74 and name_buf[3]==$73 and name_buf[4]==$75 and name_buf[5]==$62 { return 1 }   ; extsub
            if name_buf[0]==$69 and name_buf[1]==$6e and name_buf[2]==$6c and name_buf[3]==$69 and name_buf[4]==$6e and name_buf[5]==$65 { return 1 }   ; inline
            if name_buf[0]==$72 and name_buf[1]==$65 and name_buf[2]==$70 and name_buf[3]==$65 and name_buf[4]==$61 and name_buf[5]==$74 { return 1 }   ; repeat
            if name_buf[0]==$72 and name_buf[1]==$65 and name_buf[2]==$74 and name_buf[3]==$75 and name_buf[4]==$72 and name_buf[5]==$6e { return 1 }   ; return
            if name_buf[0]==$73 and name_buf[1]==$74 and name_buf[2]==$72 and name_buf[3]==$75 and name_buf[4]==$63 and name_buf[5]==$74 { return 1 }   ; struct
        }
        7 -> {
            if name_buf[0]==$70 and name_buf[1]==$72 and name_buf[2]==$69 and name_buf[3]==$76 and name_buf[4]==$61 and name_buf[5]==$74 and name_buf[6]==$65 { return 1 }   ; private
        }
        8 -> {
            if name_buf[0]==$63 and name_buf[1]==$6f and name_buf[2]==$6e and name_buf[3]==$74 and name_buf[4]==$69 and name_buf[5]==$6e and name_buf[6]==$75 and name_buf[7]==$65 { return 1 }   ; continue
        }
    }
    return 0
}


; ---- tag emitters ----

sub emit_int_head() {                                    ; "INT "
    out_byte($49) out_byte($4e) out_byte($54) out_byte($20)
}

sub emit_str_head() {                                    ; "STR \""
    out_byte($53) out_byte($54) out_byte($52) out_byte($20) out_byte($22)
}

sub emit_ident_head() {                                  ; "IDENT "
    out_byte($49) out_byte($44) out_byte($45) out_byte($4e) out_byte($54) out_byte($20)
}

sub emit_kw_head() {                                     ; "KW "
    out_byte($4b) out_byte($57) out_byte($20)
}

sub emit_dir_head() {                                    ; "DIRECTIVE "
    out_byte($44) out_byte($49) out_byte($52) out_byte($45) out_byte($43)
    out_byte($54) out_byte($49) out_byte($56) out_byte($45) out_byte($20)
}

sub emit_punct_head() {                                  ; "PUNCT "
    out_byte($50) out_byte($55) out_byte($4e) out_byte($43) out_byte($54) out_byte($20)
}

sub emit_punct1(ubyte a) {
    emit_punct_head()
    out_byte(a)
    out_nl()
}

sub emit_punct2(ubyte a, ubyte b) {
    emit_punct_head()
    out_byte(a)
    out_byte(b)
    out_nl()
}

sub emit_punct3(ubyte a, ubyte b, ubyte c) {
    emit_punct_head()
    out_byte(a)
    out_byte(b)
    out_byte(c)
    out_nl()
}

sub emit_eof() {                                         ; "EOF\n"
    out_byte($45) out_byte($4f) out_byte($46) out_nl()
}

sub out_ident() {
    ubyte i
    i = 0
    repeat {
        if i >= name_len {
            break
        }
        out_byte(name_buf[i])
        i = i + 1
    }
}

; out_escaped: write one real byte using the canonical output escape set.
sub out_escaped(ubyte rb) {
    if rb == $5c {
        out_byte($5c) out_byte($5c)                      ; backslash -> \\
        return
    }
    if rb == $22 {
        out_byte($5c) out_byte($22)                      ; " -> \"
        return
    }
    if rb == $0a {
        out_byte($5c) out_byte($6e)                      ; nl -> \n
        return
    }
    if rb == $0d {
        out_byte($5c) out_byte($72)                      ; cr -> \r
        return
    }
    if rb == $09 {
        out_byte($5c) out_byte($74)                      ; tab -> \t
        return
    }
    out_byte(rb)
}


; ---- composite literal lexers ----

sub lex_char() {                                         ; opening ' already consumed
    ubyte c
    c = read_src()
    if src_eof != 0 {
        return
    }
    if c == $5c {                                        ; escape
        ubyte e
        e = read_src()
        int_val = decode_escape_val(e)
    } else {
        int_val = c
    }
    c = read_src()                                       ; consume closing '
    emit_int_head()
    out_dec(int_val)
    out_nl()
}

sub lex_string() {                                       ; opening " already consumed
    emit_str_head()
    repeat {
        ubyte c
        c = read_src()
        if src_eof != 0 {
            break
        }
        if c == $22 {                                    ; closing "
            break
        }
        ubyte rb
        if c == $5c {
            ubyte e
            e = read_src()
            rb = decode_escape_val(e)
        } else {
            rb = c
        }
        out_escaped(rb)
    }
    out_byte($22)
    out_nl()
}

sub skip_to_nl() {
    repeat {
        ubyte c
        c = read_src()
        if src_eof != 0 {
            break
        }
        if c == $0a {
            break
        }
    }
}

; lex_operator: emit the longest punctuation/operator token whose first
; char is `c` (already consumed). At EOF the peeked char reads back as 0,
; so every multi-char test fails and we fall through to the single form.
sub lex_operator(ubyte c) {
    ubyte c2
    if c == $3c {                                        ; <  <=  <<  <<=
        c2 = peek_src()
        if c2 == $3c {
            c2 = read_src()
            c2 = peek_src()
            if c2 == $3d {
                c2 = read_src()
                emit_punct3($3c, $3c, $3d)
            } else {
                emit_punct2($3c, $3c)
            }
        } else {
            if c2 == $3d {
                c2 = read_src()
                emit_punct2($3c, $3d)
            } else {
                emit_punct1($3c)
            }
        }
        return
    }
    if c == $3e {                                        ; >  >=  >>  >>=
        c2 = peek_src()
        if c2 == $3e {
            c2 = read_src()
            c2 = peek_src()
            if c2 == $3d {
                c2 = read_src()
                emit_punct3($3e, $3e, $3d)
            } else {
                emit_punct2($3e, $3e)
            }
        } else {
            if c2 == $3d {
                c2 = read_src()
                emit_punct2($3e, $3d)
            } else {
                emit_punct1($3e)
            }
        }
        return
    }
    if c == $3d {                                        ; =  ==
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($3d, $3d)
        } else {
            emit_punct1($3d)
        }
        return
    }
    if c == $21 {                                        ; !  !=
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($21, $3d)
        } else {
            emit_punct1($21)
        }
        return
    }
    if c == $2b {                                        ; +  ++  +=
        c2 = peek_src()
        if c2 == $2b {
            c2 = read_src()
            emit_punct2($2b, $2b)
        } else {
            if c2 == $3d {
                c2 = read_src()
                emit_punct2($2b, $3d)
            } else {
                emit_punct1($2b)
            }
        }
        return
    }
    if c == $2d {                                        ; -  --  -=  ->
        c2 = peek_src()
        if c2 == $2d {
            c2 = read_src()
            emit_punct2($2d, $2d)
        } else {
            if c2 == $3d {
                c2 = read_src()
                emit_punct2($2d, $3d)
            } else {
                if c2 == $3e {
                    c2 = read_src()
                    emit_punct2($2d, $3e)
                } else {
                    emit_punct1($2d)
                }
            }
        }
        return
    }
    if c == $2a {                                        ; *  *=
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($2a, $3d)
        } else {
            emit_punct1($2a)
        }
        return
    }
    if c == $2f {                                        ; /  /=
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($2f, $3d)
        } else {
            emit_punct1($2f)
        }
        return
    }
    if c == $26 {                                        ; &  &&  &=
        c2 = peek_src()
        if c2 == $26 {
            c2 = read_src()
            emit_punct2($26, $26)
        } else {
            if c2 == $3d {
                c2 = read_src()
                emit_punct2($26, $3d)
            } else {
                emit_punct1($26)
            }
        }
        return
    }
    if c == $7c {                                        ; |  |=
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($7c, $3d)
        } else {
            emit_punct1($7c)
        }
        return
    }
    if c == $5e {                                        ; ^  ^=
        c2 = peek_src()
        if c2 == $3d {
            c2 = read_src()
            emit_punct2($5e, $3d)
        } else {
            emit_punct1($5e)
        }
        return
    }
    ; pure single-char punctuation: ( ) [ ] { } , . : ~ @ ?
    emit_punct1(c)
}


; ---- main lex loop ----

main {
    uword fn
    fn = _argv(0)
    src_hand = _open(fn)
    fn = _argv(1)
    dst_hand = _openout(fn)

    peek_ok = 0
    src_eof = 0

    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            break
        }

        ; whitespace
        if c == $20 {
            c = read_src()
            continue
        }
        if c == $09 {
            c = read_src()
            continue
        }
        if c == $0a {
            c = read_src()
            continue
        }
        if c == $0d {
            c = read_src()
            continue
        }
        ; ';' line comment
        if c == $3b {
            skip_to_nl()
            continue
        }

        ; '%' -- directive, binary literal, or bare '%'
        if c == $25 {
            c = read_src()                               ; consume '%'
            ubyte c2
            c2 = peek_src()
            if src_eof != 0 {
                emit_punct1($25)
                continue
            }
            if is_alpha_us(c2) != 0 {
                read_ident()
                emit_dir_head()
                out_ident()
                out_nl()
                continue
            }
            if c2 == $30 {
                read_bin()
                emit_int_head()
                out_dec(int_val)
                out_nl()
                continue
            }
            if c2 == $31 {
                read_bin()
                emit_int_head()
                out_dec(int_val)
                out_nl()
                continue
            }
            emit_punct1($25)
            continue
        }

        ; '$' hex literal
        if c == $24 {
            c = read_src()                               ; consume '$'
            read_hex()
            emit_int_head()
            out_dec(int_val)
            out_nl()
            continue
        }

        ; decimal literal
        if is_digit(c) != 0 {
            read_dec()
            emit_int_head()
            out_dec(int_val)
            out_nl()
            continue
        }

        ; char literal
        if c == $27 {
            c = read_src()                               ; consume opening '
            lex_char()
            continue
        }

        ; string literal
        if c == $22 {
            c = read_src()                               ; consume opening "
            lex_string()
            continue
        }

        ; identifier / keyword
        if is_alpha_us(c) != 0 {
            read_ident()
            if kw_match() != 0 {
                emit_kw_head()
            } else {
                emit_ident_head()
            }
            out_ident()
            out_nl()
            continue
        }

        ; operator / punctuation
        c = read_src()
        lex_operator(c)
    }

    emit_eof()

    _close(src_hand)
    _close(dst_hand)
}

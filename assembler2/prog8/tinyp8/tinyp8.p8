; tinyp8.p8 -- a port of tinyp8.s to Prog8.
;
; This is the self-host milestone for the host p8c compiler: a real,
; working compiler written in our language and compiled by us. The
; compiled output is meant to be byte-equivalent (or behaviorally
; equivalent) to the hand-written tinyp8.s.
;
; All file I/O syscalls are bound as asmsubs targeting the nmos-default
; emulator stubs at $F006..$F03C. The carry-flag EOF signal from `read`
; is captured via a small inline-asm helper that stashes the EOF state
; in a module-level `src_eof` byte.

%target nmos
%address $0200

; ---- syscall asmsubs ----
asmsub _exit(ubyte code) = $F00F
asmsub _close(ubyte handle) = $F015

; ---- module-level state ----
ubyte src_hand
ubyte dst_hand
ubyte peek_buf
ubyte peek_ok
ubyte src_eof
ubyte tmp_byte

; ---- low-level I/O helpers (inline asm wrappers) ----
;
; Each wrapper is a Prog8 sub whose body is one %asm{{...}} block.
; We deliberately reference the mangled p8v_<sub>_arg_<name> slots
; so the wrappers see the same parameter values the caller wrote.

; argv(i) -> uword: the emulator returns A=low, X=high.
; Prog8 expects uword in A:Y; we shuffle X -> Y via A (NMOS-compatible).
sub _argv(ubyte i) -> uword {
    %asm{{ "lda p8v__argv_arg_i\njsr $f01e\npha\ntxa\ntay\npla\nrts" }}
}

sub _argc() -> ubyte {
    %asm{{ "jsr $f01b\nrts" }}
}

; open(uword filename) -> ubyte handle. Emulator: A=low, X=high. Our
; uword in A:Y -- so we move Y -> X before the JSR.
sub _open(uword filename) -> ubyte {
    %asm{{ "lda p8v__open_arg_filename\nldx p8v__open_arg_filename+1\njsr $f012\nrts" }}
}

sub _openout(uword filename) -> ubyte {
    %asm{{ "lda p8v__openout_arg_filename\nldx p8v__openout_arg_filename+1\njsr $f021\nrts" }}
}

; read(handle) -> byte. EOF is signalled via carry; we stash it in
; the module-level src_eof byte (0 = data valid, 1 = EOF).
sub _read(ubyte handle) -> ubyte {
    %asm{{ "lda p8v__read_arg_handle\njsr $f018\nbcc .ok\nlda #1\nsta p8v_src_eof\nlda #0\nrts\n.ok:\nsta __p8c_tmp0\nlda #0\nsta p8v_src_eof\nlda __p8c_tmp0\nrts" }}
}

; write(byte, handle). Emulator: A=byte, X=handle.
sub _write(ubyte b, ubyte handle) {
    %asm{{ "ldx p8v__write_arg_handle\nlda p8v__write_arg_b\njsr $f024\nrts" }}
}


; ---- source I/O ----

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


; ---- destination I/O ----

sub write_dst(ubyte b) {
    _write(b, dst_hand)
}


; ---- skip helpers ----

sub skip_to_nl() {
    ubyte c
    repeat {
        c = read_src()
        if src_eof != 0 {
            break
        }
        if c == $0a {
            break
        }
    }
}

sub skip_ws_comments() {
    repeat {
        ubyte c
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $20 {
            ; eat
            c = read_src()
        } else {
            if c == $09 {
                c = read_src()
            } else {
                if c == $0a {
                    c = read_src()
                } else {
                    if c == $0d {
                        c = read_src()
                    } else {
                        if c == $3b {                    ; ';'
                            skip_to_nl()
                        } else {
                            return
                        }
                    }
                }
            }
        }
    }
}


; ---- nibble helpers ----

sub nibble_to_ascii(ubyte n) -> ubyte {
    if n >= $0a {
        return n + $57                                   ; 'a' - 10
    }
    return n + $30                                       ; '0'
}

sub hex_nibble(ubyte c) -> ubyte {
    if c >= $61 {                                        ; 'a'
        return c - $57
    }
    if c >= $41 {                                        ; 'A'
        return c - $37
    }
    return c - $30
}


; ---- emitters ----
;
; Each "print one char" sequence is 7 bytes:
;   lda #ch        ; A9 ch
;   jsr write_b    ; 20 09 F0   (write_b = $F009)

sub emit_print_char(ubyte ch) {
    write_dst($a9)                                       ; LDA #
    write_dst(ch)
    write_dst($20)                                       ; JSR
    write_dst($09)                                       ; low byte of $F009
    write_dst($f0)                                       ; high byte
}

sub emit_print_ub_seq(ubyte b) {
    ubyte hi
    ubyte lo
    hi = b >> 4
    lo = b & $0f
    emit_print_char(nibble_to_ascii(hi))
    emit_print_char(nibble_to_ascii(lo))
}

sub emit_exit_seq() {
    write_dst($a9)                                       ; LDA #
    write_dst($00)                                       ; 0
    write_dst($20)                                       ; JSR
    write_dst($0f)                                       ; low byte of $F00F
    write_dst($f0)                                       ; high byte
}


; ---- parse helpers ----

sub parse_print_string() {
    ubyte c
    ; Find the opening quote.
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $22 {                                    ; '"'
            break
        }
    }
    ; Read string chars until closing quote.
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $22 {
            break
        }
        emit_print_char(c)
    }
    ; Trailing newline.
    emit_print_char($0a)
    skip_to_nl()
}

sub parse_print_ub() {
    ubyte c
    ; Find the '$' sigil.
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {                                    ; '$'
            break
        }
    }
    ; Two hex digits.
    c = read_src()
    if src_eof != 0 {
        return
    }
    tmp_byte = hex_nibble(c) << 4
    c = read_src()
    if src_eof != 0 {
        return
    }
    tmp_byte = tmp_byte | hex_nibble(c)
    emit_print_ub_seq(tmp_byte)
    emit_print_char($0a)
    skip_to_nl()
}

sub parse_print() {
    ubyte c
    ; Skip "rint"
    c = read_src()
    c = read_src()
    c = read_src()
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; Peek the next char: '_' means print_ub, otherwise string form.
    c = read_src()
    if src_eof != 0 {
        return
    }
    if c == $5f {                                        ; '_'
        ; Skip "ub"
        c = read_src()
        c = read_src()
        parse_print_ub()
    } else {
        ; The byte we already consumed should be ws or the leading
        ; quote; parse_print_string will scan forward to '"' so
        ; that's fine.
        parse_print_string()
    }
}


; ---- main compile loop ----

main {
    ; arg[0] = input file, arg[1] = output file
    uword fn
    fn = _argv(0)
    src_hand = _open(fn)
    fn = _argv(1)
    dst_hand = _openout(fn)

    peek_ok = 0
    src_eof = 0

    repeat {
        skip_ws_comments()
        if src_eof != 0 {
            break
        }
        ubyte c
        c = read_src()
        if src_eof != 0 {
            break
        }
        if c == $70 {                                    ; 'p'
            parse_print()
        } else {
            if c == $65 {                                ; 'e' -- "end"
                skip_to_nl()
                break
            } else {
                skip_to_nl()
            }
        }
    }

    emit_exit_seq()

    _close(src_hand)
    _close(dst_hand)
}

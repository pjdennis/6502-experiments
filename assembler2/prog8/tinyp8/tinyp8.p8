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

; Load address constant -- used to compute absolute addresses for the
; in-output __hex_print helper that v2 emits when a variable is
; referenced from print_ub.
const uword LOAD_ADDR = $0200

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

; v2 (variables) state:
;   var_addrs[c-'a'] = ZP address allocated for variable named `c`,
;                      or 0 if undeclared.
;   next_var_addr   = next free ZP slot, starts at $60 (above tinyp8's
;                      own state which lives below $40 in compiled
;                      programs that use this scheme).
;   helper_emitted  = 0 until __hex_print is emitted into the output;
;                     then 1, and helper_addr is its absolute address.
;   bytes_emitted   = count of bytes written to the output file so far;
;                     load_addr + bytes_emitted is the current output PC.
ubyte[26] var_addrs
ubyte next_var_addr
ubyte helper_emitted
uword bytes_emitted
uword helper_addr

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
    bytes_emitted = bytes_emitted + 1
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
    ; Scan past whitespace. The next non-ws byte is either '$' for a
    ; literal byte value or a lowercase letter for a variable reference.
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {                                    ; '$' -- literal
            break
        }
        if c >= $61 {                                    ; lowercase letter -- v2 var ref
            if c <= $7a {
                ; Look up the variable's ZP address and emit a runtime
                ; hex-print sequence against it. If the variable was
                ; never declared (var_addrs[slot] == 0) we emit nothing
                ; useful, but the parse is still well-formed.
                ubyte addr
                addr = var_addrs[c - $61]
                if addr != 0 {
                    emit_print_ub_var(addr)
                }
                skip_to_nl()
                return
            }
        }
        ; otherwise keep scanning (skip ws / other chars)
    }
    ; Two hex digits (literal form).
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

sub parse_print_uw() {
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
    ; Four hex digits -- emit one print_char per nibble (no need to
    ; reassemble into a uword; each digit is independently printable).
    ubyte i
    for i in 0 to 3 {
        c = read_src()
        if src_eof != 0 {
            return
        }
        emit_print_char(nibble_to_ascii(hex_nibble(c)))
    }
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
    ; Peek the next char: '_' means print_ub/print_uw, else string form.
    c = read_src()
    if src_eof != 0 {
        return
    }
    if c == $5f {                                        ; '_'
        c = read_src()                                   ; 'u'
        c = read_src()                                   ; 'b' or 'w'
        if src_eof != 0 {
            return
        }
        if c == $77 {                                    ; 'w'
            parse_print_uw()
        } else {
            parse_print_ub()
        }
    } else {
        ; The byte we already consumed should be ws or the leading
        ; quote; parse_print_string will scan forward to '"' so
        ; that's fine.
        parse_print_string()
    }
}


; ---- v2: variable declarations + the runtime hex-print helper ----
;
; emit_hex_helper writes a position-relative byte-to-2-hex-chars
; routine inline into the output, wrapped in a JMP that branches over
; it so it isn't executed by accident. After this runs:
;   helper_addr = absolute address (load_addr + offset) callable via JSR
;   helper_emitted = 1
; The helper itself only uses BCC/BNE for branching and JSR/JMP $F009
; (write_b) for output, so its bytes are position-independent except
; for the wrapping JMP.

inline sub emit_hex_helper() {
    if helper_emitted != 0 {
        return
    }
    ; Compute where the helper will live and where to branch around
    ; it: JMP-around starts at the current position, the helper proper
    ; starts 3 bytes later (after the JMP), the user code resumes 38
    ; bytes after that.
    uword start = LOAD_ADDR + bytes_emitted
    helper_addr = start + 3                              ; helper starts here
    uword after = helper_addr + 38                       ; user code resumes here
    ; JMP <after>
    write_dst($4c)
    write_dst(lsb(after))
    write_dst(msb(after))
    ; --- the 38-byte helper itself (position-independent) ---
    write_dst($48)                                       ; pha
    write_dst($4a)                                       ; lsr a
    write_dst($4a)                                       ; lsr a
    write_dst($4a)                                       ; lsr a
    write_dst($4a)                                       ; lsr a
    write_dst($c9)                                       ; cmp #
    write_dst($0a)                                       ;   #$0a
    write_dst($90)                                       ; bcc
    write_dst($05)                                       ;   +5 -> digit1
    write_dst($18)                                       ; clc
    write_dst($69)                                       ; adc #
    write_dst($57)                                       ;   'a' - 10
    write_dst($d0)                                       ; bne
    write_dst($03)                                       ;   +3 -> print1
    write_dst($18)                                       ; clc        (.digit1)
    write_dst($69)                                       ; adc #
    write_dst($30)                                       ;   '0'
    write_dst($20)                                       ; jsr        (.print1)
    write_dst($09)                                       ;   low byte of $F009
    write_dst($f0)                                       ;   high byte
    write_dst($68)                                       ; pla
    write_dst($29)                                       ; and #
    write_dst($0f)                                       ;   $0f -- low nibble
    write_dst($c9)                                       ; cmp #
    write_dst($0a)                                       ;   #$0a
    write_dst($90)                                       ; bcc
    write_dst($05)                                       ;   +5 -> digit2
    write_dst($18)                                       ; clc
    write_dst($69)                                       ; adc #
    write_dst($57)                                       ;   'a' - 10
    write_dst($d0)                                       ; bne
    write_dst($03)                                       ;   +3 -> print2
    write_dst($18)                                       ; clc        (.digit2)
    write_dst($69)                                       ; adc #
    write_dst($30)                                       ;   '0'
    write_dst($4c)                                       ; jmp        (.print2 -- tail call)
    write_dst($09)                                       ;   $F009
    write_dst($f0)
    helper_emitted = 1
}

; parse_let -- handles a single `let X = $YY` statement. The 'l' has
; already been read; we expect "et " then the variable name (one
; lowercase letter) then ' = $XX'. Emits code that stores $YY into
; the variable's ZP slot.
sub parse_let() {
    ubyte c
    ; skip "et"
    c = read_src()
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; skip whitespace
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c != $20 {                                    ; not space
            if c != $09 {                                ; not tab
                break
            }
        }
    }
    ; c is the variable name (single char). Index into var_addrs.
    ubyte slot
    slot = c - $61                                       ; 'a'
    if var_addrs[slot] == 0 {
        var_addrs[slot] = next_var_addr
        next_var_addr = next_var_addr + 1
    }
    ubyte addr
    addr = var_addrs[slot]
    ; skip ws + '='
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $3d {                                    ; '='
            break
        }
    }
    ; ---- RHS: parse first operand and emit its load. Then check for
    ;       an optional `+` or `-` followed by a second operand.
    parse_let_emit_load_first()
    if src_eof != 0 {
        return
    }
    ; Skip whitespace; if next non-ws is '+' or '-', emit arithmetic.
    repeat {
        c = peek_src()
        if src_eof != 0 {
            break
        }
        if c == $20 {                                    ; space
            c = read_src()
        } else {
            if c == $09 {                                ; tab
                c = read_src()
            } else {
                break
            }
        }
    }
    c = peek_src()
    if src_eof == 0 {
        if c == $2b {                                    ; '+'
            c = read_src()
            parse_let_emit_arith($18)                    ; CLC/ADC path
        } else {
            if c == $2d {                                ; '-'
                c = read_src()
                parse_let_emit_arith($38)                ; SEC/SBC path
            }
        }
    }
    write_dst($85)                                       ; STA zp
    write_dst(addr)
    skip_to_nl()
}

; Helper: parse + emit the LDA for the first RHS operand. The value
; ends up in A at runtime; the caller then either stores it directly
; (no arithmetic) or chains an ADC/SBC against the second operand.
sub parse_let_emit_load_first() {
    ubyte c
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {                                    ; '$' literal
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
            write_dst($a9)                               ; LDA #
            write_dst(tmp_byte)
            return
        }
        if c >= $61 {
            if c <= $7a {
                write_dst($a5)                           ; LDA zp
                write_dst(var_addrs[c - $61])
                return
            }
        }
    }
}

; Helper: emit CLC/SEC + ADC/SBC against the second operand.
; first_op = $18 (CLC) for ADD path, $38 (SEC) for SUB path.
sub parse_let_emit_arith(ubyte first_op) {
    write_dst(first_op)
    ubyte zp_op
    ubyte imm_op
    if first_op == $18 {
        zp_op = $65                                      ; ADC zp
        imm_op = $69                                     ; ADC #
    } else {
        zp_op = $e5                                      ; SBC zp
        imm_op = $e9                                     ; SBC #
    }
    ubyte c
    repeat {
        c = peek_src()
        if src_eof != 0 {
            return
        }
        if c == $20 {
            c = read_src()
        } else {
            if c == $09 {
                c = read_src()
            } else {
                break
            }
        }
    }
    c = read_src()
    if src_eof != 0 {
        return
    }
    if c == $24 {                                        ; '$' literal
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
        write_dst(imm_op)
        write_dst(tmp_byte)
        return
    }
    ; variable
    write_dst(zp_op)
    write_dst(var_addrs[c - $61])
}

; Emit a print_ub call against a variable reference (single letter).
; The byte at `addr` is loaded into A and then JSR'd to the in-output
; hex-print helper, which writes 2 ASCII hex chars. A trailing newline
; matches the literal-form output.
sub emit_print_ub_var(ubyte addr) {
    emit_hex_helper()
    write_dst($a5)                                       ; LDA zp
    write_dst(addr)
    write_dst($20)                                       ; JSR
    write_dst(lsb(helper_addr))
    write_dst(msb(helper_addr))
    ; trailing newline
    emit_print_char($0a)
}

; ---- v6: `while X != $YY` loop with a fixed-shape increment body ----
;
; The body is restricted to `let X = X + $ZZ` (variable += literal),
; which compiles to a known 7 bytes; that lets us hard-code both the
; BEQ skip displacement (10 bytes = body + jmp) and the JMP-back
; target (recorded as bytes_emitted at the loop top).
;
;   while X != $YY
;       let X = X + $ZZ
;
; Compiled output (14 bytes per while):
;   loop_top: lda <X>        ; 2
;             cmp #$YY       ; 2
;             beq +10        ; 2  -- skip body + jmp on equal
;             lda <X>        ; 2
;             clc            ; 1
;             adc #$ZZ       ; 2
;             sta <X>        ; 2
;             jmp loop_top   ; 3
;   loop_exit:
sub parse_while() {
    ubyte c
    ; skip 'h','i','l','e'
    c = read_src()
    c = read_src()
    c = read_src()
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; skip ws to variable name
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c >= $61 {
            if c <= $7a {
                break
            }
        }
    }
    ubyte x_addr
    x_addr = var_addrs[c - $61]
    ; skip ws to '!='
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $21 {                                    ; '!'
            break
        }
    }
    c = read_src()                                       ; '='
    if src_eof != 0 {
        return
    }
    ; skip ws to '$'
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {
            break
        }
    }
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
    ubyte cmp_val
    cmp_val = tmp_byte
    skip_to_nl()
    ; ---- Read the body: `let X = X + $ZZ` ----
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $6c {                                    ; 'l' of "let"
            break
        }
    }
    c = read_src()                                       ; 'e'
    c = read_src()                                       ; 't'
    ; loop var
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c >= $61 {
            if c <= $7a {
                break
            }
        }
    }
    ; '='
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $3d {
            break
        }
    }
    ; loop var on RHS (not validated)
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c >= $61 {
            if c <= $7a {
                break
            }
        }
    }
    ; '+'
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $2b {
            break
        }
    }
    ; '$'
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {
            break
        }
    }
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
    ubyte incr
    incr = tmp_byte
    skip_to_nl()
    ; ---- Emit the loop ----
    uword loop_top
    loop_top = LOAD_ADDR + bytes_emitted
    write_dst($a5)                                       ; LDA zp <X>
    write_dst(x_addr)
    write_dst($c9)                                       ; CMP #
    write_dst(cmp_val)
    write_dst($f0)                                       ; BEQ
    write_dst($0a)                                       ;   +10
    write_dst($a5)                                       ; LDA zp
    write_dst(x_addr)
    write_dst($18)                                       ; CLC
    write_dst($69)                                       ; ADC #
    write_dst(incr)
    write_dst($85)                                       ; STA zp
    write_dst(x_addr)
    write_dst($4c)                                       ; JMP
    write_dst(lsb(loop_top))
    write_dst(msb(loop_top))
}


; ---- v3: conditional `if X == $YY then print_ub Z` ----
;
; Restricted form: the then-clause must be exactly `print_ub <letter>`
; which compiles to a known 10-byte sequence. That lets us hard-code
; the BNE displacement and avoid any forward-reference back-patching.
;
; Compiled output for `if X == $YY then print_ub Z`:
;   lda <X_addr>      ; 2 bytes
;   cmp #$YY          ; 2 bytes
;   bne +10           ; 2 bytes  -- skip over the then-block
;   lda <Z_addr>      ; 2  (print_ub var)
;   jsr <hex_helper>  ; 3
;   lda #$0a; jsr write_b ; 5 (newline)
; Total: 16 bytes per if.
sub parse_if() {
    ubyte c
    ; skip 'f' (the 'i' was consumed by the dispatcher)
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; skip ws to variable name (1 char)
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c >= $61 {
            if c <= $7a {
                break
            }
        }
    }
    ubyte x_slot
    x_slot = c - $61
    ubyte x_addr
    x_addr = var_addrs[x_slot]
    ; skip ws to '=='
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $3d {                                    ; '='
            break
        }
    }
    ; skip second '='
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; skip ws to '$'
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $24 {                                    ; '$'
            break
        }
    }
    ; two hex digits -> compare value
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
    ubyte cmp_val
    cmp_val = tmp_byte
    ; skip ws then "then"
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $74 {                                    ; 't'
            break
        }
    }
    ; consume "hen"
    c = read_src()
    c = read_src()
    c = read_src()
    if src_eof != 0 {
        return
    }
    ; skip ws to "print_ub <z>"
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c == $70 {                                    ; 'p'
            break
        }
    }
    ; consume "rint_ub"
    c = read_src()  ; r
    c = read_src()  ; i
    c = read_src()  ; n
    c = read_src()  ; t
    c = read_src()  ; _
    c = read_src()  ; u
    c = read_src()  ; b
    if src_eof != 0 {
        return
    }
    ; skip ws to variable letter
    repeat {
        c = read_src()
        if src_eof != 0 {
            return
        }
        if c >= $61 {
            if c <= $7a {
                break
            }
        }
    }
    ubyte z_slot
    z_slot = c - $61
    ubyte z_addr
    z_addr = var_addrs[z_slot]
    ; Ensure the helper exists in the output -- before we emit the
    ; conditional, so its size doesn't shift our hard-coded BNE
    ; displacement.
    emit_hex_helper()
    ; Emit the 16-byte conditional.
    write_dst($a5)                                       ; LDA zp x_addr
    write_dst(x_addr)
    write_dst($c9)                                       ; CMP #
    write_dst(cmp_val)
    write_dst($d0)                                       ; BNE
    write_dst($0a)                                       ;   +10 (skip then-block)
    ; then-block: print_ub Z (10 bytes)
    write_dst($a5)                                       ; LDA zp z_addr
    write_dst(z_addr)
    write_dst($20)                                       ; JSR
    write_dst(lsb(helper_addr))
    write_dst(msb(helper_addr))
    write_dst($a9)                                       ; LDA #
    write_dst($0a)                                       ;   '\n'
    write_dst($20)                                       ; JSR
    write_dst($09)                                       ;   $F009
    write_dst($f0)
    skip_to_nl()
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
    next_var_addr = $60
    helper_emitted = 0
    bytes_emitted = 0
    ; var_addrs[] zeroed by BSS init.

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
            if c == $6c {                                ; 'l' -- "let"
                parse_let()
            } else {
                if c == $69 {                                ; 'i' -- "if"
                    parse_if()
                } else {
                    if c == $77 {                                ; 'w' -- "while"
                        parse_while()
                    } else {
                        if c == $65 {                                ; 'e' -- "end"
                            skip_to_nl()
                            break
                        } else {
                            skip_to_nl()
                        }
                    }
                }
            }
        }
    }

    emit_exit_seq()

    _close(src_hand)
    _close(dst_hand)
}

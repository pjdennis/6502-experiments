; sysio -- file/exit syscalls for the "nmos" emulator machine.
;
; Thin register-ABI asmsubs over the emulator's $F006+ stub jmp table (installed
; by the nmos machine). The monolith p1.p8 %imports this; the wendy2 build picks
; up the same-interface libraries/wendy2/sysio.p8 instead (the $F800 disk ports).
; Keeping this one swappable module is the only target-specific source in the
; compiler -- see WENDY2_MONOLITH_BANKING_PLAN.md.
;
; sys_read_raw returns msb=EOF flag (1 => at EOF), lsb=byte. The caller's
; prog8 wrapper turns that into a byte + its own EOF global.

%option no_symbol_prefixing, ignore_unused

sysio {
    extsub $F00F = sys_exit(ubyte code @A)
    extsub $F015 = sys_close(ubyte handle @A)

    asmsub sys_argv(ubyte i @A) -> uword @AY {
        %asm {{
            jsr  $f01e
            pha
            txa
            tay
            pla
            rts
        }}
    }

    asmsub sys_open(uword filename @AY) -> ubyte @A {
        %asm {{
            pha
            tya
            tax
            pla
            jsr  $f012
            rts
        }}
    }

    asmsub sys_openout(uword filename @AY) -> ubyte @A {
        %asm {{
            pha
            tya
            tax
            pla
            jsr  $f021
            rts
        }}
    }

    ; A=byte, Y=EOF flag (Y!=0 => EOF) -> packed uword (msb=EOF, lsb=byte).
    asmsub sys_read_raw(ubyte handle @A) -> uword @AY {
        %asm {{
            jsr  $f018
            bcc  sys_read_ok
            lda  #0
            ldy  #1
            rts
            sys_read_ok:
            ldy  #0
            rts
        }}
    }

    asmsub sys_write(ubyte b @A, ubyte handle @X) {
        %asm {{
            jsr  $f024
            rts
        }}
    }
}

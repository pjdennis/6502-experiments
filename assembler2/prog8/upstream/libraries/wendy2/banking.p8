; Upper-window memory banking for the wendy2c machine.
;
; The lower 32K ($0000-$7FFF) is fixed RAM; the window $8000-$EFFF is one of
; 8 RAM banks selected by VIA PORT B ($F000) bits 0-4. The lower-fixed RAM
; configs that yield 8 distinct upper banks are (see WENDY2_BANKING_TARGET_PLAN.md
; S2.2): logical bank 0..7 -> PORTB cfg $01,$11,$12,$13,$14,$15,$16,$17.
; (cfg $00/$10 map ROM into the window; we don't use them here.)
;
; PORTB bit 5 is the LCD E strobe and bits 6-7 are unused; set_raw preserves
; them. IRQs are masked program-wide (syslib init_system), so switches are
; already atomic; an interrupt-driven program must bracket switches itself.

%option no_symbol_prefixing, ignore_unused

banking {
    ; logical bank (0..7) -> PORTB config byte (bits 0-4)
    ubyte[8] cfgtab = [$01, $11, $12, $13, $14, $15, $16, $17]

    ; write the bank field (PORTB bits 0-4) = cfg, preserving bits 5-7
    sub set_raw(ubyte cfg) {
        @($f000) = (@($f000) & $e0) | cfg
    }

    ; current bank field (PORTB bits 0-4)
    sub get_raw() -> ubyte {
        return @($f000) & $1f
    }

    ; select logical upper bank 0..7
    sub set_upper_bank(ubyte n) {
        set_raw(cfgtab[n])
    }

    ; read one byte from `win` ($8000-$EFFF) in logical bank n, restoring the
    ; previously-selected config.
    sub bank_peek(ubyte n, uword win) -> ubyte {
        ubyte saved = get_raw()
        set_raw(cfgtab[n])
        ubyte v = @(win)
        set_raw(saved)
        return v
    }

    ; write one byte to `win` ($8000-$EFFF) in logical bank n, restoring the
    ; previously-selected config.
    sub bank_poke(ubyte n, uword win, ubyte val) {
        ubyte saved = get_raw()
        set_raw(cfgtab[n])
        @(win) = val
        set_raw(saved)
    }
}

; sysio -- file/exit syscalls for the wendy2c machine (the $F800-$F80F disk
; OS-call ports, installed when the emulator runs with --disk DIR).
;
; Same interface as libraries/nmos/sysio.p8 so the monolith p1.p8 builds for
; either target unchanged; only this module differs. The ports live in fixed
; high RAM, so these work from any mapped bank. See os.p8 for the raw ABI and
; WENDY2_MONOLITH_BANKING_PLAN.md for the overall scheme.
;
; wendy2 has no argv: the compiler reads/writes fixed staged filenames on the
; SPI disk (in.p8 -> out.s). sys_argv returns those names so p1.p8's start()
; (fn = sys_argv(0); open(fn); ...) is unchanged.

%option no_symbol_prefixing, ignore_unused

sysio {
    const uword P_NAME   = $f800     ; W: append filename byte
    const uword P_NCLEAR = $f801     ; W: clear filename buffer
    const uword P_OPENR  = $f802     ; R: open-for-read  -> handle
    const uword P_OPENW  = $f803     ; R: open-for-write -> handle
    const uword P_SEL    = $f804     ; W: select current handle
    const uword P_READ   = $f805     ; R: read byte from current handle
    const uword P_EOF    = $f806     ; R: EOF of current handle (bit7)
    const uword P_WRITE  = $f807     ; W: write byte to current handle
    const uword P_CLOSE  = $f808     ; W: close current handle
    const uword P_POWER  = $f80f     ; W: power off / halt (code)

    str IN_NAME  = "in.p8"
    str OUT_NAME = "out.s"

    sub sys_argv(ubyte i) -> uword {
        if i == 0 {
            return &IN_NAME
        }
        return &OUT_NAME
    }

    sub setname(uword name) {
        @(P_NCLEAR) = 0
        uword p = name
        while @(p) != 0 {
            @(P_NAME) = @(p)
            p++
        }
    }

    sub sys_open(uword filename) -> ubyte {
        setname(filename)
        return @(P_OPENR)
    }

    sub sys_openout(uword filename) -> ubyte {
        setname(filename)
        return @(P_OPENW)
    }

    ; returns packed uword: msb = EOF flag (1 => at EOF), lsb = byte read.
    sub sys_read_raw(ubyte handle) -> uword {
        @(P_SEL) = handle
        if (@(P_EOF) & $80) != 0 {
            return mkword(1, 0)
        }
        return mkword(0, @(P_READ))
    }

    sub sys_write(ubyte b, ubyte handle) {
        @(P_SEL) = handle
        @(P_WRITE) = b
    }

    sub sys_close(ubyte handle) {
        @(P_SEL) = handle
        @(P_CLOSE) = 0
    }

    sub sys_exit(ubyte code) {
        @(P_POWER) = code
    }
}

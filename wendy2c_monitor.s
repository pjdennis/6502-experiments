; wendy2c boot MONITOR -- alternate boot ROM.
;
; Loads and runs programs from the simulated SPI "disk" (the emulator's
; --disk directory) over the $F800+ file-I/O OS calls. At boot it reads the
; disk file "autoexec" into a buffer and runs each line as a program name:
; load that file to $4000 and execute it. Programs return to the monitor when
; they exit (see the signature/return-stub contract below), so the monitor
; advances to the next autoexec line. When the lines are exhausted it halts.
;
; Memory: this ROM lives at $8000-$FFFF (the reset/config-$00 view). Programs
; load into the fixed lower-32K RAM at $4000; a launch stub in lower RAM
; switches the upper window to RAM bank $01 and jumps to $4000 (removing this
; ROM from the map -- hence the stub runs from RAM). On exit a program jumps
; to the return stub in lower RAM, which maps the ROM back (config $00) and
; re-enters the monitor. The wendy2 syslib's exit jumps to $0320 iff the
; monitor signature byte ($A5 at $02FF) is present, else it halts (STP), so
; the same programs still run standalone under the upload boot ROM.
; See WENDY2_DISK_BOOT_DESIGN.md.

  .include base_config_wendy2c.inc

; ---- OS-call ports ($F800+, provided by the emulator's --disk chip) ----
P_NAME   = $f800
P_NCLEAR = $f801
P_OPENR  = $f802
P_SEL    = $f804
P_READ   = $f805
P_EOF    = $f806
P_CLOSE  = $f808

; ---- zero page ----
DISPLAY_STRING_PARAM = $00      ; 2 bytes (display_string ABI)
DESTL  = $10
DESTH  = $11
HANDLE = $12
NP     = $14                    ; name pointer (2 bytes)

PROGRAM_LOAD = $4000

; ---- fixed lower-RAM layout (untouched by loaded programs, which use $4000+) ----
MON_SIG      = $02ff            ; = $A5 tells the syslib a monitor is present
LAUNCH_RAM   = $0300            ; launch stub (bank $01 + jmp $4000)
RETURN_RAM   = $0320            ; return stub (config $00 + jmp run_next) -- exit target
LINEBUF      = $0400            ; current program-name line
AX_POS       = $04fe            ; autoexec cursor
AX_LEN       = $04ff            ; autoexec length
AX_BUF       = $0500            ; autoexec contents (<=256 bytes)

  .org $8000

reset:
  sei
  cld
  ldx #$ff
  txs

  ; VIA: make banking bits + display pins outputs (config stays $00 = ROM)
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_PORT + DDR_OFFSET
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET
  lda #E
  trb DISPLAY_ENABLE_PORT
  tsb DISPLAY_ENABLE_PORT + DDR_OFFSET

  jsr reset_and_enable_display_no_cursor

  ; copy the launch + return stubs into fixed lower RAM
  ldx #0
.copy_launch:
  lda launch_stub_src,x
  sta LAUNCH_RAM,x
  inx
  cpx #(launch_stub_end - launch_stub_src)
  bne .copy_launch
  ldx #0
.copy_return:
  lda return_stub_src,x
  sta RETURN_RAM,x
  inx
  cpx #(return_stub_end - return_stub_src)
  bne .copy_return

  ; mark the monitor present so program exits return here
  lda #$a5
  sta MON_SIG

  jsr clear_display
  lda #<banner
  ldx #>banner
  jsr display_string

  ; read the whole "autoexec" file into AX_BUF
  jsr read_autoexec
  lda #0
  sta AX_POS
  ; fall through to run_next


; ---- run the next autoexec line (also the warm-start re-entry point) ----
run_next:
  ldx AX_POS
  cpx AX_LEN
  bcs .alldone
  ; copy one line (to LF/CR/EOF) into LINEBUF
  ldy #0
.cp:
  cpx AX_LEN
  bcs .lineend
  lda AX_BUF,x
  inx
  cmp #$0a
  beq .lineend
  cmp #$0d
  beq .lineend
  sta LINEBUF,y
  iny
  cpy #63
  bne .cp
.lineend:
  lda #0
  sta LINEBUF,y
  stx AX_POS                 ; save advanced cursor
  cpy #0
  beq run_next               ; blank line -> next
  jmp load_and_run
.alldone:
  stp


; ---- load the file named in LINEBUF to $4000, then launch it ----
load_and_run:
  lda #<LINEBUF
  ldx #>LINEBUF
  jsr os_open_read
  cmp #0
  bne .ok
  jsr clear_display
  lda #<msg_notfound
  ldx #>msg_notfound
  jsr display_string
  jmp run_next               ; skip the bad line, keep going
.ok:
  sta HANDLE
  sta P_SEL
  lda #<PROGRAM_LOAD
  sta DESTL
  lda #>PROGRAM_LOAD
  sta DESTH
.rd:
  lda P_EOF
  bmi .eof
  lda P_READ
  sta (DESTL)                ; 65C02 (zp) store
  inc DESTL
  bne .rd
  inc DESTH
  bra .rd
.eof:
  lda HANDLE
  sta P_CLOSE
  jmp LAUNCH_RAM             ; switch to bank $01 and jmp $4000


; ---- read "autoexec" into AX_BUF; AX_LEN = byte count (0 if missing) ----
read_autoexec:
  stz AX_LEN
  lda #<autoexec_name
  ldx #>autoexec_name
  jsr os_open_read
  cmp #0
  beq .none
  sta HANDLE
  sta P_SEL
  ldy #0
.rd:
  lda P_EOF
  bmi .done
  lda P_READ
  sta AX_BUF,y
  iny
  bne .rd                    ; cap at 256 bytes
.done:
  sty AX_LEN
  lda HANDLE
  sta P_CLOSE
.none:
  rts


; ---- OS open-for-read: name ptr in A(lo)/X(hi) -> A = handle ----
os_open_read:
  sta NP
  stx NP+1
  sta P_NCLEAR
  ldy #0
.push:
  lda (NP),y
  beq .open
  sta P_NAME
  iny
  bne .push
.open:
  lda P_OPENR
  rts


; ---- stubs copied into fixed lower RAM (survive the bank switch) ----
launch_stub_src:
  lda #BANK_MASK
  trb BANK_PORT
  lda #BANK_START            ; $01 -> upper window = RAM bank 0; ROM out
  tsb BANK_PORT
  jmp PROGRAM_LOAD
launch_stub_end:

return_stub_src:
  lda #BANK_MASK
  trb BANK_PORT              ; config $00 -> ROM mapped back at $8000+
  jmp run_next
return_stub_end:

banner:        asciiz "wendy2 monitor"
autoexec_name: asciiz "autoexec"
msg_notfound:  asciiz "prog not found"

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

  ; ---- vectors ----
  .org $fffc
  .word reset
  .word $0000

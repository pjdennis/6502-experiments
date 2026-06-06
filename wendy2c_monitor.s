; wendy2c boot MONITOR -- alternate boot ROM.
;
; Loads and runs a program from the simulated SPI "disk" (the emulator's
; --disk directory) over the $F800+ file-I/O OS calls. The program to run is
; named by the contents of the disk file "autoexec" (first line = filename).
;
; Memory: this ROM lives at $8000-$FFFF (the reset/config-$00 view). It reads
; the program into the fixed lower-32K RAM at $4000, then a small launch stub
; copied into lower RAM switches the upper window to RAM bank $01 and jumps to
; $4000 (which removes this ROM from the map -- hence the stub runs from RAM).
; See WENDY2_DISK_BOOT_DESIGN.md.
;
; Build: vasm6502_oldstyle -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc
;        (run from the repo root so the .include paths resolve).

  .include base_config_wendy2c.inc

; ---- OS-call ports ($F800+, provided by the emulator's --disk chip) ----
P_NAME   = $f800        ; W: append filename byte
P_NCLEAR = $f801        ; W: clear filename buffer
P_OPENR  = $f802        ; R: open-for-read -> handle
P_SEL    = $f804        ; W: select current handle
P_READ   = $f805        ; R: read byte from current handle
P_EOF    = $f806        ; R: EOF of current handle (bit7)
P_CLOSE  = $f808        ; W: close current handle

; ---- zero page ----
DISPLAY_STRING_PARAM = $00      ; 2 bytes (display_string ABI)
DESTL  = $10                    ; load destination pointer
DESTH  = $11
HANDLE = $12
NP     = $14                    ; name pointer (2 bytes)

PROGRAM_LOAD = $4000
LAUNCH_RAM   = $0300            ; launch stub copied here (fixed lower RAM)
LINEBUF      = $0400            ; autoexec line / program-name buffer

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

  ; copy the launch stub into fixed lower RAM
  ldx #0
.copy_stub:
  lda launch_stub_src,x
  sta LAUNCH_RAM,x
  inx
  cpx #(launch_stub_end - launch_stub_src)
  bne .copy_stub

  jsr clear_display
  lda #<banner
  ldx #>banner
  jsr display_string

  jsr do_autoexec               ; loads+runs the named program (no return on success)

  ; only reached if there was no autoexec / the program wasn't found
  stp


; ---- read "autoexec"; its first line is the program name; load+run it ----
do_autoexec:
  lda #<autoexec_name
  ldx #>autoexec_name
  jsr os_open_read              ; A = handle (0 = missing)
  cmp #0
  bne .have
  rts
.have:
  sta HANDLE
  sta P_SEL
  ldy #0
.rd:
  lda P_EOF
  bmi .done
  lda P_READ
  cmp #$0a                      ; stop at LF
  beq .done
  cmp #$0d                      ; or CR
  beq .done
  sta LINEBUF,y
  iny
  cpy #63
  bne .rd
.done:
  lda #0
  sta LINEBUF,y
  lda HANDLE
  sta P_CLOSE
  jmp load_and_run             ; tail


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
  rts
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
  sta (DESTL)                  ; 65C02 (zp) store
  inc DESTL
  bne .rd
  inc DESTH
  bra .rd
.eof:
  lda HANDLE
  sta P_CLOSE
  jmp LAUNCH_RAM               ; switch to bank $01 and jmp $4000


; ---- OS open-for-read: name ptr in A(lo)/X(hi) -> A = handle ----
os_open_read:
  sta NP
  stx NP+1
  sta P_NCLEAR                 ; clear name buffer (value ignored)
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


; ---- launch stub: copied to LAUNCH_RAM, runs from fixed lower RAM ----
launch_stub_src:
  lda #BANK_MASK
  trb BANK_PORT
  lda #BANK_START              ; $01 -> upper window = RAM bank 0; ROM out
  tsb BANK_PORT
  jmp PROGRAM_LOAD
launch_stub_end:

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

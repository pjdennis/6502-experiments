write_b = $F009
write_d = $F00C

r_open   = $F005
r_read   = $EFFF
w_close  = $F000

FILE_HANDLE = $00

* = $1000

; On entry A;X points to zero terminated filename
; On exit A contains the file handle
open
  LDA r_open
  RTS

; On entry A contains the file handle
; On exit A contains a character read from the file
;         C set if at end, clear otherwise
read
  LDA r_read
  CMP# $04
  BEQ r_at_end
  CLC
  RTS
r_at_end
  SEC
  RTS

; On entry A contains the file handle to close
close
  STA w_close
  RTS


start
  LDA# <filename
  LDX# >filename
  JSR open
  STAZ FILE_HANDLE
loop
  LDAZ FILE_HANDLE
  JSR read
  BCS done
  JSR write_d
  JMP loop
done
  LDAZ FILE_HANDLE
  JSR close
  BRK $00


filename
  DATA "test.txt" $00


  DATA start

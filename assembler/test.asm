write_b = $F009

write_d = $F00C

; On entry A;X points to zero terminated filename
; On exit A contains the file handle
open    = $F012

; On entry A contains the file handle to close
close   = $F015

; On entry A contains the file handle
; On exit A contains a character read from the file
;         C set if at end, clear otherwise
read    = $F018


FILE_HANDLE = $00


* = $1000


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

  .include test_inc.asm

  DATA start

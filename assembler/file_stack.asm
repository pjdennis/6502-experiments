; Requires:
;   FILE_STACK    - 1 past the highest address from which the stack grows down
;   FS_FILENAME   - filename
;   FS_CURR_FILE  - zero page location of the current file handle
;   FS_CURR_LINEL - zero page location of the current line
;   FS_CURR_LINEH - "
;   open, close   - functions to open and close a file


  .zeropage

FILE_STACK_L DATA $00
FILE_STACK_H DATA $00

  .code


init_file_stack
  LDA# <FILE_STACK
  STAZ FILE_STACK_L
  LDA# >FILE_STACK
  STAZ FILE_STACK_H
  RTS


; On exit Z is set if file stack empty, clear otherwise
file_stack_empty
  LDAZ FILE_STACK_L
  CMP# <FILE_STACK
  BNE fse_done
  LDAZ FILE_STACK_H
  CMP# >FILE_STACK
fse_done
  RTS


; On entry FS_FILENAME contains the file name
;          FS_CURR_LINEL;FS_CURR_LINEH contains the current line number
;          FS_CURR_FILE contains the current file handle
; On exit X is preserved
push_file_stack
  LDY# $FF
pfs_len_loop
  INY
  LDA,Y FS_FILENAME
  BNE pfs_len_loop
  TYA
  STAZ TEMP
  CLC    ; -1
  LDAZ FILE_STACK_L
  SBCZ TEMP
  STAZ FILE_STACK_L
  LDAZ FILE_STACK_H
  SBC# $00
  STAZ FILE_STACK_H
  LDY# $FF
pfs_copy_loop
  INY
  LDA,Y FS_FILENAME
  STAZ(),Y FILE_STACK_L
  BNE pfs_copy_loop
  ; Adjust pointer for line number and file handle
  SEC
  LDAZ FILE_STACK_L
  SBC# $03
  STAZ FILE_STACK_L
  LDAZ FILE_STACK_H
  SBC# $00
  STAZ FILE_STACK_H
  ; Store file handle
  LDY# $00
  LDA FS_CURR_FILE
  STAZ(),Y FILE_STACK_L
  INY
  ; Store line number
  LDA FS_CURR_LINEL
  STAZ(),Y FILE_STACK_L
  INY
  LDA FS_CURR_LINEH
  STAZ(),Y FILE_STACK_L
  INY
; Reset line number and open new file
  LDA# $00
  STAZ FS_CURR_LINEL
  STAZ FS_CURR_LINEH

  TXA
  PHA
  LDA# <FS_FILENAME
  LDX# >FS_FILENAME
  JSR open
  STAZ FS_CURR_FILE
  PLA
  TAX

  RTS


; On exit FS_CURR_FILE contains the previous file handle
;         FS_CURR_LINEL;FS_CURR_LINEH contains the previous line number
pop_file_stack
; Close currnet file and restore from filestack
  LDAZ FS_CURR_FILE
  JSR close
  LDY# $00
  LDAZ(),Y FILE_STACK_L
  STAZ FS_CURR_FILE
  INY
  LDAZ(),Y FILE_STACK_L
  STAZ FS_CURR_LINEL
  INY
  LDAZ(),Y FILE_STACK_L
  STAZ FS_CURR_LINEH
rc_pop_loop
  INY
  LDAZ(),Y FILE_STACK_L
  BNE rc_pop_loop
; Adjust stack pointer
  TYA
  SEC  ; +1
  ADCZ FILE_STACK_L
  STAZ FILE_STACK_L
  LDA# $00
  ADCZ FILE_STACK_H
  STAZ FILE_STACK_H
  RTS

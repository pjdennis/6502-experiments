; Requires:
;   FILE_STACK    - 1 past the highest address from which the stack grows down
;   FS_FILENAME   - filename
;   FS_CURR_FILE  - zero page location of the current file handle
;   FS_CURR_LINEL - zero page location of the current line
;   FS_CURR_LINEH - "
;   open, close   - functions to open and close a file


  .zeropage

FS_PL   DATA $00 ; Pointer to the current location in the file stack
FS_PH   DATA $00 ; "
FS_TEMP DATA $00 ; Temporary location for use in calculations

  .code


file_stack_init
  LDA# <FILE_STACK
  STAZ FS_PL
  LDA# >FILE_STACK
  STAZ FS_PH
  RTS


; On exit Z is set if file stack empty, clear otherwise
file_stack_empty
  LDAZ FS_PL
  CMP# <FILE_STACK
  BNE fse_done
  LDAZ FS_PH
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
  STAZ FS_TEMP
  CLC    ; -1
  LDAZ FS_PL
  SBCZ FS_TEMP
  STAZ FS_PL
  LDAZ FS_PH
  SBC# $00
  STAZ FS_PH
  LDY# $FF
pfs_copy_loop
  INY
  LDA,Y FS_FILENAME
  STAZ(),Y FS_PL
  BNE pfs_copy_loop
  ; Adjust pointer for line number and file handle
  SEC
  LDAZ FS_PL
  SBC# $03
  STAZ FS_PL
  LDAZ FS_PH
  SBC# $00
  STAZ FS_PH
  ; Store file handle
  LDY# $00
  LDA FS_CURR_FILE
  STAZ(),Y FS_PL
  INY
  ; Store line number
  LDA FS_CURR_LINEL
  STAZ(),Y FS_PL
  INY
  LDA FS_CURR_LINEH
  STAZ(),Y FS_PL
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
  LDAZ(),Y FS_PL
  STAZ FS_CURR_FILE
  INY
  LDAZ(),Y FS_PL
  STAZ FS_CURR_LINEL
  INY
  LDAZ(),Y FS_PL
  STAZ FS_CURR_LINEH
rc_pop_loop
  INY
  LDAZ(),Y FS_PL
  BNE rc_pop_loop
; Adjust stack pointer
  TYA
  SEC  ; +1
  ADCZ FS_PL
  STAZ FS_PL
  LDA# $00
  ADCZ FS_PH
  STAZ FS_PH
  RTS

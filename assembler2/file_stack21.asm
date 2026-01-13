; Requires:
;   FILE_STACK    - 1 past the highest address from which the stack grows down
;   FS_FILENAME   - filename buffer
;   FS_CURR_FILE  - zero page location of the current file handle
;   FS_CURR_LINEL - zero page location of the current line number (low byte)
;   FS_CURR_LINEH - zero page location of the current line number (high byte)
;   FS_NEXT_CHAR  - zero page location to store last character read
;   open, close, read - file I/O functions
;
; Optional:
;   FS_ERR_NO_FILE - error handler for read_char when no file is open
;                    If not defined, read_char returns SEC like normal EOF

; The file stack grows downwards. Each entry includes (from low to high address):
;
; For file sources (FS_SRC_TYPE = 0):
;   File name of current file (0-terminated)
;   File handle of previous file (1 byte)
;   Line number of previous file (2 bytes)
;
; For memory sources (FS_SRC_TYPE = 1):
;   Single null byte (empty "filename" marker)
;   Previous FS_SRC_TYPE (1 byte)
;   Previous FS_MEM_PTR (2 bytes)
;   Previous FS_MEM_END (2 bytes)
;   Previous line number (2 bytes)

  .zeropage

FS_PL   .data $00 ; Pointer to the current location in the file stack
FS_PH   .data $00 ; "
FS_TEMP .data $00 ; Temporary location for use in calculations

; Memory source support
FS_SRC_TYPE   .data $00 ; Source type: 0=file, 1=memory
FS_MEM_PTR_L  .data $00 ; Current read position in memory (low)
FS_MEM_PTR_H  .data $00 ; Current read position in memory (high)
FS_MEM_END_L  .data $00 ; End of memory buffer (low)
FS_MEM_END_H  .data $00 ; End of memory buffer (high)

  .code


file_stack_init
  LDA #<FILE_STACK
  STA FS_PL
  LDA #>FILE_STACK
  STA FS_PH
  LDA #$00
  STA FS_SRC_TYPE
  RTS


; On exit Z is set if file stack empty, clear otherwise
file_stack_empty
  LDA FS_PL
  CMP #<FILE_STACK
  BNE .done
  LDA FS_PH
  CMP #>FILE_STACK
.done
  RTS


; On entry FS_FILENAME contains the file name of the new file to open
;            and push on stack
;          FS_CURR_LINEL;FS_CURR_LINEH contains the current line
;            number of the current file
;          FS_CURR_FILE contains the current file handle
; On exit X is preserved
push_file_stack
  LDY #$FF
.len_loop
; A <- len(FS_FILENAME)
  INY
  LDA FS_FILENAME,Y
  BNE .len_loop
; Decrease file stack pointer by len(FS_FILENAME) + 4
; (null terminator + handle + 2-byte line number)
  TYA
  CLC
  ADC #$04
  STA FS_TEMP
  SEC
  LDA FS_PL
  SBC FS_TEMP
  STA FS_PL
  LDA FS_PH
  SBC #$00
  STA FS_PH
  LDY #$FF
.copy_loop
  INY
  LDA FS_FILENAME,Y
  STA (FS_PL),Y
  BNE .copy_loop
  ; Store file handle
  INY
  LDA FS_CURR_FILE
  STA (FS_PL),Y
  INY
  ; Store line number
  LDA FS_CURR_LINEL
  STA (FS_PL),Y
  INY
  LDA FS_CURR_LINEH
  STA (FS_PL),Y
  INY
; Reset line number and open new file
  LDA #$00
  STA FS_SRC_TYPE     ; File source
  STA FS_CURR_LINEL
  STA FS_CURR_LINEH

  TXA
  PHA
  LDA #<FS_FILENAME
  LDX #>FS_FILENAME
  JSR open
  STA FS_CURR_FILE
  PLA
  TAX

  RTS


; Push a memory source onto the stack
; On entry: FS_MEM_PTR_L/H = start of memory buffer to read
;           FS_MEM_END_L/H = end of memory buffer (one past last byte)
; On exit: X is preserved, reading will continue from memory buffer
;
; Stack frame format for memory source:
;   Null byte (empty filename marker)
;   Previous source type (1 byte)
;   Previous mem ptr L/H (2 bytes)
;   Previous mem end L/H (2 bytes)
;   Previous line number L/H (2 bytes)
; Total: 8 bytes (fixed)
push_memory_source
  ; Decrease file stack pointer by 8
  SEC
  LDA FS_PL
  SBC #$08
  STA FS_PL
  LDA FS_PH
  SBC #$00
  STA FS_PH
  ; Store null byte (empty filename marker)
  LDY #$00
  LDA #$00
  STA (FS_PL),Y
  ; Store previous source type
  INY
  LDA FS_SRC_TYPE
  STA (FS_PL),Y
  ; Store previous mem ptr
  INY
  LDA FS_MEM_PTR_L
  STA (FS_PL),Y
  INY
  LDA FS_MEM_PTR_H
  STA (FS_PL),Y
  ; Store previous mem end
  INY
  LDA FS_MEM_END_L
  STA (FS_PL),Y
  INY
  LDA FS_MEM_END_H
  STA (FS_PL),Y
  ; Store previous line number
  INY
  LDA FS_CURR_LINEL
  STA (FS_PL),Y
  INY
  LDA FS_CURR_LINEH
  STA (FS_PL),Y
  ; Set up new memory source (pointers already set by caller)
  LDA #$01
  STA FS_SRC_TYPE     ; Memory source
  LDA #$00
  STA FS_CURR_LINEL
  STA FS_CURR_LINEH
  RTS


; On exit FS_CURR_FILE contains the previous file handle
;         FS_CURR_LINEL;FS_CURR_LINEH contains the previous line number
pop_file_stack
; Close current file and restore from filestack
  LDA FS_CURR_FILE
  JSR close
; Pop the filename
  LDY #$FF
.pop_loop
  INY
  LDA (FS_PL),Y
  BNE .pop_loop
; Pop the file handle
  INY
  LDA (FS_PL),Y
  STA FS_CURR_FILE
; Pop the line number
  INY
  LDA (FS_PL),Y
  STA FS_CURR_LINEL
  INY
  LDA (FS_PL),Y
  STA FS_CURR_LINEH
; Adjust stack pointer
  TYA
  SEC  ; +1
  ADC FS_PL
  STA FS_PL
  LDA #$00
  ADC FS_PH
  STA FS_PH
  ; Restore to file source type
  LDA #$00
  STA FS_SRC_TYPE
  RTS


; Pop a memory source and restore previous state
pop_memory_source
  ; Skip null byte
  LDY #$00
  ; Restore previous source type
  INY
  LDA (FS_PL),Y
  STA FS_SRC_TYPE
  ; Restore mem ptr
  INY
  LDA (FS_PL),Y
  STA FS_MEM_PTR_L
  INY
  LDA (FS_PL),Y
  STA FS_MEM_PTR_H
  ; Restore mem end
  INY
  LDA (FS_PL),Y
  STA FS_MEM_END_L
  INY
  LDA (FS_PL),Y
  STA FS_MEM_END_H
  ; Restore line number
  INY
  LDA (FS_PL),Y
  STA FS_CURR_LINEL
  INY
  LDA (FS_PL),Y
  STA FS_CURR_LINEH
  ; Adjust stack pointer (add 8)
  CLC
  LDA FS_PL
  ADC #$08
  STA FS_PL
  LDA FS_PH
  ADC #$00
  STA FS_PH
  RTS


; Read character from current source (file or memory)
; On exit: A = character (also stored in FS_NEXT_CHAR)
;          C = 0 if char read, C = 1 if all sources exhausted
file_stack_read_char
  LDA FS_SRC_TYPE
  BNE .read_memory
  ; Type 0 = file source
  LDA FS_CURR_FILE
  BEQ .no_source
  JSR read
  BCC .got_char
  ; EOF on current file - pop stack and try previous file
  JSR pop_file_stack
  LDA FS_CURR_FILE
  BEQ .all_done
  JMP file_stack_read_char
.read_memory
  ; Type 1 = memory source
  ; Check if we've reached the end
  LDA FS_MEM_PTR_L
  CMP FS_MEM_END_L
  BNE .mem_not_done
  LDA FS_MEM_PTR_H
  CMP FS_MEM_END_H
  BEQ .mem_exhausted
.mem_not_done
  ; Read byte from memory pointer
  LDY #$00
  LDA (FS_MEM_PTR_L),Y
  PHA
  ; Increment memory pointer
  INC FS_MEM_PTR_L
  BNE .mem_got_char
  INC FS_MEM_PTR_H
.mem_got_char
  PLA
.got_char
  STA FS_NEXT_CHAR
  CLC
  RTS
.mem_exhausted
  ; Memory source exhausted - pop and continue
  JSR pop_memory_source
  JMP file_stack_read_char
.no_source
  .ifdef FS_ERR_NO_FILE
  JMP FS_ERR_NO_FILE
  .endif
.all_done
  SEC
  RTS

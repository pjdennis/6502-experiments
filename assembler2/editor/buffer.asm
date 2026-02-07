; Text buffer data structure and operations
;
; Memory layout:
;   TEXT_BUF ($2000) - Start of text buffer (contiguous, newline-delimited)
;   LINE_TBL ($C000) - Line pointer table (16-bit offsets, max 1024 lines)
;
; The text buffer stores all text contiguously. Lines are delimited by $0A.
; The line table stores 16-bit pointers to the start of each line.
; Insertions/deletions shift all text after the edit point.

TEXT_BUF    = $2000  ; Start of text buffer
TEXT_LIMIT  = $C000  ; End of text buffer space
LINE_TBL    = $C000  ; Line pointer table (2 bytes per entry)
LINE_LIMIT  = $E000  ; End of line table (supports up to 4096 entries = 2048 lines, but
                     ; practically limited by available text space)
MAX_LINES   = $03FF  ; Maximum line count (1023), 0-indexed

  .zeropage

BUF_END16     .data $0000 ; Points one past last byte of text
LINE_COUNT16  .data $0000 ; Number of lines in buffer (16-bit)
BUF_PTR16     .data $0000 ; General-purpose buffer pointer
BUF_SRC16     .data $0000 ; Source pointer for block moves
BUF_DST16     .data $0000 ; Destination pointer for block moves
BUF_LEN16     .data $0000 ; Length/count for block moves
BUF_TEMP      .data $00   ; Temp byte for buffer operations
FILE_HANDLE   .data $00   ; File handle for load/save
BUF_LIMIT     .data $00   ; High byte of buffer limit (default >TEXT_LIMIT)

  .code

; Initialize empty buffer
; Sets up an empty buffer with one empty line
buf_init
  SET16 TEXT_BUF BUF_END16
  ; Add a newline to have at least one line
  LDY #$00
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
  ; Build line table
  JSR buf_rebuild_lines
  RTS

; Load file into buffer
; File handle in A (already opened)
; On return: buffer contains file contents, line table built
; Carry set = file was truncated, carry clear = fully loaded
buf_load_file
  STA FILE_HANDLE
  SET16 TEXT_BUF BUF_END16
  LDA #$00
  STA BUF_TEMP            ; Clear truncation flag

.read_loop
  LDA FILE_HANDLE
  JSR read
  BCS .read_done
  ; Store byte in buffer
  LDY #$00
  STA (BUF_END16),Y
  INC16 BUF_END16
  ; Check for buffer overflow
  LDA BUF_END16+$01
  CMP BUF_LIMIT
  BCC .read_loop
  ; Buffer full - file was truncated
  LDA #$FF
  STA BUF_TEMP
  JMP .read_done

.read_loop_2
  JMP .read_loop
.read_done
  ; Ensure buffer ends with newline
  SEC
  LDA BUF_END16
  SBC #$01
  STA BUF_PTR16
  LDA BUF_END16+$01
  SBC #$00
  STA BUF_PTR16+$01

  ; Check if last byte is newline
  LDY #$00
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .has_newline
  ; Need to add a newline
  LDA BUF_TEMP
  BNE .overwrite_last
  ; Not truncated - append trailing newline
  LDA #'\n'
  LDY #$00
  STA (BUF_END16),Y
  INC16 BUF_END16
  JMP .has_newline
.overwrite_last
  ; Truncated - overwrite last byte to stay within buffer limit
  LDA #'\n'
  LDY #$00
  STA (BUF_PTR16),Y
.has_newline

  ; If buffer is empty (nothing read), add a newline for one empty line
  LDA BUF_END16
  CMP #<TEXT_BUF
  BNE .not_empty
  LDA BUF_END16+$01
  CMP #>TEXT_BUF
  BNE .not_empty
  ; Empty buffer
  LDY #$00
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.not_empty

  JSR buf_rebuild_lines
  LDA BUF_TEMP
  BEQ .return_ok
  SEC                    ; Truncated
  RTS
.return_ok
  CLC                    ; Not truncated
  RTS

; Save buffer to file
; File handle in A (already opened for write)
; Writes all text except the final trailing newline of the last empty line
buf_save_file
  STA FILE_HANDLE
  SET16 TEXT_BUF BUF_PTR16

.write_loop
  ; Check if we've reached the end
  LDA BUF_PTR16+$01
  CMP BUF_END16+$01
  BCC .do_write
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .write_done

.do_write
  LDY #$00
  LDA (BUF_PTR16),Y
  LDX FILE_HANDLE
  JSR write
  INC16 BUF_PTR16
  JMP .write_loop

.write_done
  RTS

; Return line count in LINE_COUNT16
; (Already maintained by rebuild)
buf_line_count
  RTS

; Get pointer to start of line N (N in A/X, low/high)
; Returns pointer in BUF_PTR16
; Clobbers A, Y
buf_get_line_ptr
  ; Line table index = N * 2
  STA BUF_PTR16
  STX BUF_PTR16+$01
  ASL16 BUF_PTR16
  ; Add LINE_TBL base
  CLC
  LDA BUF_PTR16
  ADC #<LINE_TBL
  STA BUF_PTR16
  LDA BUF_PTR16+$01
  ADC #>LINE_TBL
  STA BUF_PTR16+$01
  ; Read the 16-bit pointer from the table
  LDY #$00
  LDA (BUF_PTR16),Y
  PHA
  INY
  LDA (BUF_PTR16),Y
  STA BUF_PTR16+$01
  PLA
  STA BUF_PTR16
  RTS

; Get length of line N (N in A/X, low/high)
; Returns length in A (capped at 255), not counting the newline
; Clobbers X, Y
buf_get_line_len
  JSR buf_get_line_ptr
  LDY #$00
.len_loop
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .len_done
  INY
  BNE .len_loop
  ; Line longer than 255 - cap at 255
  LDA #$FF
  RTS
.len_done
  TYA
  RTS

; Insert character at position in buffer
; A = character to insert
; BUF_PTR16 = position to insert at
; Shifts all following bytes right by 1
; Returns carry set = buffer full, carry clear = success
buf_insert_char
  STA BUF_TEMP
  ; Check if buffer is at capacity
  LDA BUF_END16+$01
  CMP BUF_LIMIT
  BCC .has_room
  SEC              ; Buffer full
  RTS
.has_room

  ; Move bytes from BUF_END16-1 down to BUF_PTR16, shifting right by 1
  ; Source = BUF_END16-1, dest = BUF_END16, count = BUF_END16-BUF_PTR16
  ; We copy backwards from end to insertion point

  ; Set up: copy from BUF_END16-1 to BUF_END16, working backwards
  CP16 BUF_END16 BUF_DST16
  SEC
  LDA BUF_END16
  SBC #$01
  STA BUF_SRC16
  LDA BUF_END16+$01
  SBC #$00
  STA BUF_SRC16+$01

.shift_right_loop
  ; Check if src has reached insert point (BUF_PTR16)
  LDA BUF_SRC16+$01
  CMP BUF_PTR16+$01
  BCC .shift_right_done
  BNE .do_copy_right
  LDA BUF_SRC16
  CMP BUF_PTR16
  BCC .shift_right_done

.do_copy_right
  LDY #$00
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y

  ; Decrement both pointers
  LDA BUF_SRC16
  BNE .no_borrow_s
  DEC BUF_SRC16+$01
.no_borrow_s
  DEC BUF_SRC16

  LDA BUF_DST16
  BNE .no_borrow_d
  DEC BUF_DST16+$01
.no_borrow_d
  DEC BUF_DST16

  JMP .shift_right_loop

.shift_right_done
  ; Store the new character
  LDY #$00
  LDA BUF_TEMP
  STA (BUF_PTR16),Y

  ; Increment buffer end
  INC16 BUF_END16

  CLC              ; Success
  RTS

; Delete character at BUF_PTR16
; Shifts all following bytes left by 1
buf_delete_char
  ; Copy from BUF_PTR16+1 to BUF_PTR16, forward to BUF_END16
  CLC
  LDA BUF_PTR16
  ADC #$01
  STA BUF_SRC16
  LDA BUF_PTR16+$01
  ADC #$00
  STA BUF_SRC16+$01
  CP16 BUF_PTR16 BUF_DST16

.shift_left_loop
  ; Check if src has reached end
  LDA BUF_SRC16+$01
  CMP BUF_END16+$01
  BCC .do_copy_left
  BNE .shift_left_done
  LDA BUF_SRC16
  CMP BUF_END16
  BCS .shift_left_done

.do_copy_left
  LDY #$00
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y

  INC16 BUF_SRC16
  INC16 BUF_DST16

  JMP .shift_left_loop

.shift_left_done
  ; Decrement buffer end
  SEC
  LDA BUF_END16
  SBC #$01
  STA BUF_END16
  LDA BUF_END16+$01
  SBC #$00
  STA BUF_END16+$01

  RTS

; Insert newline at BUF_PTR16 (splits current line)
; Returns carry set = buffer full, carry clear = success
buf_insert_newline
  LDA #'\n'
  JSR buf_insert_char
  BCS .full
  JSR buf_rebuild_lines
  CLC
.full
  RTS

; Delete entire line N (N in A/X, low/high)
; Removes the line and its trailing newline
buf_delete_line
  PHA
  TXA
  PHA

  ; Get pointer to start of this line
  PLA
  TAX
  PLA
  JSR buf_get_line_ptr

  ; Save start pointer
  CP16 BUF_PTR16 BUF_SRC16

  ; Find end of line (the newline character)
  LDY #$00
.find_newline
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .found_newline
  INY
  BNE .find_newline
.found_newline
  ; BUF_PTR16 + Y + 1 = start of next line (after newline)
  INY
  TYA
  CLC
  ADC BUF_SRC16
  STA BUF_SRC16
  LDA #$00
  ADC BUF_SRC16+$01
  STA BUF_SRC16+$01

  ; Now shift: copy from BUF_SRC16 to BUF_PTR16 up to BUF_END16
  ; BUF_PTR16 = destination (start of deleted line)
  ; BUF_SRC16 = source (start of next line)

.del_shift_loop
  ; Check if src has reached end
  LDA BUF_SRC16+$01
  CMP BUF_END16+$01
  BCC .del_do_copy
  BNE .del_shift_done
  LDA BUF_SRC16
  CMP BUF_END16
  BCS .del_shift_done

.del_do_copy
  LDY #$00
  LDA (BUF_SRC16),Y
  STA (BUF_PTR16),Y

  INC16 BUF_SRC16
  INC16 BUF_PTR16

  JMP .del_shift_loop

.del_shift_done
  ; Update buffer end: subtract the number of bytes removed
  ; New end = BUF_PTR16 (which is where we stopped copying to)
  CP16 BUF_PTR16 BUF_END16

  ; If buffer is now empty, add a newline
  LDA BUF_END16
  CMP #<TEXT_BUF
  BNE .del_not_empty
  LDA BUF_END16+$01
  CMP #>TEXT_BUF
  BNE .del_not_empty
  LDY #$00
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.del_not_empty

  JSR buf_rebuild_lines
  RTS

; Rebuild line pointer table by scanning for newlines
; Sets LINE_COUNT16 and fills LINE_TBL
buf_rebuild_lines
  SET16 $0000 LINE_COUNT16
  SET16 TEXT_BUF BUF_PTR16
  SET16 LINE_TBL BUF_DST16

  ; First line starts at TEXT_BUF
  LDY #$00
  LDA BUF_PTR16
  STA (BUF_DST16),Y
  INY
  LDA BUF_PTR16+$01
  STA (BUF_DST16),Y
  INC16 LINE_COUNT16

.scan_loop
  ; Check if we've reached the end
  LDA BUF_PTR16+$01
  CMP BUF_END16+$01
  BCC .scan_byte
  BNE .scan_done
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .scan_done

.scan_byte
  LDY #$00
  LDA (BUF_PTR16),Y
  INC16 BUF_PTR16

  CMP #'\n'
  BNE .scan_loop

  ; Found a newline - check if there's more text after it
  LDA BUF_PTR16+$01
  CMP BUF_END16+$01
  BCC .add_line
  BNE .scan_done
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .scan_done

.add_line
  ; Advance line table pointer
  CLC
  LDA BUF_DST16
  ADC #$02
  STA BUF_DST16
  LDA BUF_DST16+$01
  ADC #$00
  STA BUF_DST16+$01

  ; Store line start pointer
  LDY #$00
  LDA BUF_PTR16
  STA (BUF_DST16),Y
  INY
  LDA BUF_PTR16+$01
  STA (BUF_DST16),Y

  INC16 LINE_COUNT16

  JMP .scan_loop

.scan_done
  RTS

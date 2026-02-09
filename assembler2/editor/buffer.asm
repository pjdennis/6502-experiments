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
BATCH_BUF   = $E000  ; Staging buffer for batch insert (32 bytes)
BATCH_MAX   = 32     ; Maximum batch size

  .zeropage

BUF_END16:     .word     ; Points one past last byte of text
LINE_COUNT16:  .word     ; Number of lines in buffer (16-bit)
BUF_PTR16:     .word     ; General-purpose buffer pointer
BUF_SRC16:     .word     ; Source pointer for block moves
BUF_DST16:     .word     ; Destination pointer for block moves
BUF_LEN16:     .word     ; Length/count for block moves
BUF_TEMP:      .byte     ; Temp byte for buffer operations
BUF_DELTA:     .byte     ; Shift amount for block moves
FILE_HANDLE:   .byte     ; File handle for load/save
BUF_LIMIT:     .byte     ; High byte of buffer limit (default >TEXT_LIMIT)

  .code

; Initialize empty buffer
; Sets up an empty buffer with one empty line
buf_init:
  SET16 TEXT_BUF, BUF_END16
  ; Add a newline to have at least one line
  LDY #0
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
buf_load_file:
  STA FILE_HANDLE
  SET16 TEXT_BUF, BUF_END16
  LDA #0
  STA BUF_TEMP            ; Clear truncation flag

.read_loop:
  LDA FILE_HANDLE
  JSR read
  BCS .read_done
  ; Store byte in buffer
  LDY #0
  STA (BUF_END16),Y
  INC16 BUF_END16
  ; Check for buffer overflow
  LDA BUF_END16 + 1
  CMP BUF_LIMIT
  BCC .read_loop
  ; Buffer full - file was truncated
  LDA #$FF
  STA BUF_TEMP
  JMP .read_done

.read_loop_2:
  JMP .read_loop
.read_done:
  ; Ensure buffer ends with newline
  SEC
  SBCI16 BUF_END16, $0001, BUF_PTR16

  ; Check if last byte is newline
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .has_newline
  ; Need to add a newline
  LDA BUF_TEMP
  BNE .overwrite_last
  ; Not truncated - append trailing newline
  LDA #'\n'
  LDY #0
  STA (BUF_END16),Y
  INC16 BUF_END16
  JMP .has_newline
.overwrite_last:
  ; Truncated - overwrite last byte to stay within buffer limit
  LDA #'\n'
  LDY #0
  STA (BUF_PTR16),Y
.has_newline:

  ; If buffer is empty (nothing read), add a newline for one empty line
  LDA BUF_END16
  CMP #<TEXT_BUF
  BNE .not_empty
  LDA BUF_END16 + 1
  CMP #>TEXT_BUF
  BNE .not_empty
  ; Empty buffer
  LDY #0
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.not_empty:

  JSR buf_rebuild_lines
  LDA BUF_TEMP
  BEQ .return_ok
  SEC                    ; Truncated
  RTS
.return_ok:
  CLC                    ; Not truncated
  RTS

; Save buffer to file
; File handle in A (already opened for write)
; Writes all text except the final trailing newline of the last empty line
buf_save_file:
  STA FILE_HANDLE
  SET16 TEXT_BUF, BUF_PTR16

.write_loop:
  ; Check if we've reached the end
  LDA BUF_PTR16 + 1
  CMP BUF_END16 + 1
  BCC .do_write
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .write_done

.do_write:
  LDY #0
  LDA (BUF_PTR16),Y
  LDX FILE_HANDLE
  JSR write
  INC16 BUF_PTR16
  JMP .write_loop

.write_done:
  RTS

; Return line count in LINE_COUNT16
; (Already maintained by rebuild)
buf_line_count:
  RTS

; Get pointer to start of line N (N in A/X, low/high)
; Returns pointer in BUF_PTR16
; Clobbers A, Y
buf_get_line_ptr:
  ; Line table index = N * 2
  STAX16 BUF_PTR16
  ASL16 BUF_PTR16
  ; Add LINE_TBL base
  CLC
  LDA BUF_PTR16
  ADC #<LINE_TBL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #>LINE_TBL
  STA BUF_PTR16 + 1
  ; Read the 16-bit pointer from the table
  LDY #0
  LDA (BUF_PTR16),Y
  PHA
  INY
  LDA (BUF_PTR16),Y
  STA BUF_PTR16 + 1
  PLA
  STA BUF_PTR16
  RTS

; Get length of line N (N in A/X, low/high)
; Returns length in A (capped at 255), not counting the newline
; Clobbers X, Y
buf_get_line_len:
  JSR buf_get_line_ptr
  LDY #0
.len_loop:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .len_done
  INY
  BNE .len_loop
  ; Line longer than 255 - cap at 255
  LDA #$FF
  RTS
.len_done:
  TYA
  RTS

; Insert character at position in buffer
; A = character to insert
; BUF_PTR16 = position to insert at
; Shifts all following bytes right by 1
; Returns carry set = buffer full, carry clear = success
buf_insert_char:
  STA BUF_TEMP
  LDA #1
  STA BUF_DELTA
  JSR buf_shift_right
  BCS .full
  ; Store the new character
  LDY #0
  LDA BUF_TEMP
  STA (BUF_PTR16),Y
  CLC
  RTS
.full:
  SEC
  RTS

; Insert multiple characters from BATCH_BUF at position in buffer
; BUF_PTR16 = position to insert at
; BUF_DELTA = number of characters to insert
; Characters in BATCH_BUF[0..BUF_DELTA-1]
; Returns carry set = buffer full, carry clear = success
buf_insert_chars:
  JSR buf_shift_right
  BCS .batch_full
  ; Copy BUF_DELTA bytes from BATCH_BUF into the gap at BUF_PTR16
  LDY #0
.batch_copy:
  LDA BATCH_BUF,Y
  STA (BUF_PTR16),Y
  INY
  CPY BUF_DELTA
  BNE .batch_copy
  CLC
  RTS
.batch_full:
  SEC
  RTS

; Shift buffer right by BUF_DELTA bytes at BUF_PTR16
; Input: BUF_PTR16 = insert point, BUF_DELTA = shift amount
; Returns carry set = buffer full, carry clear = success
; Updates BUF_END16 on success
buf_shift_right:
  LDA BUF_DELTA
  STA BUF_LEN16
  LDA #0
  STA BUF_LEN16+1
  ; Fall through to the 16 bit version


; Shift buffer right by BUF_LEN16 bytes at BUF_PTR16 (16-bit version)
; Input: BUF_PTR16 = insert point, BUF_LEN16 = shift amount (16-bit)
; Returns carry set = buffer full, carry clear = success
; Updates BUF_END16 on success. Does not modify BUF_PTR16.
buf_shift_right_16:
  ; Check if buffer has room for BUF_LEN16 bytes
  CLC
  LDA BUF_END16
  ADC BUF_LEN16
  STA BUF_DST16              ; Temp: new end low
  LDA BUF_END16 + 1
  ADC BUF_LEN16 + 1
  CMP BUF_LIMIT
  BCC .sr16_has_room
  BNE .sr16_full
  LDA BUF_DST16
  BEQ .sr16_has_room         ; Exactly at limit is ok
.sr16_full:
  SEC
  RTS
.sr16_has_room:

  ; Check if nothing to move (insert at end)
  LDA BUF_END16 + 1
  CMP BUF_PTR16 + 1
  BNE .sr16_need_shift
  LDA BUF_END16
  CMP BUF_PTR16
  BEQ .sr16_shift_done
.sr16_need_shift:

  ; Set up BUF_SRC16 = page base of (BUF_END16-1)
  ; Y = low byte of (BUF_END16-1)
  SEC
  LDA BUF_END16
  SBC #1
  TAY                    ; Y = low byte of last source byte
  LDA BUF_END16 + 1
  SBC #0
  STA BUF_SRC16 + 1
  LDA #0
  STA BUF_SRC16          ; BUF_SRC16 = page-aligned base

  ; BUF_DST16 = BUF_SRC16 + BUF_LEN16
  CLC
  LDA BUF_SRC16          ; = 0
  ADC BUF_LEN16
  STA BUF_DST16
  LDA BUF_SRC16 + 1
  ADC BUF_LEN16 + 1
  STA BUF_DST16 + 1

  ; Check if insert point is on same page
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .sr16_full_page

  ; Same page as insert point: copy Y down to low byte of BUF_PTR16
.sr16_last_page:
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  CPY BUF_PTR16
  BEQ .sr16_shift_done
  DEY
  JMP .sr16_last_page

.sr16_full_page:
  ; Copy from Y down to 0 on this page
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  DEY
  CPY #$FF
  BNE .sr16_full_page

  ; Move to previous page
  DEC BUF_SRC16 + 1
  DEC BUF_DST16 + 1
  LDY #$FF

  ; Check if this is the page containing the insert point
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .sr16_full_page

  JMP .sr16_last_page

.sr16_shift_done:
  ; Update buffer end: add BUF_LEN16
  CLC
  LDA BUF_END16
  ADC BUF_LEN16
  STA BUF_END16
  LDA BUF_END16 + 1
  ADC BUF_LEN16 + 1
  STA BUF_END16 + 1

  CLC              ; Success
  RTS

; Insert a block of bytes from BUF_SRC16 into the text buffer at BUF_PTR16
; Input: BUF_PTR16 = insert point, BUF_SRC16 = source data, BUF_LEN16 = byte count
; Returns carry set = buffer full, carry clear = success
; Shifts existing data right by BUF_LEN16, then copies BUF_LEN16 bytes from BUF_SRC16
buf_insert_block:
  ; Check if buffer has room: BUF_END16 + BUF_LEN16 < BUF_LIMIT:00
  CLC
  LDA BUF_END16
  ADC BUF_LEN16
  STA BUF_DST16            ; Temp: new end low
  LDA BUF_END16 + 1
  ADC BUF_LEN16 + 1
  CMP BUF_LIMIT
  BCC .ib_has_room
  ; If equal, check low byte
  BNE .ib_full
  LDA BUF_DST16
  BEQ .ib_has_room         ; Exactly at limit is ok
.ib_full:
  SEC
  RTS
.ib_has_room:

  ; Shift right by BUF_LEN16 bytes (backward copy)
  ; Start from BUF_END16-1, copy to BUF_END16+BUF_LEN16-1, working backward

  ; Check if nothing to move (insert at end)
  CMP16 BUF_END16, BUF_PTR16
  BEQ .ib_shift_done

  ; Simple backward byte-at-a-time copy
  ; src_ptr = BUF_END16 - 1, dst_ptr = BUF_END16 + BUF_LEN16 - 1
  ; Copy backward until src_ptr < BUF_PTR16

  ; Set up dst = BUF_END16 + BUF_LEN16 - 1
  CLC
  LDA BUF_END16
  ADC BUF_LEN16
  STA BUF_DST16
  LDA BUF_END16 + 1
  ADC BUF_LEN16 + 1
  STA BUF_DST16 + 1
  ; -1
  LDA BUF_DST16
  BNE .ib_no_borrow1
  DEC BUF_DST16 + 1
.ib_no_borrow1:
  DEC BUF_DST16

  ; Set up src = BUF_END16 - 1
  PUSH16 BUF_SRC16         ; Save BUF_SRC16 (we need it after shift)
  LDA BUF_END16
  BNE .ib_no_borrow2
  DEC BUF_END16 + 1        ; Temporarily borrow from high byte
  ; We'll fix BUF_END16 after the loop
.ib_no_borrow2:
  DEC BUF_END16
  CP16 BUF_END16, BUF_SRC16   ; BUF_SRC16 = src pointer for copy

.ib_copy_back:
  LDY #0
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  ; Check if we've reached BUF_PTR16
  CMP16 BUF_SRC16, BUF_PTR16
  BEQ .ib_copy_back_done
  ; Decrement both pointers
  DEC16 BUF_SRC16
  DEC16 BUF_DST16
  JMP .ib_copy_back

.ib_copy_back_done:
  POP16 BUF_SRC16          ; Restore source data pointer

  ; Restore BUF_END16 (we decremented it)
  INC16 BUF_END16

.ib_shift_done:
  ; Update BUF_END16
  CLC
  LDA BUF_END16
  ADC BUF_LEN16
  STA BUF_END16
  LDA BUF_END16 + 1
  ADC BUF_LEN16 + 1
  STA BUF_END16 + 1

  ; Copy BUF_LEN16 bytes from BUF_SRC16 to gap at BUF_PTR16
  ; Forward copy: src=BUF_SRC16, dst=BUF_PTR16, count=BUF_LEN16
  CP16 BUF_LEN16, BUF_DST16  ; BUF_DST16 = remaining count
.ib_fill:
  LDY #0
  LDA (BUF_SRC16),Y
  STA (BUF_PTR16),Y
  INC16 BUF_SRC16
  INC16 BUF_PTR16
  DEC16 BUF_DST16
  TST16 BUF_DST16
  BNE .ib_fill

  CLC
  RTS

; Delete character at BUF_PTR16
; Shifts all following bytes left by 1
buf_delete_char:
  LDA #1
  STA BUF_DELTA
  JMP buf_shift_left

; Delete BUF_DELTA characters starting at BUF_PTR16
; Input: BUF_PTR16 = position, BUF_DELTA = count
; Shifts all following bytes left by BUF_DELTA, updates BUF_END16
buf_delete_chars:
  JMP buf_shift_left

; Delete entire line N (N in A/X, low/high)
; Removes the line and its trailing newline
buf_delete_line:
  JSR buf_get_line_ptr

  ; Find end of line (the newline character)
  LDY #0
.find_newline:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .found_newline
  INY
  BNE .find_newline
.found_newline:
  ; BUF_DELTA = Y + 1 (line content + newline)
  INY
  STY BUF_DELTA

  ; Delete BUF_DELTA bytes at BUF_PTR16
  JSR buf_delete_chars

  ; If buffer is now empty, add a newline
  LDA BUF_END16
  CMP #<TEXT_BUF
  BNE .del_not_empty
  LDA BUF_END16 + 1
  CMP #>TEXT_BUF
  BNE .del_not_empty
  LDY #0
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.del_not_empty:

  JSR buf_rebuild_lines
  RTS

; Delete N contiguous lines starting at line A/X
; Input: A/X = first line number (low/high), BUF_TEMP = count of lines to delete
; Handles end-of-file clamping, empty buffer, rebuilds line table once
buf_delete_lines:
  ; Save first line number
  STAX16 BUF_DST16

  ; Get pointer to start of first line
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of first line
  PUSH16 BUF_PTR16           ; Save dest pointer on stack

  ; Calculate line number after last deleted: first + count
  CLC
  LDA BUF_DST16
  ADC BUF_TEMP
  STA BUF_SRC16
  LDA BUF_DST16 + 1
  ADC #0
  STA BUF_SRC16 + 1         ; BUF_SRC16 = end line number

  ; If end line >= LINE_COUNT16, source = BUF_END16
  CMP16 BUF_SRC16, LINE_COUNT16
  BCC .get_end_ptr
  CP16 BUF_END16, BUF_SRC16
  JMP .have_source

.get_end_ptr:
  ; Get pointer to line after last deleted
  LDAX16 BUF_SRC16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of end line
  CP16 BUF_PTR16, BUF_SRC16

.have_source:
  ; BUF_SRC16 = source address (data to keep)
  POP16 BUF_PTR16            ; BUF_PTR16 = dest (start of deleted region)

  ; Calculate shift amount: BUF_LEN16 = BUF_SRC16 - BUF_PTR16
  SEC
  SBC16 BUF_SRC16, BUF_PTR16, BUF_LEN16

  ; Shift left by BUF_LEN16 bytes
  JSR buf_shift_left_16

  ; If buffer is now empty, add a newline
  LDA BUF_END16
  CMP #<TEXT_BUF
  BNE .dels_not_empty
  LDA BUF_END16 + 1
  CMP #>TEXT_BUF
  BNE .dels_not_empty
  LDY #0
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.dels_not_empty:

  JSR buf_rebuild_lines
  RTS

; Shift buffer left by BUF_DELTA bytes at BUF_PTR16
; Input: BUF_PTR16 = delete point, BUF_DELTA = shift amount
; Updates BUF_END16 on completion
buf_shift_left:
  LDA BUF_DELTA
  STA BUF_LEN16
  LDA #0
  STA BUF_LEN16 + 1
  ; Fall through to 16 bit version

; Shift buffer left by BUF_LEN16 bytes at BUF_PTR16 (16-bit version)
; Input: BUF_PTR16 = delete point, BUF_LEN16 = shift amount (16-bit)
; Updates BUF_END16 on completion
buf_shift_left_16:
  ; Compute source start = BUF_PTR16 + BUF_LEN16
  CLC
  LDA BUF_PTR16
  ADC BUF_LEN16
  STA BUF_SRC16
  LDA BUF_PTR16 + 1
  ADC BUF_LEN16 + 1
  STA BUF_SRC16 + 1

  ; Check if nothing to move (source >= BUF_END16)
  LDA BUF_SRC16 + 1
  CMP BUF_END16 + 1
  BCC .sl16_need_shift
  BNE .sl16_shift_done
  LDA BUF_SRC16
  CMP BUF_END16
  BCS .sl16_shift_done
.sl16_need_shift:

  ; Set up page-aligned BUF_SRC16 and Y
  LDA BUF_SRC16
  TAY                    ; Y = low byte of first source byte
  LDA BUF_SRC16 + 1
  STA BUF_SRC16 + 1
  LDA #0
  STA BUF_SRC16          ; BUF_SRC16 = page-aligned base

  ; BUF_DST16 = BUF_SRC16 - BUF_LEN16
  SEC
  LDA BUF_SRC16          ; = 0
  SBC BUF_LEN16
  STA BUF_DST16
  LDA BUF_SRC16 + 1
  SBC BUF_LEN16 + 1
  STA BUF_DST16 + 1

  ; Check if BUF_END16 is on the same page
  LDA BUF_SRC16 + 1
  CMP BUF_END16 + 1
  BNE .sl16_full_page

  ; Same page as end: copy Y up to (BUF_END16 low - 1)
.sl16_last_page:
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  CPY BUF_END16
  BNE .sl16_last_page
  JMP .sl16_shift_done

.sl16_full_page:
  ; Copy from Y up to $FF on this page
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  BNE .sl16_full_page

  ; Move to next page
  INC BUF_SRC16 + 1
  INC BUF_DST16 + 1
  LDY #0

  ; Check if this is the page containing BUF_END16
  LDA BUF_SRC16 + 1
  CMP BUF_END16 + 1
  BNE .sl16_full_page

  ; Check if BUF_END16 low byte is 0 (end is at page boundary)
  LDA BUF_END16
  BEQ .sl16_shift_done

  JMP .sl16_last_page

.sl16_shift_done:
  ; Update buffer end: subtract BUF_LEN16
  SEC
  LDA BUF_END16
  SBC BUF_LEN16
  STA BUF_END16
  LDA BUF_END16 + 1
  SBC BUF_LEN16 + 1
  STA BUF_END16 + 1

  RTS

; Rebuild line pointer table by scanning for newlines
; Sets LINE_COUNT16 and fills LINE_TBL
buf_rebuild_lines:
  SET16 $0000, LINE_COUNT16
  SET16 TEXT_BUF, BUF_PTR16
  SET16 LINE_TBL, BUF_DST16

  ; First line starts at TEXT_BUF
  LDY #0
  LDA BUF_PTR16
  STA (BUF_DST16),Y
  INY
  LDA BUF_PTR16 + 1
  STA (BUF_DST16),Y
  INC16 LINE_COUNT16

.scan_loop:
  ; Check if we've reached the end
  LDA BUF_PTR16 + 1
  CMP BUF_END16 + 1
  BCC .scan_byte
  BNE .scan_done
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .scan_done

.scan_byte:
  LDY #0
  LDA (BUF_PTR16),Y
  INC16 BUF_PTR16

  CMP #'\n'
  BNE .scan_loop

  ; Found a newline - check if there's more text after it
  LDA BUF_PTR16 + 1
  CMP BUF_END16 + 1
  BCC .add_line
  BNE .scan_done
  LDA BUF_PTR16
  CMP BUF_END16
  BCS .scan_done

.add_line:
  ; Advance line table pointer
  CLC
  ADCI16 BUF_DST16, $0002, BUF_DST16

  ; Store line start pointer
  LDY #0
  LDA BUF_PTR16
  STA (BUF_DST16),Y
  INY
  LDA BUF_PTR16 + 1
  STA (BUF_DST16),Y

  INC16 LINE_COUNT16

  JMP .scan_loop

.scan_done:
  RTS

; Increment line pointers after current line by 1
; Used after inserting a non-newline character (no lines added/removed)
; Input: FILE_LINE16 = current line number
; Clobbers: A, Y
buf_adjust_lines_inc:
  ; Calculate number of entries to adjust: LINE_COUNT16 - FILE_LINE16 - 1
  SEC
  LDA LINE_COUNT16
  SBC FILE_LINE16
  STA BUF_LEN16
  LDA LINE_COUNT16 + 1
  SBC FILE_LINE16 + 1
  STA BUF_LEN16 + 1

  ; Subtract 1 (we start from line+1, not line)
  LDA BUF_LEN16
  BNE .inc_no_borrow
  DEC BUF_LEN16 + 1
.inc_no_borrow:
  DEC BUF_LEN16

  ; If count <= 0, nothing to adjust
  LDA BUF_LEN16 + 1
  BMI .inc_done
  ORA BUF_LEN16
  BEQ .inc_done

  ; Calculate LINE_TBL entry for (FILE_LINE16 + 1)
  ; Entry address = LINE_TBL + (FILE_LINE16 + 1) * 2
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  ASL16 BUF_PTR16
  CLC
  LDA BUF_PTR16
  ADC #<LINE_TBL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #>LINE_TBL
  STA BUF_PTR16 + 1

.inc_loop:
  ; Increment the 16-bit line pointer at (BUF_PTR16)
  LDY #0
  CLC
  LDA (BUF_PTR16),Y
  ADC BUF_DELTA
  STA (BUF_PTR16),Y
  BCC .inc_no_carry
  INY
  LDA (BUF_PTR16),Y
  ADC #0
  STA (BUF_PTR16),Y
.inc_no_carry:

  ; Advance to next LINE_TBL entry (+2 bytes)
  CLC
  ADCI16 BUF_PTR16, $0002, BUF_PTR16

  ; Decrement count
  LDA BUF_LEN16
  BNE .inc_dec_no_borrow
  DEC BUF_LEN16 + 1
.inc_dec_no_borrow:
  DEC BUF_LEN16

  ; Check if count reached 0
  TST16 BUF_LEN16
  BNE .inc_loop

.inc_done:
  RTS

; Decrement line pointers after current line by 1
; Used after deleting a non-newline character (no lines added/removed)
; Input: FILE_LINE16 = current line number
; Clobbers: A, Y
buf_adjust_lines_dec:
  ; Calculate number of entries to adjust: LINE_COUNT16 - FILE_LINE16 - 1
  SEC
  LDA LINE_COUNT16
  SBC FILE_LINE16
  STA BUF_LEN16
  LDA LINE_COUNT16 + 1
  SBC FILE_LINE16 + 1
  STA BUF_LEN16 + 1

  ; Subtract 1
  LDA BUF_LEN16
  BNE .dec_no_borrow
  DEC BUF_LEN16 + 1
.dec_no_borrow:
  DEC BUF_LEN16

  ; If count <= 0, nothing to adjust
  LDA BUF_LEN16 + 1
  BMI .dec_done
  ORA BUF_LEN16
  BEQ .dec_done

  ; Calculate LINE_TBL entry for (FILE_LINE16 + 1)
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  ASL16 BUF_PTR16
  CLC
  LDA BUF_PTR16
  ADC #<LINE_TBL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #>LINE_TBL
  STA BUF_PTR16 + 1

.dec_loop:
  ; Decrement the 16-bit line pointer at (BUF_PTR16)
  LDY #0
  SEC
  LDA (BUF_PTR16),Y
  SBC BUF_DELTA
  STA (BUF_PTR16),Y
  BCS .dec_no_borrow2
  INY
  LDA (BUF_PTR16),Y
  SBC #0
  STA (BUF_PTR16),Y
.dec_no_borrow2:

  ; Advance to next LINE_TBL entry (+2 bytes)
  CLC
  ADCI16 BUF_PTR16, $0002, BUF_PTR16

  ; Decrement count
  LDA BUF_LEN16
  BNE .dec_dec_no_borrow
  DEC BUF_LEN16 + 1
.dec_dec_no_borrow:
  DEC BUF_LEN16

  ; Check if count reached 0
  TST16 BUF_LEN16
  BNE .dec_loop

.dec_done:
  RTS

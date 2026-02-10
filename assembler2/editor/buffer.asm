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

; Buffer size: normal build = 40KB, small build = 256 bytes
  .ifndef small_buffer
TEXT_LIMIT  = $C000  ; End of text buffer space (40KB: $2000-$BFFF)
  .else
TEXT_LIMIT  = $2100  ; End of text buffer space (256 bytes: $2000-$20FF)
  .endif

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
  ADCI16 BUF_PTR16, LINE_TBL, BUF_PTR16
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
  BCC .has_room
  BNE .full
  LDA BUF_DST16
  BEQ .has_room         ; Exactly at limit is ok
.full:
  SEC
  RTS
.has_room:

  ; Check if nothing to move (insert at end)
  LDA BUF_END16 + 1
  CMP BUF_PTR16 + 1
  BNE .need_shift
  LDA BUF_END16
  CMP BUF_PTR16
  BEQ .shift_done
.need_shift:

  ; Set up mem_copy_up parameters:
  ;   BUF_SRC16 = source start (insert point = BUF_PTR16)
  ;   BUF_DST16 = destination (insert point + shift amount)
  ;   BUF_PTR16 = source end (BUF_END16)
  ; Save BUF_PTR16 (callers need it preserved)
  PUSH16 BUF_PTR16
  CP16 BUF_PTR16, BUF_SRC16
  CLC
  ADC16 BUF_SRC16, BUF_LEN16, BUF_DST16
  CP16 BUF_END16, BUF_PTR16
  JSR mem_copy_up
  POP16 BUF_PTR16

.shift_done:
  ; Update buffer end: add BUF_LEN16
  CLC
  ADC16 BUF_END16, BUF_LEN16, BUF_END16

  CLC              ; Success
  RTS

; Backward copy (safe when dst >= src or non-overlapping)
; Input: BUF_SRC16 = source start, BUF_PTR16 = source end (exclusive),
;        BUF_DST16 = destination start
; Preserves BUF_SRC16. Clobbers A, Y, BUF_PTR16, BUF_DST16
mem_copy_up:
  ; Check empty case (SRC >= END)
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BCC .not_empty
  BNE .done
  LDA BUF_SRC16
  CMP BUF_PTR16
  BCS .done
.not_empty:

  ; Compute offset = BUF_DST16 - BUF_SRC16 (constant shift amount)
  ; Store in BUF_DST16 temporarily
  SEC
  SBC16 BUF_DST16, BUF_SRC16, BUF_DST16

  ; Set up page-aligned end pointer and Y offset
  ; BUF_PTR16 points to (end-1), page-aligned. Y = low byte of (end-1).
  SEC
  LDA BUF_PTR16
  SBC #1
  TAY                      ; Y = low byte of last source byte
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_PTR16 + 1
  LDA #0
  STA BUF_PTR16            ; BUF_PTR16 = page-aligned base

  ; BUF_DST16 = BUF_PTR16 + offset (so (BUF_DST16),Y gives correct dest)
  CLC
  ADC16 BUF_PTR16, BUF_DST16, BUF_DST16

  ; Check if source start is on the same page
  LDA BUF_PTR16 + 1
  CMP BUF_SRC16 + 1
  BNE .full_page

  ; Same page: copy Y down to low byte of BUF_SRC16
.last_page:
  LDA (BUF_PTR16),Y
  STA (BUF_DST16),Y
  CPY BUF_SRC16
  BEQ .done
  DEY
  JMP .last_page

.full_page:
  ; Copy from Y down to 0 on this page
  LDA (BUF_PTR16),Y
  STA (BUF_DST16),Y
  DEY
  CPY #$FF
  BNE .full_page

  ; Move to previous page
  DEC BUF_PTR16 + 1
  DEC BUF_DST16 + 1
  LDY #$FF

  ; Check if this is the page containing the source start
  LDA BUF_PTR16 + 1
  CMP BUF_SRC16 + 1
  BNE .full_page

  JMP .last_page

.done:
  RTS

; Delete BUF_DELTA characters starting at BUF_PTR16
; Input: BUF_PTR16 = position, BUF_DELTA = count
; Shifts all following bytes left by BUF_DELTA, updates BUF_END16
buf_delete_chars:
  JMP buf_shift_left

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
  BNE .not_empty
  LDA BUF_END16 + 1
  CMP #>TEXT_BUF
  BNE .not_empty
  LDY #0
  LDA #'\n'
  STA (BUF_END16),Y
  INC16 BUF_END16
.not_empty:

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
  ADC16 BUF_PTR16, BUF_LEN16, BUF_SRC16

  ; Check if nothing to move (source >= BUF_END16)
  LDA BUF_SRC16 + 1
  CMP BUF_END16 + 1
  BCC .need_shift
  BNE .shift_done
  LDA BUF_SRC16
  CMP BUF_END16
  BCS .shift_done
.need_shift:

  ; Set up mem_copy_down parameters:
  ;   BUF_SRC16 = source start (already set above)
  ;   BUF_DST16 = destination (delete point = original BUF_PTR16)
  ;   BUF_PTR16 = source end (BUF_END16)
  CP16 BUF_PTR16, BUF_DST16
  CP16 BUF_END16, BUF_PTR16
  JSR mem_copy_down

.shift_done:
  ; Update buffer end: subtract BUF_LEN16
  SEC
  SBC16 BUF_END16, BUF_LEN16, BUF_END16

  RTS

; Forward copy (safe when dst <= src or non-overlapping)
; Input: BUF_SRC16 = source start, BUF_PTR16 = source end (exclusive),
;        BUF_DST16 = destination start
; Preserves BUF_PTR16. Clobbers A, Y, BUF_SRC16, BUF_DST16
mem_copy_down:
  ; Check empty case (SRC >= END)
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BCC .not_empty
  BNE .done
  LDA BUF_SRC16
  CMP BUF_PTR16
  BCS .done
.not_empty:

  ; Set up page-aligned source and Y offset
  ; Y = low byte of BUF_SRC16, BUF_SRC16 = page base
  ; Adjust BUF_DST16 so (BUF_DST16),Y gives correct dest address:
  ;   BUF_DST16 = BUF_DST16 - SRC_low_byte
  LDA BUF_SRC16
  TAY                      ; Y = source low byte offset
  SEC
  LDA BUF_DST16
  SBC BUF_SRC16            ; Subtract source low byte only
  STA BUF_DST16
  BCS .no_borrow
  DEC BUF_DST16 + 1
.no_borrow:
  LDA #0
  STA BUF_SRC16            ; BUF_SRC16 = page-aligned base

  ; Check if end is on the same page as start
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .full_page

  ; Same page: copy Y up to (end low - 1)
.last_page:
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  CPY BUF_PTR16
  BNE .last_page
  JMP .done

.full_page:
  ; Copy from Y up through $FF on this page
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  BNE .full_page

  ; Move to next page
  INC BUF_SRC16 + 1
  INC BUF_DST16 + 1
  LDY #0

  ; Check if this is the last page
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .full_page

  ; Check if end low byte is 0 (end is at page boundary)
  LDA BUF_PTR16
  BEQ .done

  JMP .last_page

.done:
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
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_LEN16

  ; Subtract 1 (we start from line+1, not line)
  LDA BUF_LEN16
  BNE .no_borrow
  DEC BUF_LEN16 + 1
.no_borrow:
  DEC BUF_LEN16

  ; If count <= 0, nothing to adjust
  LDA BUF_LEN16 + 1
  BMI .done
  ORA BUF_LEN16
  BEQ .done

  ; Calculate LINE_TBL entry for (FILE_LINE16 + 1)
  ; Entry address = LINE_TBL + (FILE_LINE16 + 1) * 2
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  ASL16 BUF_PTR16
  CLC
  ADCI16 BUF_PTR16, LINE_TBL, BUF_PTR16

.loop:
  ; Increment the 16-bit line pointer at (BUF_PTR16)
  LDY #0
  CLC
  LDA (BUF_PTR16),Y
  ADC BUF_DELTA
  STA (BUF_PTR16),Y
  BCC .no_carry
  INY
  LDA (BUF_PTR16),Y
  ADC #0
  STA (BUF_PTR16),Y
.no_carry:

  ; Advance to next LINE_TBL entry (+2 bytes)
  CLC
  ADCI16 BUF_PTR16, $0002, BUF_PTR16

  ; Decrement count
  LDA BUF_LEN16
  BNE .no_borrow2
  DEC BUF_LEN16 + 1
.no_borrow2:
  DEC BUF_LEN16

  ; Check if count reached 0
  TST16 BUF_LEN16
  BNE .loop

.done:
  RTS

; Decrement line pointers after current line by 1
; Used after deleting a non-newline character (no lines added/removed)
; Input: FILE_LINE16 = current line number
; Clobbers: A, Y
buf_adjust_lines_dec:
  ; Calculate number of entries to adjust: LINE_COUNT16 - FILE_LINE16 - 1
  SEC
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_LEN16

  ; Subtract 1
  LDA BUF_LEN16
  BNE .no_borrow
  DEC BUF_LEN16 + 1
.no_borrow:
  DEC BUF_LEN16

  ; If count <= 0, nothing to adjust
  LDA BUF_LEN16 + 1
  BMI .done
  ORA BUF_LEN16
  BEQ .done

  ; Calculate LINE_TBL entry for (FILE_LINE16 + 1)
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  ASL16 BUF_PTR16
  CLC
  ADCI16 BUF_PTR16, LINE_TBL, BUF_PTR16

.loop:
  ; Decrement the 16-bit line pointer at (BUF_PTR16)
  LDY #0
  SEC
  LDA (BUF_PTR16),Y
  SBC BUF_DELTA
  STA (BUF_PTR16),Y
  BCS .no_borrow2
  INY
  LDA (BUF_PTR16),Y
  SBC #0
  STA (BUF_PTR16),Y
.no_borrow2:

  ; Advance to next LINE_TBL entry (+2 bytes)
  CLC
  ADCI16 BUF_PTR16, $0002, BUF_PTR16

  ; Decrement count
  LDA BUF_LEN16
  BNE .no_borrow3
  DEC BUF_LEN16 + 1
.no_borrow3:
  DEC BUF_LEN16

  ; Check if count reached 0
  TST16 BUF_LEN16
  BNE .loop

.done:
  RTS

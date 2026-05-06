; Requires:
;   SOURCE_STACK     - 1 past the highest address from which the stack grows down (asm.asm)
;   SS_NAME    - filename buffer (asm.asm alias to TOKEN)
;   SS_ERR_NO_FILE - error handler for read_char when no file is open (errors.asm)
;   SS_POP_MEMORY_HOOK - optional hook for memory-source cleanup (asm.asm alias)
;   err_file_not_found - error handler for when open returns 0 (errors.asm)
;   open, close, read - file I/O functions (environment.asm)

; The source stack grows downwards. Unified frame format (from low to high address):
;
;   name\0         - Source name (null-terminated)
;   curr_type      - Type of THIS source: 0=file, 1=memory
;   prev_type      - Type we're RETURNING to: 0=file, 1=memory
;   prev_line_L    - Line number in parent (low byte)
;   prev_line_H    - Line number in parent (high byte)
;   <prev_data>    - Depends on prev_type:
;                    If prev_type=0 (file):   prev_handle (1 byte)
;                    If prev_type=1 (memory): prev_ptr_L, prev_ptr_H (2 bytes, zero-terminated)
;
; Frame sizes: name_len + 1 (null) + 1 (curr) + 1 (prev) + 2 (line) + prev_data
;   = name_len + 6 if returning to file
;   = name_len + 7 if returning to memory

  .zeropage

SS_CURR_CHAR:   .byte       ; The last character read
SS_CURR_FILE:   .byte       ; The current file handle
SS_CURR_LINE16: .word       ; The current line number
SS_P16:         .word       ; Pointer to the current location in the source stack
SS_TEMP16:      .word       ; Temporary location for use in calculations

; Memory source support (zero-terminated buffers)
SS_SRC_TYPE:    .byte       ; Source type: 0=file, 1=memory
SS_MEM_PTR16:   .word       ; Current read position in memory

  .code

SS_SRC_TYPE_FILE   = 0
SS_SRC_TYPE_MEMORY = 1


source_stack_init:
  SET16 SOURCE_STACK, SS_P16
  LDA #SS_SRC_TYPE_FILE
  STA SS_SRC_TYPE
  STA SS_CURR_FILE
  RTS


; On exit Z is set if source stack empty, clear otherwise
source_stack_empty:
  CMPI16 SS_P16, SOURCE_STACK
  RTS


; Internal: Build a stack frame for a new source
; On entry: A = curr_type (0=file, 1=memory)
;           SS_NAME contains the source name
; On exit: Frame built with name, curr_type, prev_type, prev_line, prev_data
;          SS_CURR_LINE16 reset to 0
;          A, X, Y clobbered
push_source_frame:
  PHA                   ; Save curr_type for later
  ; Calculate name length
  LDY #$FF
.len_loop:
  INY
  LDA SS_NAME,Y
  BNE .len_loop
  ; Y = name length (without null)
  ; Calculate frame size: name_len + 1 (null) + 1 (curr) + 1 (prev) + 2 (line) + prev_data
  ; prev_data is 1 byte if prev_type=0 (file), 2 bytes if prev_type=1 (memory ptr only)
  LDA SS_SRC_TYPE
  CMP #SS_SRC_TYPE_FILE
  BNE .memory
  ; File
  TYA
  CLC
  ADC #5 + 1            ; name + null + curr_type + prev_type + line + handle
  BNE .size_done        ; Always taken
.memory
  TYA
  CLC
  ADC #5 + 2            ; name + null + curr_type + prev_type + line + memory ptr
.size_done:
  STA SS_TEMP16
  ; Decrease stack pointer by frame size
  SEC
  LDA SS_P16
  SBC SS_TEMP16
  STA SS_TEMP16
  LDA SS_P16 + 1
  SBC #$00
  STA SS_TEMP16 + 1

  ; Check for collision with heap before committing
  CHECK_FOR_OUT_OF_MEMORY SS_TEMP16

  ; Commit new stack pointer
  CP16 SS_TEMP16, SS_P16
  ; Copy name to stack
  LDY #$FF
.copy_loop:
  INY
  LDA SS_NAME,Y
  STA (SS_P16),Y
  BNE .copy_loop
  ; Store curr_type (saved on 6502 stack)
  INY
  PLA                   ; Get curr_type
  STA (SS_P16),Y
  ; Store prev_type
  INY
  LDA SS_SRC_TYPE
  STA (SS_P16),Y
  PHA                   ; Save prev_type for later
  ; Store prev_line
  INY
  LDA SS_CURR_LINE16
  STA (SS_P16),Y
  INY
  LDA SS_CURR_LINE16 + 1
  STA (SS_P16),Y
  ; Store prev_data based on prev_type
  PLA                   ; Restore prev_type
  BNE .save_memory_state
  ; prev_type=0: save file handle
  INY
  LDA SS_CURR_FILE
  STA (SS_P16),Y
  JMP .reset_line
.save_memory_state:
  ; prev_type=1: save memory pointer (zero-terminated, no end needed)
  INY
  LDA SS_MEM_PTR16
  STA (SS_P16),Y
  INY
  LDA SS_MEM_PTR16 + 1
  STA (SS_P16),Y
.reset_line:
  ; Reset line number for new source
  LDA #$00
  STA_LH16 SS_CURR_LINE16
  RTS


; Push a file source onto the stack
; On entry: SS_NAME contains the file name to open
;           SS_CURR_LINE16 contains the current line number
;           SS_CURR_FILE contains the current file handle
; On exit: X is preserved, new file is open and ready to read
push_file_source:
  TXA
  PHA                   ; Save X
  ; Open file before pushing frame so error reports parent context
  LDA #<SS_NAME
  LDX #>SS_NAME
  JSR open
  CMP #0
  BNE .file_ok
  JMP err_file_not_found
.file_ok:
  PHA                   ; Save new file handle
  LDA #SS_SRC_TYPE_FILE
  JSR push_source_frame
  LDA #SS_SRC_TYPE_FILE
  STA SS_SRC_TYPE
  PLA
  STA SS_CURR_FILE      ; Set new file handle
  PLA
  TAX                   ; Restore X
  RTS


; Push a memory source onto the stack
; On entry: SS_NAME       = name for this memory source (e.g. macro name)
;           SS_MEM_PTR16  = parent's read position (saved into the new
;                           frame as prev_data when prev_type=memory).
;                           Do NOT preload this with the new buffer
;                           pointer -- that overwrites the value
;                           push_source_frame is about to copy into the
;                           parent's prev_data slot, which silently
;                           breaks memory-above-memory pop. The new
;                           buffer pointer must be installed by the
;                           caller AFTER this routine returns.
; On exit: X is preserved. SS_SRC_TYPE = memory. Caller must now
;          assign the new buffer pointer to SS_MEM_PTR16; reads will
;          then proceed from the new buffer.
push_memory_source:
  TXA
  PHA                   ; Save X
  LDA #SS_SRC_TYPE_MEMORY
  JSR push_source_frame ; Saves SS_MEM_PTR16 (still parent's) as prev_data
  LDA #SS_SRC_TYPE_MEMORY
  STA SS_SRC_TYPE
  PLA
  TAX                   ; Restore X
  RTS


; Unified pop function - handles both file and memory sources
; On exit: Previous state restored (SS_CURR_FILE or FS_MEM_PTR)
;          SS_SRC_TYPE restored to prev_type
;          SS_CURR_LINE16 restored to prev_line
pop_source:
  ; Skip past name to find null terminator
  LDY #$FF
.skip_name:
  INY
  LDA (SS_P16),Y
  BNE .skip_name
  ; Y points at null, curr_type is at Y+1
  INY
  LDA (SS_P16),Y
  BEQ .was_file_source
  ; curr_type=1: was memory source - pop label scope if hook defined
  .ifdef SS_POP_MEMORY_HOOK
  TYA
  PHA                   ; Save Y (frame offset) before hook
  JSR SS_POP_MEMORY_HOOK
  PLA
  TAY                   ; Restore Y
  .endif
  JMP .restore_prev
.was_file_source:
  ; curr_type=0: close the current file (if open)
  LDA SS_CURR_FILE
  BEQ .restore_prev     ; Handle 0 = no file to close
  JSR close
.restore_prev:
  ; Read prev_type
  INY
  LDA (SS_P16),Y
  STA SS_SRC_TYPE       ; Restore source type
  PHA                   ; Save for later
  ; Read prev_line
  INY
  LDA (SS_P16),Y
  STA SS_CURR_LINE16
  INY
  LDA (SS_P16),Y
  STA SS_CURR_LINE16 + 1
  ; Restore prev_data based on prev_type
  PLA
  BNE .restore_memory
  ; prev_type=0: restore file handle
  INY
  LDA (SS_P16),Y
  STA SS_CURR_FILE
  JMP .adjust_stack
.restore_memory:
  ; prev_type=1: restore memory pointer (zero-terminated, no end needed)
  INY
  LDA (SS_P16),Y
  STA SS_MEM_PTR16
  INY
  LDA (SS_P16),Y
  STA SS_MEM_PTR16 + 1
.adjust_stack:
  ; Y points to last byte read, add Y+1 to stack pointer
  TYA
  SEC                   ; +1
  ADCA16 SS_P16, SS_P16
  RTS

; Read character from current source (file or memory)
; On exit: A = character (also stored in SS_CURR_CHAR)
;          C = 0 if char read, C = 1 if all sources exhausted
;          X is preserved
;          Y is not preserved
source_stack_read_char:
  LDA SS_SRC_TYPE
  BNE .read_memory
  ; Type 0 = file source
  LDA SS_CURR_FILE
  .ifdef enable_debug 
  BEQ .no_source
  .endif
  JSR read
  BCS .source_exhausted
  ; Got character
  STA SS_CURR_CHAR
  ; Carry is clear
  RTS
.read_memory:
  ; Type 1 = memory source (zero-terminated)
  ; Read byte from memory pointer
  LDY #0
  LDA (SS_MEM_PTR16),Y
  BEQ .source_exhausted     ; $00 = end of memory source
  ; Increment memory pointer
  INC16 SS_MEM_PTR16     ; Preserves A
  STA SS_CURR_CHAR
  CLC
  RTS
.source_exhausted:
  ; Source exhausted - pop and try previous source
  JSR pop_source
  ; Check if stack is empty
  JSR source_stack_empty
  ; Continue reading from previous source
  BNE source_stack_read_char
.all_done:
  SEC
  RTS
  .ifdef enable_debug
.no_source:
  JMP SS_ERR_NO_FILE
  .endif

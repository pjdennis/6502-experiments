; Requires:
;   SOURCE_STACK       - 1 past the highest address; stack grows down (asm.asm)
;   SS_NAME            - buffer holding the source's name; alias to TOKEN
;                        (asm.asm / source_stack_test.asm)
;   SS_ERR_NO_FILE     - error handler for read_char when no source is
;                        open (errors.asm; only referenced under
;                        enable_debug)
;   SS_POP_MEMORY_HOOK - optional hook invoked when a memory source is
;                        popped, used by the assembler to restore label
;                        scope (asm.asm alias to pop_label_scope; left
;                        undefined by the test program)
;   err_file_not_found - error handler for when open returns 0 (errors.asm)
;   open, close, read  - source I/O syscalls (environment.asm)

; The source stack grows downwards. Each frame is laid out from low to
; high address (low address is closer to the top of the stack):
;
;   name\0         - Source name (null-terminated)
;   curr_type      - Type of THIS source: 0=file, 1=memory
;   prev_type      - Type we're RETURNING to: 0=file, 1=memory
;   prev_line_L    - Line number in parent (low byte)
;   prev_line_H    - Line number in parent (high byte)
;   <prev_data>    - Parent state to restore on pop. Size depends on
;                    prev_type:
;                      prev_type=0 (file):   prev_handle (1 byte)
;                      prev_type=1 (memory): prev_ptr_L, prev_ptr_H
;                                            (2 bytes; the parent's
;                                            SS_MEM_PTR16 at the moment
;                                            of this push)
;
; Frame size: name_len + 1 (null) + 1 (curr) + 1 (prev) + 2 (line) + prev_data
;   = name_len + 6 if returning to file
;   = name_len + 7 if returning to memory
;
; Future Phase 3 work appends additional payload bytes after prev_data
; for memory sources that need activation state (label scope, macro
; entry, etc.); the source stack itself never reads those payload
; bytes -- they are written and consumed by the SS_POP_MEMORY_HOOK
; owner.

  .zeropage

SS_CURR_CHAR:    .byte       ; The last character read
SS_CURR_FILE:    .byte       ; The current file handle
SS_CURR_LINE16:  .word       ; The current line number
SS_P16:          .word       ; Pointer to the current location in the source stack
SS_TEMP16:       .word       ; Temporary location for use in calculations
SS_PENDING_FILE: .byte       ; In-flight file handle: opened by push_file_source
                             ; but not yet committed to a source-stack frame.
                             ; Non-zero means the error path must close it
                             ; (push_source_frame's OOM jump would otherwise
                             ; orphan the handle, since traceback only sees
                             ; handles that already live in a frame). Zero
                             ; means there's no pending handle.

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
  ; SS_SRC_TYPE_FILE happens to be 0, which is also "no pending file"
  STA SS_PENDING_FILE
  RTS


; On exit Z is set if source stack empty, clear otherwise
source_stack_empty:
  CMPI16 SS_P16, SOURCE_STACK
  RTS


; INTERNAL helper -- callers should use push_file_source or
; push_memory_source rather than calling this directly. Those two
; routines own the calling-convention details (saving X, opening the
; file, ordering of SS_MEM_PTR16 updates, etc.).
;
; Builds a stack frame for a new source. The size of the frame depends
; on the parent's source type (read from SS_SRC_TYPE), since prev_data
; is 1 byte for file parents and 2 bytes for memory parents.
;
; On entry: A          = curr_type (0=file, 1=memory) for the new frame
;           SS_NAME    = source name (null-terminated)
;           SS_SRC_TYPE = parent's source type (becomes prev_type)
;           SS_CURR_FILE / SS_MEM_PTR16 = parent's read state, captured
;                        into prev_data. SS_MEM_PTR16 must still hold
;                        the parent's value when prev_type=memory.
; On exit:  Frame written with name, curr_type, prev_type, prev_line,
;           prev_data; SS_P16 advanced past it.
;           SS_CURR_LINE16 reset to 0.
;           A, X, Y clobbered.
push_source_frame:
  PHA                   ; Save curr_type for later
  ; Calculate name length
  LDY #$FF
.len_loop:
  INY
  LDA SS_NAME,Y
  BNE .len_loop
  ; Y = name length (without null)
  ; Calculate frame size:
  ;   1 (frame_size) + name_len + 1 (null) + 1 (curr) + 1 (prev) + 2 (line) + prev_data
  ; prev_data is 1 byte if prev_type=0 (file), 2 bytes if prev_type=1 (memory ptr).
  LDA SS_SRC_TYPE
  CMP #SS_SRC_TYPE_FILE
  BNE .memory
  ; File parent
  TYA
  CLC
  ADC #5 + 1 + 1        ; +5 fixed fields + 1 handle + 1 frame_size byte
  BNE .size_done        ; Always taken
.memory
  ; Memory parent
  TYA
  CLC
  ADC #5 + 2 + 1        ; +5 fixed fields + 2 mem ptr + 1 frame_size byte
.size_done:
  PHA                   ; Save frame_size on 6502 stack (under curr_type)
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
  ; Write frame_size at offset 0
  LDY #0
  PLA                   ; Get frame_size
  STA (SS_P16),Y
  ; Copy name to offsets 1..name_len in the frame.
  ; Y indexes the frame (starts at 0, INY first); X indexes SS_NAME (starts at $FF, INX first).
  LDX #$FF
.copy_loop:
  INX
  INY
  LDA SS_NAME,X
  STA (SS_P16),Y
  BNE .copy_loop
  ; X = name_len, Y = name_len + 1 (offset of null in frame)
  ; Store curr_type at next offset
  INY
  PLA                   ; Get curr_type (saved at routine entry)
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
  ; Park the new handle in SS_PENDING_FILE rather than the 6502 stack so
  ; that an OOM jump out of push_source_frame doesn't orphan it -- the
  ; error path closes any non-zero SS_PENDING_FILE before exiting.
  STA SS_PENDING_FILE
  LDA #SS_SRC_TYPE_FILE
  JSR push_source_frame
  LDA #SS_SRC_TYPE_FILE
  STA SS_SRC_TYPE
  LDA SS_PENDING_FILE
  STA SS_CURR_FILE      ; Install new file handle
  LDA #$00
  STA SS_PENDING_FILE   ; Clear pending: handle is now owned by the frame
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


; Unified pop function - handles both file and memory sources.
; For file sources, closes the current file handle. For memory sources,
; calls SS_POP_MEMORY_HOOK if defined (the assembler hooks scope
; restore here; the test program leaves it undefined).
; On exit: Previous state restored (SS_CURR_FILE or SS_MEM_PTR16)
;          SS_SRC_TYPE restored to prev_type
;          SS_CURR_LINE16 restored to prev_line
pop_source:
  ; Skip the frame_size byte at offset 0, then scan the name (which
  ; starts at offset 1) for its null terminator.
  LDY #0
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

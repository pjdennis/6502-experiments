; Requires:
;   SOURCE_STACK       - 1 past the highest address; stack grows down (asm.asm)
;   SS_NAME            - buffer holding the source's name; alias to TOKEN
;                        (asm.asm / source_stack_test.asm)
;   SS_ERR_NO_FILE     - error handler for read_char when no source is
;                        open (errors.asm; only referenced under
;                        enable_debug)
;   err_file_not_found - error handler for when open returns 0 (errors.asm)
;   open, close, read  - source I/O syscalls (environment.asm)

; The source stack grows downwards. Each frame is laid out from low to
; high address (low address is closer to the top of the stack):
;
;   frame_size     - Total frame size in bytes (1-byte; offset 0)
;   curr_type      - Type of THIS source: 0=file, 1=memory (offset 1)
;   prev_type      - Type we're RETURNING to: 0=file, 1=memory (offset 2)
;   prev_line_L    - Line number in parent (low byte, offset 3)
;   prev_line_H    - Line number in parent (high byte, offset 4)
;   prev_data      - Parent state to restore on pop. Fixed 2-byte slot
;                    at offsets 5..6, regardless of prev_type:
;                      prev_type=0 (file):   offset 5 = prev_handle;
;                                            offset 6 unused
;                      prev_type=1 (memory): offsets 5..6 = prev_ptr_L,
;                                            prev_ptr_H (parent's
;                                            SS_MEM_PTR16 at the moment
;                                            of this push)
;   name\0         - Source name (null-terminated; starts at offset 7,
;                    variable length up to 127+null = 128 bytes)
;   <payload>      - Optional bytes reserved for memory frames via
;                    push_memory_source_reserve_payload (caller writes
;                    them after the push; the source stack itself never
;                    inspects payload contents). Used by expand_macro
;                    to carry per-invocation activation state; consumed
;                    by the memory-pop handler installed via
;                    ss_install_memory_pop.
;
; Frame size: name_len + 8 + payload_size (1 frame_size + 1 curr_type
;   + 1 prev_type + 2 prev_line + 2 prev_data + name + 1 null + payload).
;   No parent-type branch: prev_data is always 2 bytes.
;
; Putting curr_type / prev_type / prev_line / prev_data at fixed
; offsets 1..6 makes pop_source O(1) end-to-end -- the pre-reorg
; version paid an O(name_len) skip-name walk to find prev_data on
; every pop. With prev_data at fixed offset 5, that walk is gone.
; File parents waste 1 byte at offset 6 in exchange for a constant
; frame-size formula and a fixed name offset that consumers (e.g.
; SHOW_FRAME_NAME) can use without scanning.

  .zeropage

SS_CURR_CHAR:    .byte       ; The last character read
SS_CURR_FILE:    .byte       ; The current file handle
SS_CURR_LINE16:  .word       ; The current line number
SS_P16:          .word       ; Pointer to the current location in the source stack
SS_TEMP16:       .word       ; Temporary location for use in calculations
SS_PAYLOAD_SIZE: .byte       ; Number of payload bytes to reserve for the
                             ; next push_memory_source_reserve_payload
                             ; call. Always 0 outside of that path.

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
  ; SS_SRC_TYPE_FILE is 0; reuse A for SS_PAYLOAD_SIZE init.
  STA SS_PAYLOAD_SIZE
  RTS


; Verify there's room on the source stack for the next frame. Reads the
; same inputs push_source_frame uses (SS_NAME, SS_SRC_TYPE) so callers
; can pre-check before any irreversible side effects (e.g. opening a
; file). Side-effect free on success; jumps to err_out_of_memory on
; failure.
;
; On exit (success): SS_TEMP16 = proposed new SS_P16. push_source_frame
;                    consumes this directly (it's the only place the
;                    frame size is computed), so a successful return
;                    here must be followed by push_source_frame before
;                    any other routine clobbers SS_TEMP16.
;                    A, X, Y clobbered.
check_source_frame_room:
  ; Compute name length
  LDY #$FF
.len_loop:
  INY
  LDA SS_NAME,Y
  BNE .len_loop
  ; Frame size = name_len + 8 + payload_size. The 8 covers the fixed
  ; header (frame_size, curr_type, prev_type, prev_line lo/hi,
  ; prev_data lo/hi) plus the name's null terminator. prev_data is a
  ; fixed 2-byte slot regardless of parent type, so no SS_SRC_TYPE
  ; branch is needed here.
  TYA
  CLC
  ADC #$08
  CLC
  ADC SS_PAYLOAD_SIZE
  STA SS_TEMP16         ; total size in low byte; high byte is scratch below
  ; Compute proposed new SS_P16 = SS_P16 - size
  SEC
  LDA SS_P16
  SBC SS_TEMP16
  STA SS_TEMP16
  LDA SS_P16 + 1
  SBC #$00
  STA SS_TEMP16 + 1
  CHECK_FOR_OUT_OF_MEMORY SS_TEMP16
  RTS


; Generic stack mechanic: commit a pre-checked frame allocation.
;
; Reads SS_TEMP16 (the proposed new SS_P16, set by
; check_source_frame_room), commits it, recovers the frame size as the
; one-byte difference (frames are always < 256 bytes), and writes that
; size at offset 0 of the new frame. Layout-agnostic past offset 0.
;
; PRECONDITION: caller has just called check_source_frame_room and the
; OOM check passed. ss_alloc_frame has no failure path.
;
; On exit:  SS_P16 = pre-call SS_TEMP16; (SS_P16),0 = frame_size;
;           Y = 0; A and X clobbered.
ss_alloc_frame:
  ; Recover size as low byte of (SS_P16 - SS_TEMP16).
  LDA SS_P16
  SEC
  SBC SS_TEMP16
  PHA                       ; Save size for the offset-0 write
  ; Commit new stack pointer
  CP16 SS_TEMP16, SS_P16
  ; Write frame_size at offset 0
  LDY #0
  PLA
  STA (SS_P16),Y
  RTS


; Generic stack mechanic: free the top frame.
;
; Reads the frame_size byte at offset 0 of the current top frame and
; advances SS_P16 past it, exposing the previous frame. Layout-agnostic.
;
; On exit:  SS_P16 advanced upward by the freed frame's size;
;           A = freed size; Y = 0; X preserved.
ss_free_frame:
  LDY #0
  LDA (SS_P16),Y
  CLC
  ADCA16 SS_P16, SS_P16
  RTS


; Per-curr_type pop handlers. pop_source dispatches to one of these
; based on curr_type, before prev_data restoration. The dispatch
; preserves both X and Y around the JSR; handlers may freely clobber
; them. The memory entry can be patched at runtime via
; ss_install_memory_pop -- the assembler installs
; pop_label_scope_from_frame, the test program leaves the no-op default.
ss_pop_file:
  ; curr_type=0: close the current file handle if open.
  LDA SS_CURR_FILE
  BEQ .nothing_to_close
  JMP close             ; tail call
.nothing_to_close:
  RTS

; Default memory pop handler: no-op. The host program installs its own
; via ss_install_memory_pop if memory frames carry state that needs
; restoring (the assembler installs pop_label_scope_from_frame; the
; test program leaves the default in place).
ss_pop_memory_noop:
  RTS

; Per-curr_type pop dispatch table (lo/hi split for ASL-free indexing).
; The memory entry can be patched at runtime via ss_install_memory_pop.
ss_on_pop_table_lo:
  .byte <ss_pop_file
  .byte <ss_pop_memory_noop
ss_on_pop_table_hi:
  .byte >ss_pop_file
  .byte >ss_pop_memory_noop

; Install a custom memory-pop handler. Overwrites the memory entry of
; ss_on_pop_table_{lo,hi} so subsequent pop_source calls dispatch to
; this handler when curr_type=memory.
;
; On entry: A = handler addr low byte
;           X = handler addr high byte
; On exit:  Y/A clobbered; X preserved (the table is patched in place).
ss_install_memory_pop:
  STA ss_on_pop_table_lo + 1
  TXA
  STA ss_on_pop_table_hi + 1
  RTS

; Indirect-call thunk: caller stores target address in SS_TEMP16, then
; JSRs here. The target's RTS returns to the original caller. Used by
; pop_source's curr_type dispatch (the only remaining call site after
; ss_walk_frames moved into the test program).
ss_invoke:
  JMP (SS_TEMP16)


; On exit Z is set if source stack empty, clear otherwise
source_stack_empty:
  CMPI16 SS_P16, SOURCE_STACK
  RTS


; INTERNAL helper -- callers should use push_file_source or
; push_memory_source rather than calling this directly. Those two
; routines own the calling-convention details (saving X, opening the
; file, ordering of SS_MEM_PTR16 updates, etc.).
;
; Builds a stack frame for a new source. Frame size is name_len + 8 +
; payload (fixed-size prev_data slot regardless of parent type).
;
; PRECONDITION: caller has called check_source_frame_room, which leaves
; the proposed new SS_P16 in SS_TEMP16 and verified the OOM check. That
; result is consumed here; together the pair calculates the frame size
; exactly once. Because the OOM check has already passed, this routine
; has no failure path -- it never jumps to err_out_of_memory -- so it's
; safe to call after acquiring resources (e.g. a freshly-opened file
; handle) that would otherwise need cleanup on OOM.
;
; On entry: A          = curr_type (0=file, 1=memory) for the new frame
;           SS_TEMP16  = proposed new SS_P16 (from check_source_frame_room)
;           SS_NAME    = source name (null-terminated)
;           SS_SRC_TYPE = parent's source type (becomes prev_type)
;           SS_CURR_FILE / SS_MEM_PTR16 = parent's read state, captured
;                        into prev_data. SS_MEM_PTR16 must still hold
;                        the parent's value when prev_type=memory.
; On exit:  Frame written with curr_type, prev_type, prev_line,
;           prev_data, name; SS_P16 advanced past it.
;           SS_CURR_LINE16 reset to 0.
;           A, X, Y clobbered.
push_source_frame:
  PHA                   ; Save curr_type for later
  ; Allocate the frame and write its size byte at offset 0. Pure stack
  ; mechanics live in ss_alloc_frame; everything below is layout.
  JSR ss_alloc_frame    ; SS_P16 advanced; (SS_P16),0 = frame_size; Y = 0
  ; Write the fixed-offset header (offsets 1..6). All readers index
  ; these by constant offset, no name scan involved.
  INY                   ; Y = 1 (curr_type)
  PLA                   ; Get curr_type (saved at routine entry)
  STA (SS_P16),Y
  INY                   ; Y = 2 (prev_type)
  LDA SS_SRC_TYPE
  STA (SS_P16),Y
  PHA                   ; Save prev_type for the prev_data branch below
  INY                   ; Y = 3 (prev_line low)
  LDA SS_CURR_LINE16
  STA (SS_P16),Y
  INY                   ; Y = 4 (prev_line high)
  LDA SS_CURR_LINE16 + 1
  STA (SS_P16),Y
  ; prev_data at fixed offsets 5..6. prev_type selects which 1 or 2
  ; bytes are meaningful; offset 6 is unused (left undefined) for
  ; file parents. Both branches leave Y = 6 so .copy_name's first
  ; INY lands on offset 7.
  PLA                   ; Restore prev_type
  BNE .save_memory_state
  ; prev_type=0 (file): handle at offset 5; offset 6 unused.
  INY                   ; Y = 5
  LDA SS_CURR_FILE
  STA (SS_P16),Y
  INY                   ; Y = 6 (unused byte; not written)
  JMP .copy_name
.save_memory_state:
  ; prev_type=1 (memory): SS_MEM_PTR16 lo at offset 5, hi at offset 6.
  INY                   ; Y = 5
  LDA SS_MEM_PTR16
  STA (SS_P16),Y
  INY                   ; Y = 6
  LDA SS_MEM_PTR16 + 1
  STA (SS_P16),Y
.copy_name:
  ; Copy name + null at offsets 7..(7+name_len). Y advances byte-by-byte;
  ; X indexes SS_NAME (starts at $FF, INX first); the loop terminates on
  ; the source's null terminator (which gets copied too).
  LDX #$FF
.copy_loop:
  INX
  INY
  LDA SS_NAME,X
  STA (SS_P16),Y
  BNE .copy_loop
  ; SS_PAYLOAD_SIZE bytes of payload trail the name; the frame_size
  ; byte at offset 0 already accounts for them. The bytes are reserved
  ; but not initialized here -- push_memory_source_reserve_payload's
  ; caller pre-writes them at (SS_P16 - SS_PAYLOAD_SIZE) before the push,
  ; so they are already in place by the time SS_P16 advances over them.
  ; Reset line number for new source.
  LDA #$00
  STA_LH16 SS_CURR_LINE16
  RTS


; Push a file source onto the stack
; On entry: SS_NAME contains the file name to open
;           SS_CURR_LINE16 contains the current line number
;           SS_CURR_FILE contains the current file handle
; On exit: X is preserved, new file is open and ready to read
;
; Order of operations is: pre-check OOM, then open the file, then push
; the frame. Each error exits with no resources to clean up: OOM happens
; before open so no file is leaked; file-not-found happens before push
; so no orphan frame is left behind.
push_file_source:
  TXA
  PHA                   ; Save X
  ; Pre-check: confirm the new frame will fit before we open the file,
  ; so an OOM here can't leak a freshly-opened handle.
  JSR check_source_frame_room
  ; Open file
  LDA #<SS_NAME
  LDX #>SS_NAME
  JSR open
  CMP #0
  BNE .file_ok
  JMP err_file_not_found
.file_ok:
  PHA                   ; Stash new handle on the 6502 stack across the
                        ; push (push_source_frame can't fail now).
  LDA #SS_SRC_TYPE_FILE
  JSR push_source_frame
  LDA #SS_SRC_TYPE_FILE
  STA SS_SRC_TYPE
  PLA
  STA SS_CURR_FILE      ; Install new file handle
  PLA
  TAX                   ; Restore X
  RTS


; Push a memory source carrying a trailing payload region whose bytes
; are RESERVED only -- the source stack does not copy any data into
; them. The caller is expected to have written the payload contents
; into (SS_P16 - SS_PAYLOAD_SIZE) BEFORE calling, since the push
; advances SS_P16 over those bytes and they become the new frame's
; payload region in place. expand_macro uses this to parse argument
; expressions one at a time and write each parsed slot straight into
; the soon-to-be-frame, avoiding a staging buffer entirely.
;
; On entry: SS_NAME       = name for this memory source
;           SS_MEM_PTR16  = parent's read position. Saved into the new
;                           frame as prev_data when prev_type=memory.
;                           Do NOT preload this with the new buffer
;                           pointer -- that overwrites the value
;                           push_source_frame is about to copy into the
;                           parent's prev_data slot, which silently
;                           breaks memory-above-memory pop. The new
;                           buffer pointer must be installed by the
;                           caller AFTER this routine returns.
;           A             = payload size (0..N) to reserve. 0 is fine
;                           too -- the test program calls this from
;                           setup_memory_source with A=0 to push a
;                           plain (payload-less) memory frame.
; On exit:  X preserved. SS_SRC_TYPE = MEMORY. SS_PAYLOAD_SIZE reset
;           to 0. Caller must assign the new buffer pointer to
;           SS_MEM_PTR16; reads will then proceed from the new buffer.
push_memory_source_reserve_payload:
  STA SS_PAYLOAD_SIZE
  TXA
  PHA
  JSR check_source_frame_room
  LDA #SS_SRC_TYPE_MEMORY
  JSR push_source_frame
  LDA #SS_SRC_TYPE_MEMORY
  STA SS_SRC_TYPE
  LDA #$00
  STA SS_PAYLOAD_SIZE
  PLA
  TAX
  RTS


; Unified pop function - handles both file and memory sources via
; ss_on_pop_table dispatch. For file sources, closes the current file
; handle. For memory sources, runs whatever handler the host installed
; via ss_install_memory_pop (the assembler installs
; pop_label_scope_from_frame; the test program leaves the default
; no-op).
; On exit: Previous state restored (SS_CURR_FILE or SS_MEM_PTR16)
;          SS_SRC_TYPE restored to prev_type
;          SS_CURR_LINE16 restored to prev_line
pop_source:
  ; All header fields (curr_type/prev_type/prev_line/prev_data) live at
  ; fixed offsets 1..6 -- no name scan anywhere on this path.
  LDY #1                ; curr_type offset
  ; Dispatch on curr_type via ss_on_pop_table_{lo,hi} (file=0, memory=1).
  ; Save X around the dispatch -- pop_source preserves X by external
  ; contract (read_char's X preservation flows through here).
  TXA
  PHA
  LDA (SS_P16),Y
  TAX
  LDA ss_on_pop_table_lo,X
  STA SS_TEMP16
  LDA ss_on_pop_table_hi,X
  STA SS_TEMP16+1
  ; Y must also survive the handler call (we still need it for the
  ; prev_type / prev_line / prev_data reads below).
  TYA
  PHA
  JSR ss_invoke
  PLA
  TAY
  PLA
  TAX
  ; Read prev_type at offset 2.
  INY
  LDA (SS_P16),Y
  STA SS_SRC_TYPE       ; Restore source type
  PHA                   ; Save for the prev_data branch below
  ; Read prev_line at offsets 3..4.
  INY
  LDA (SS_P16),Y
  STA SS_CURR_LINE16
  INY
  LDA (SS_P16),Y
  STA SS_CURR_LINE16 + 1
  ; prev_data at fixed offset 5 (and offset 6 for memory parents).
  INY                   ; Y = 5
  PLA
  BNE .restore_memory
  ; prev_type=0: restore file handle (offset 5; offset 6 unused).
  LDA (SS_P16),Y
  STA SS_CURR_FILE
  JMP ss_free_frame     ; Tail call: deallocate via offset-0 frame_size
.restore_memory:
  ; prev_type=1: restore memory pointer lo/hi at offsets 5..6.
  LDA (SS_P16),Y
  STA SS_MEM_PTR16
  INY
  LDA (SS_P16),Y
  STA SS_MEM_PTR16 + 1
  JMP ss_free_frame     ; Tail call: deallocate via offset-0 frame_size

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

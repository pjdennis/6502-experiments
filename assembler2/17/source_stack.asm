; Requires:
;   SOURCE_STACK       - 1 past the highest address; stack grows down (asm.asm)
;   SS_NAME            - buffer holding the source's name; alias to TOKEN
;                        (asm.asm / source_stack_test.asm)
;   SS_ERR_NO_FILE     - error handler for read_char when no source is
;                        open (errors.asm; only referenced under
;                        enable_debug)
;   TABP16             - host-provided 2-byte zero-page scratch pointer
;                        used by ss_walk_frames* to track the current
;                        frame during a walk (hash_table.asm in the
;                        assembler; locally defined in the test program)
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
;   name\0         - Source name (null-terminated; starts at offset 5,
;                    variable length up to 127+null = 128 bytes)
;   <prev_data>    - Parent state to restore on pop. Size depends on
;                    prev_type:
;                      prev_type=0 (file):   prev_handle (1 byte)
;                      prev_type=1 (memory): prev_ptr_L, prev_ptr_H
;                                            (2 bytes; the parent's
;                                            SS_MEM_PTR16 at the moment
;                                            of this push)
;   <payload>      - Optional caller-supplied bytes (memory frames only),
;                    sized via SS_PAYLOAD_SIZE at push time.
;
; Frame size: 5 (header) + name_len + 1 (null) + prev_data + payload
;   = name_len + 7 + payload_size if returning to file
;   = name_len + 8 + payload_size if returning to memory
;
; Putting curr_type / prev_type / prev_line at fixed offsets 1..4 makes
; the hot walks (ss_walk_frames_by_type, the pop_source dispatch) O(1)
; per frame for the curr_type read; pre-reorg they had to scan past the
; variable-length name first. prev_data still
; lives after the name, so pop_source's restore step still pays the
; strlen-scan cost -- but that's once per pop, not once per identifier
; lookup.
;
; Future Phase 3 work appends additional payload bytes after prev_data
; for memory sources that need activation state (label scope, macro
; entry, etc.); the source stack itself never reads those payload
; bytes -- they are written and consumed by the memory-pop handler
; installed via ss_install_memory_pop.

  .zeropage

SS_CURR_CHAR:    .byte       ; The last character read
SS_CURR_FILE:    .byte       ; The current file handle
SS_CURR_LINE16:  .word       ; The current line number
SS_P16:          .word       ; Pointer to the current location in the source stack
SS_TEMP16:       .word       ; Temporary location for use in calculations
SS_WALK_FILTER:  .byte       ; curr_type filter for ss_walk_frames_by_type
SS_PAYLOAD_SIZE: .byte       ; Number of payload bytes to append to next push
                             ; (0 outside push_*_with_payload calls)
SS_PAYLOAD16:    .word       ; Pointer to payload bytes when SS_PAYLOAD_SIZE > 0

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
  ; Compute frame size: name_len + 5 fixed + 1 frame_size + (1 file | 2 memory)
  LDA SS_SRC_TYPE
  CMP #SS_SRC_TYPE_FILE
  BNE .memory
  TYA
  CLC
  ADC #5 + 1 + 1
  BNE .size_done        ; Always taken (size > 0)
.memory:
  TYA
  CLC
  ADC #5 + 2 + 1
.size_done:
  ; Add caller-supplied payload size (0 for plain pushes; non-zero for
  ; push_*_with_payload). Frame_size still fits in one byte: callers
  ; are responsible for keeping name + standard fields + payload < 256.
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


; Walk source-stack frames newest-to-oldest, calling the callback once
; per frame. Generic stack mechanic; layout-agnostic past offset 0.
;
; On entry: A = callback address low byte
;           X = callback address high byte
; Per-callback state:
;   TABP16 = current frame address (frame_size byte at offset 0)
;   Y is free for the callback to clobber
; Callback contract:
;   - Must leave TABP16 unchanged on exit (PUSH16/POP16 if needed).
;   - Must NOT clobber SS_TEMP16 (walker holds the callback addr there).
; On exit:  TABP16 = SOURCE_STACK (one past the bottom frame).
;           A, X, Y, SS_TEMP16 clobbered.
ss_walk_frames:
  STA SS_TEMP16
  STX SS_TEMP16+1
  CP16 SS_P16, TABP16
.loop:
  CMPI16 TABP16, SOURCE_STACK
  BCS .done
  JSR ss_invoke           ; callback(TABP16)
  ; Advance TABP16 by frame_size at offset 0 (frames < 256 bytes)
  LDY #0
  LDA (TABP16),Y
  CLC
  ADCA16 TABP16, TABP16
  JMP .loop
.done:
  RTS


; Like ss_walk_frames, but only invokes the callback for frames whose
; curr_type matches the filter. Other frames are still walked past so
; the iteration covers the whole stack.
;
; On entry: A = callback addr low, X = callback addr high
;           Y = curr_type to match (0=file, 1=memory)
; Same callback contract as ss_walk_frames; SS_WALK_FILTER additionally
; clobbered.
ss_walk_frames_by_type:
  STA SS_TEMP16
  STX SS_TEMP16+1
  STY SS_WALK_FILTER
  CP16 SS_P16, TABP16
.loop:
  CMPI16 TABP16, SOURCE_STACK
  BCS .done
  ; curr_type lives at fixed offset 1 of the frame -- post-reorg this
  ; is a single (TABP16),Y read instead of an O(name_len) strlen scan.
  LDY #1
  LDA (TABP16),Y
  CMP SS_WALK_FILTER
  BNE .skip
  JSR ss_invoke
.skip:
  LDY #0
  LDA (TABP16),Y          ; frame_size
  CLC
  ADCA16 TABP16, TABP16
  JMP .loop
.done:
  RTS


; ss_top_memory_frame was deleted when MACRO_LOOKUP_FRAME16 took over
; resolve_identifier's "find the innermost macro frame" job. The pointer
; is saved into each macro frame's payload at push and restored on pop,
; so the active macro frame is now an O(1) lookup (zp word read) instead
; of a stack walk.


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
; both pop_source's curr_type dispatch and ss_walk_frames* below.
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
; Builds a stack frame for a new source. The size of the frame depends
; on the parent's source type (read from SS_SRC_TYPE), since prev_data
; is 1 byte for file parents and 2 bytes for memory parents.
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
; On exit:  Frame written with name, curr_type, prev_type, prev_line,
;           prev_data; SS_P16 advanced past it.
;           SS_CURR_LINE16 reset to 0.
;           A, X, Y clobbered.
push_source_frame:
  PHA                   ; Save curr_type for later
  ; Allocate the frame and write its size byte at offset 0. Pure stack
  ; mechanics live in ss_alloc_frame; everything below is layout.
  JSR ss_alloc_frame    ; SS_P16 advanced; (SS_P16),0 = frame_size; Y = 0
  ; Write the fixed-offset header so consumers can read curr_type /
  ; prev_type / prev_line at known offsets without scanning past the
  ; variable-length name.
  INY                   ; Y = 1 (curr_type offset)
  PLA                   ; Get curr_type (saved at routine entry)
  STA (SS_P16),Y
  INY                   ; Y = 2 (prev_type offset)
  LDA SS_SRC_TYPE
  STA (SS_P16),Y
  PHA                   ; Save prev_type for the prev_data branch below
  INY                   ; Y = 3 (prev_line low)
  LDA SS_CURR_LINE16
  STA (SS_P16),Y
  INY                   ; Y = 4 (prev_line high)
  LDA SS_CURR_LINE16 + 1
  STA (SS_P16),Y
  ; Copy name + null at offsets 5..(5+name_len). Y advances byte-by-byte;
  ; X indexes SS_NAME (starts at $FF, INX first); the loop terminates on
  ; the source's null terminator (which gets copied too).
  LDX #$FF
.copy_loop:
  INX
  INY
  LDA SS_NAME,X
  STA (SS_P16),Y
  BNE .copy_loop
  ; Y = offset of the null we just wrote in the frame.
  ; Store prev_data based on prev_type.
  PLA                   ; Restore prev_type
  BNE .save_memory_state
  ; prev_type=0: save file handle
  INY
  LDA SS_CURR_FILE
  STA (SS_P16),Y
  JMP .write_payload
.save_memory_state:
  ; prev_type=1: save memory pointer (zero-terminated, no end needed)
  INY
  LDA SS_MEM_PTR16
  STA (SS_P16),Y
  INY
  LDA SS_MEM_PTR16 + 1
  STA (SS_P16),Y
.write_payload:
  ; Append SS_PAYLOAD_SIZE bytes of payload from SS_PAYLOAD16 right
  ; after prev_data. The frame_size byte at offset 0 already accounts
  ; for these bytes (check_source_frame_room added SS_PAYLOAD_SIZE in).
  ; SS_PAYLOAD_SIZE is 0 for plain push_*_source paths, so this is a
  ; no-op outside push_*_with_payload.
  LDA SS_PAYLOAD_SIZE
  BEQ .reset_line
  ; Compute frame-payload-write pointer = SS_P16 + (Y+1), parked in
  ; SS_TEMP16 (which is free at this point -- ss_alloc_frame already
  ; consumed it). Then use Y=0..N-1 to copy payload bytes through
  ; both indirect pointers.
  INY                   ; first payload offset within frame
  TYA
  CLC
  ADC SS_P16
  STA SS_TEMP16
  LDA SS_P16 + 1
  ADC #0
  STA SS_TEMP16 + 1
  LDY #0
.payload_loop:
  LDA (SS_PAYLOAD16),Y
  STA (SS_TEMP16),Y
  INY
  CPY SS_PAYLOAD_SIZE
  BNE .payload_loop
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
  JSR check_source_frame_room
  LDA #SS_SRC_TYPE_MEMORY
  JSR push_source_frame ; Saves SS_MEM_PTR16 (still parent's) as prev_data
  LDA #SS_SRC_TYPE_MEMORY
  STA SS_SRC_TYPE
  PLA
  TAX                   ; Restore X
  RTS


; Push a memory source carrying a trailing payload region.
;
; The payload bytes are written into the frame immediately after
; prev_data; frame_size grows accordingly so subsequent walks/pops
; transparently account for the larger frame. The source-stack module
; itself never reads the payload bytes -- consumers (the memory-pop
; hook installed via ss_install_memory_pop) own their interpretation.
;
; On entry: SS_NAME       = name for this memory source
;           SS_MEM_PTR16  = parent's read position (same contract as
;                           push_memory_source -- caller installs the
;                           new buffer pointer AFTER this returns)
;           SS_PAYLOAD16  = pointer to the payload bytes
;           A             = payload size (1..N)
; On exit:  SS_PAYLOAD_SIZE reset to 0 so a subsequent plain
;           push_memory_source / push_file_source doesn't inherit
;           the payload reservation.
;           Other effects mirror push_memory_source.
push_memory_source_with_payload:
  STA SS_PAYLOAD_SIZE
  TXA
  PHA                   ; Save X
  JSR check_source_frame_room
  LDA #SS_SRC_TYPE_MEMORY
  JSR push_source_frame
  LDA #SS_SRC_TYPE_MEMORY
  STA SS_SRC_TYPE
  ; Reset payload size so the contract for plain pushes stays "no
  ; payload" without each caller having to clear it.
  LDA #0
  STA SS_PAYLOAD_SIZE
  PLA
  TAX                   ; Restore X
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
  ; curr_type / prev_type / prev_line live at fixed offsets 1..4 of the
  ; frame, so the dispatch on curr_type is now O(1) -- no need to scan
  ; past the name first.
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
  ; prev_type / prev_line reads below).
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
  ; prev_data sits after the (variable-length) name, so we walk past
  ; the name's null terminator before reading. Y is at offset 4 here;
  ; offset 5 starts the name. Once-per-pop O(name_len) cost, vs the
  ; pre-reorg "every walker pays it" cost.
.skip_name:
  INY
  LDA (SS_P16),Y
  BNE .skip_name
  ; Y points at the name's null. prev_data starts at Y+1.
  ; Restore prev_data based on prev_type.
  PLA
  BNE .restore_memory
  ; prev_type=0: restore file handle
  INY
  LDA (SS_P16),Y
  STA SS_CURR_FILE
  JMP ss_free_frame     ; Tail call: deallocate via offset-0 frame_size
.restore_memory:
  ; prev_type=1: restore memory pointer (zero-terminated, no end needed)
  INY
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

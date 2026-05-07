; Label Scope Management (for macro expansions)
;
; Each macro expansion gets a unique scope for local labels. The scope is
; identified by EXPANSION_ID, which acts as a synthetic "global label pointer"
; for local label scoping. Since expansion IDs are small integers (1, 2, 3...),
; they won't conflict with real heap addresses.
;
; Post-Phase-3.4, the per-expansion activation state lives on the source
; stack as the trailing payload of each macro's memory frame:
;   - LABEL_SCOPE16 (2 bytes) - restored on pop
;   - CACHED_HASH (1 byte) - restored on pop
;   - MACRO_ENTRY16 (2 bytes) - saved but not restored (read by
;                               check_macro_recursion to detect recursive
;                               expansions). Sits at the very end of the
;                               frame; check_macro_recursion locates it
;                               via frame_size - 2.
;
; expand_macro stages these 5 bytes in MACRO_ACTIVATION before calling
; push_memory_source_with_payload. pop_label_scope_from_frame (installed
; via ss_install_memory_pop) reads them back when the frame is popped.
;
; The legacy SCOPE_STACK / SCOPE_PTR16 / push_label_scope / pop_label_scope
; routines are still defined but no longer used (Phase 3.6 deletes them).
;
; Requires (from caller):
;   SCOPE_STACK          - base address of legacy scope stack (asm.asm)
;   MACRO_ENTRY16        - macro hash table entry address (asm.asm)
;
; Requires (from hash_table.asm):
;   LABEL_SCOPE16        - current scope for local label resolution
;   CACHED_HASH          - pre-computed hash for current scope
;   scramble_table       - hash scrambling table
;
; Requires (from source_stack.asm):
;   SS_P16               - source stack pointer (read by
;                          pop_label_scope_from_frame to locate payload)
;
; Requires (errors.asm):
;   err_macro_nesting_too_deep - error handler for legacy scope overflow

SCOPE_ENTRY_SIZE = 5

  .zeropage

EXPANSION_ID16: .word       ; 2-byte expansion counter for macro scopes
SCOPE_PTR16:    .word       ; Pointer to next free slot in scope stack
SCOPE_DEPTH:    .byte       ; Current nesting depth (0 = not in macro)

  .code


; Initialize/reset scope stack and expansion ID counter
; Called at program start and between passes (to ensure pass 2 uses same scope IDs)
; On exit: SCOPE_PTR16 points to SCOPE_STACK (empty stack)
;          EXPANSION_ID16 = 0, SCOPE_DEPTH = 0
;          A clobbered, X/Y preserved
init_scope_stack:
  SET16 SCOPE_STACK, SCOPE_PTR16
  LDA #$00
  STA_LH16 EXPANSION_ID16
  STA SCOPE_DEPTH
  RTS
reset_scope_stack = init_scope_stack


; Push current label scope and create new macro expansion scope
; Saves LABEL_SCOPE16, CACHED_HASH, and MACRO_ENTRY16 to scope stack,
; increments EXPANSION_ID, sets up synthetic scope using expansion ID.
;
; EXPANSION_ID16 is a monotonic counter (NOT saved/restored) to ensure each
; macro expansion gets a unique ID, preventing collisions in sibling expansions.
;
; MACRO_ENTRY16 is saved for recursion detection, but NOT restored on pop since
; it's only needed during initial setup (reading body pointer). After setup,
; the macro body is in the memory source and params are in the hash table.
;
; On entry: MACRO_ENTRY16 contains the macro's hash table entry address
; On exit: New scope active (LABEL_SCOPE16 = EXPANSION_ID, CACHED_HASH set)
;          Previous scope saved on scope stack
;          A, Y clobbered, X preserved
push_label_scope:
  ; SCOPE_STACK bounds check
  ; Check if SCOPE_PTR16 <= SCOPE_LIMIT - SCOPE_ENTRY_SIZE (room for one more entry)
  CMPI16 SCOPE_PTR16, SCOPE_LIMIT - SCOPE_ENTRY_SIZE
  BCC .scope_ok       ; Less than limit: safe
  BEQ .scope_ok       ; Equal to limit: safe
  JMP err_macro_nesting_too_deep
.scope_ok:
  .macro APPEND_TO_SCOPE ptr
  LDA ptr
  STA (SCOPE_PTR16),Y
  INY
  .endmacro
  ; Save current scope state to scope stack
  LDY #$00
  APPEND_TO_SCOPE LABEL_SCOPE16
  APPEND_TO_SCOPE LABEL_SCOPE16 + 1
  APPEND_TO_SCOPE CACHED_HASH
  ; Save macro entry address for recursion detection
  APPEND_TO_SCOPE MACRO_ENTRY16
  APPEND_TO_SCOPE MACRO_ENTRY16 + 1
  ; Advance scope pointer by 5 bytes for the 5 entries added above
  CLC
  ADCI16 SCOPE_PTR16, $05, SCOPE_PTR16
  ; Increment expansion ID
  INC16 EXPANSION_ID16
  ; Set LABEL_SCOPE16 to expansion ID (synthetic scope pointer)
  CP16 EXPANSION_ID16, LABEL_SCOPE16
  ; Calculate CACHED_HASH from expansion ID
  ; Use low byte through scramble table for reasonable distribution
  LDA EXPANSION_ID16
  AND #$7F
  TAY
  LDA scramble_table,Y
  STA CACHED_HASH
  ; Increment scope depth
  INC SCOPE_DEPTH
  RTS


; Pop label scope, restoring previous LABEL_SCOPE16 and CACHED_HASH
;
; Note: EXPANSION_ID16 is NOT restored (it's a monotonic counter, not stack-based)
; Note: MACRO_ENTRY16 is NOT restored (only needed during setup, stays on stack
;       for recursion detection via check_macro_recursion)
;
; On exit: Previous scope restored from scope stack
;          A, Y clobbered, X preserved
pop_label_scope:
  ; Move scope pointer back by 5 bytes
  SEC
  SBCI16 SCOPE_PTR16, $05, SCOPE_PTR16
  ; Restore scope state from scope stack
  LDY #$00
  LDA (SCOPE_PTR16),Y
  STA LABEL_SCOPE16
  INY
  LDA (SCOPE_PTR16),Y
  STA LABEL_SCOPE16 + 1
  INY
  LDA (SCOPE_PTR16),Y
  STA CACHED_HASH
  ; Decrement scope depth
  DEC SCOPE_DEPTH
  RTS


; Memory-source pop hook installed at startup via ss_install_memory_pop.
; Called from pop_source's curr_type=memory dispatch when a macro frame
; is popped. The frame's last 5 bytes hold the activation payload that
; expand_macro stashed in via push_memory_source_with_payload:
;
;   payload offset 0..1: prev LABEL_SCOPE16 lo/hi
;   payload offset 2:    prev CACHED_HASH
;   payload offset 3..4: prev MACRO_ENTRY16 (saved for check_macro_recursion;
;                                            not restored on pop, matching
;                                            the legacy pop_label_scope)
;
; Restores LABEL_SCOPE16 and CACHED_HASH; decrements SCOPE_DEPTH. The
; pop_source dispatch preserves Y/X around this call, so we can clobber
; them freely.
pop_label_scope_from_frame:
  LDY #0
  LDA (SS_P16),Y          ; frame_size
  SEC
  SBC #5                  ; offset of activation payload start
  TAY
  LDA (SS_P16),Y
  STA LABEL_SCOPE16
  INY
  LDA (SS_P16),Y
  STA LABEL_SCOPE16 + 1
  INY
  LDA (SS_P16),Y
  STA CACHED_HASH
  DEC SCOPE_DEPTH
  RTS

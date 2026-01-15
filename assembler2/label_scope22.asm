; Label Scope Management (for macro expansions)
;
; Each macro expansion gets a unique scope for local labels. The scope is
; identified by EXPANSION_ID, which acts as a synthetic "global label pointer"
; for local label scoping. Since expansion IDs are small integers (1, 2, 3...),
; they won't conflict with real heap addresses.
;
; Scope state is saved on a dedicated scope stack (SCOPE_STACK in memory),
; NOT the 6502 stack. Each entry is 5 bytes:
;   - LABEL_SCOPE16 (2 bytes)
;   - CACHED_HASH
;   - MACRO_ENTRY16 (macro hash table address for recursion detection)
;
; The scope stack grows upward from SCOPE_STACK.
;
; Requires (from caller):
;   SCOPE_STACK          - base address of scope stack
;   MACRO_ENTRY16        - macro hash table entry address (set before push)
;
; Requires (from hash_table22.asm):
;   LABEL_SCOPE16        - current scope for local label resolution
;   CACHED_HASH          - pre-computed hash for current scope
;   scramble_table       - hash scrambling table


  .zeropage

EXPANSION_ID16 .data $0000 ; 2-byte expansion counter for macro scopes
SCOPE_PTR16    .data $0000 ; Pointer to next free slot in scope stack

  .code


; Initialize scope stack and expansion ID counter (call once at program start)
; On exit: SCOPE_PTR16 points to SCOPE_STACK (empty stack)
;          EXPANSION_ID16 = 0
;          A clobbered, X/Y preserved
init_scope_stack
  SET16 SCOPE_STACK SCOPE_PTR16
  SET16 $00 EXPANSION_ID16
  RTS


; Reset scope stack and expansion ID to initial state (call between passes)
; This ensures pass 2 uses the same scope IDs as pass 1
; On exit: SCOPE_PTR16 points to SCOPE_STACK (empty stack)
;          EXPANSION_ID16 = 0
;          A clobbered, X/Y preserved
reset_scope_stack
  SET16 SCOPE_STACK SCOPE_PTR16
  SET16 $00 EXPANSION_ID16
  RTS


; Push current label scope and create new macro expansion scope
; Saves LABEL_SCOPE16, CACHED_HASH, and MACRO_ENTRY16 to scope stack,
; increments EXPANSION_ID, sets up synthetic scope using expansion ID.
;
; On entry: MACRO_ENTRY16 contains the macro's hash table entry address
; On exit: New scope active (LABEL_SCOPE16 = EXPANSION_ID, CACHED_HASH set)
;          Previous scope saved on scope stack
;          A, Y clobbered, X preserved
push_label_scope
  .macro APPEND_TO_SCOPE ptr
  LDA ptr
  STA (SCOPE_PTR16),Y
  INY
  .endmacro
  ; Save current scope state to scope stack
  LDY #$00
  APPEND_TO_SCOPE LABEL_SCOPE16
  APPEND_TO_SCOPE LABEL_SCOPE16+$01
  APPEND_TO_SCOPE CACHED_HASH
  ; Save macro entry address for recursion detection
  APPEND_TO_SCOPE MACRO_ENTRY16
  APPEND_TO_SCOPE MACRO_ENTRY16+$01
  ; Advance scope pointer by 5 bytes for the 5 entries added above
  CLC
  ADDI16 SCOPE_PTR16 $05 SCOPE_PTR16
  ; Increment expansion ID
  INC16 EXPANSION_ID16
  ; Set LABEL_SCOPE16 to expansion ID (synthetic scope pointer)
  CP16 EXPANSION_ID16 LABEL_SCOPE16
  ; Calculate CACHED_HASH from expansion ID
  ; Use low byte through scramble table for reasonable distribution
  LDA EXPANSION_ID16
  AND #$7F
  TAY
  LDA scramble_table,Y
  STA CACHED_HASH
  RTS


; Pop label scope, restoring previous LABEL_SCOPE16 and CACHED_HASH
; On exit: Previous scope restored from scope stack
;          A, Y clobbered, X preserved
pop_label_scope
  ; Move scope pointer back by 5 bytes
  SEC
  SUBI16 SCOPE_PTR16 $05 SCOPE_PTR16
  ; Restore scope state from scope stack
  LDY #$00
  LDA (SCOPE_PTR16),Y
  STA LABEL_SCOPE16
  INY
  LDA (SCOPE_PTR16),Y
  STA LABEL_SCOPE16+$01
  INY
  LDA (SCOPE_PTR16),Y
  STA CACHED_HASH
  RTS

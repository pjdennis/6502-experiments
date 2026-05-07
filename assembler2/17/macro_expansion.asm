; macro_expansion.asm - Macro invocation and expansion
;
; Provides: check_macro_recursion, expand_macro
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in source_stack.asm)
;   TOKEN, PASS (asm.asm)
;   IN_MACRO_DEF (macro_capture.asm)
;   MACRO_ENTRY16, OPERAND16, TEMP, MACRO_MAX_ARGS (asm.asm)
;   LABEL_SCOPE16, CACHED_HASH, scramble_table (hash_table.asm)
;   EXPANSION_ID16, SCOPE_DEPTH, MACRO_LOOKUP_FRAME16,
;     MACRO_PAYLOAD_BASE16, MACRO_ARG_REMAIN (label_scope.asm)
;   read_char (asm.asm alias; implemented in source_stack.asm)
;   check_for_end_of_line (tokenizer.asm)
;   parse_expression (expressions.asm)
;   select_label_hash_table (common.asm)
;   hash_add (hash_table.asm), store_hash_value (common.asm)
;   push_memory_source_reserve_payload, SS_P16, SS_PAYLOAD_SIZE,
;     SS_MEM_PTR16, SS_NAME, SS_SRC_TYPE_MEMORY (source_stack.asm)
;   err_* (errors.asm)

  .code


; Check if the active macro is already being expanded somewhere up the
; macro-frame chain. Walks via the prev_macro_lookup linked list
; threaded through each macro frame's payload, comparing each saved
; MACRO_ENTRY16 against the active one. File frames are skipped for
; free -- they don't sit in the chain at all. Pre-step-1 this used
; ss_walk_frames_by_type; the linked-list walk is faster (no per-frame
; CMPI16 against SOURCE_STACK, no curr_type filter test) and more
; direct.
;
; On entry: MACRO_ENTRY16 = the macro's hash table entry address.
; On exit:  Returns normally if no recursion; jumps to err_recursive_macro
;           on match. TABP16, A, Y clobbered; X preserved.
check_macro_recursion:
  ; TABP16 walks the chain, starting at MACRO_LOOKUP_FRAME16 (the
  ; innermost macro frame, or $0000 outside any macro).
  LDA MACRO_LOOKUP_FRAME16
  STA TABP16
  LDA MACRO_LOOKUP_FRAME16 + 1
  STA TABP16 + 1
.cmr_loop:
  ; Empty chain (or end of chain) -> no recursion.
  LDA TABP16
  ORA TABP16 + 1
  BEQ .cmr_done
  ; Compare this frame's MACRO_ENTRY16 (last 2 bytes of frame) against
  ; the active one. Match -> recursive; report and abort.
  LDY #0
  LDA (TABP16),Y          ; frame_size
  SEC
  SBC #2                  ; offset of saved MACRO_ENTRY16 lo
  TAY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16
  BNE .cmr_advance
  INY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16 + 1
  BNE .cmr_advance
  JMP err_recursive_macro
.cmr_advance:
  ; Move to the parent macro frame via prev_macro_lookup. Layout:
  ;   ... LABEL_SCOPE16 lo/hi, CACHED_HASH,
  ;       prev_macro_lookup lo/hi, MACRO_ENTRY16 lo/hi
  ; prev_macro_lookup sits at frame_size - 4..-3 (Y is currently at
  ; frame_size - 1; back up 3 for the lo byte).
  TYA
  SEC
  SBC #3                  ; offset of prev_macro_lookup lo (frame_size - 4)
  TAY
  LDA (TABP16),Y
  PHA                     ; stash new TABP16 lo byte
  INY
  LDA (TABP16),Y          ; new TABP16 hi byte
  STA TABP16 + 1
  PLA
  STA TABP16
  JMP .cmr_loop
.cmr_done:
  RTS


; Look up TOKEN's identifier in the parameter slots of the memory frame
; at TABP16 (typically the innermost macro frame, supplied by
; resolve_identifier from MACRO_LOOKUP_FRAME16). Walks the macro
; definition's parameter name list to find an index, then reads the
; matching slot from the frame.
;
; Frame payload (last bytes, low to high offset):
;   slots[0..N-1]   3 bytes each: fwdref, value_L, value_H
;   scope_block      LABEL_SCOPE16 lo/hi, CACHED_HASH,
;                    prev_macro_lookup lo/hi, MACRO_ENTRY16 lo/hi at
;                    offsets frame_size - 7..-1
;
; N is read from the def itself: MACRO_ENTRY16 (at the end of the
; payload) points at the count byte, with param names following. The
; frame no longer carries a separate arg_count -- the def is canonical.
;
; On entry: TABP16 = memory frame address; TOKEN holds the identifier.
; On exit:  C=0 if found -- HEX16 (= OPERAND16) and IS_FWDREF set,
;             matching find_in_hash's contract.
;           C=1 if no parameter matched. HEX16/IS_FWDREF unchanged.
;           A, Y, HTTP16, TEMP clobbered. X preserved (the output file
;             handle in macro bodies, the activation byte index in
;             expand_macro Phase 1's nested-arg-parse path).
ss_lookup_param_slot:
  ; Save X -- callers depend on X surviving identifier lookup.
  TXA
  PHA
  ; Read frame_size; stash on the 6502 stack (used twice below).
  LDY #0
  LDA (TABP16),Y
  PHA
  ; Load HTTP16 = MACRO_ENTRY16 from the last 2 bytes of the frame.
  SEC
  SBC #2                         ; offset of MACRO_ENTRY16 lo
  TAY
  LDA (TABP16),Y
  STA HTTP16
  INY
  LDA (TABP16),Y
  STA HTTP16 + 1
  ; Read N (the count byte) from the def. MACRO_ENTRY16 points at it.
  LDY #0
  LDA (HTTP16),Y                 ; A = N
  TAX                             ; X = remaining param iterations
  STA TEMP                       ; TEMP = N
  ASL                             ; 2N
  CLC
  ADC TEMP                       ; 3N
  STA TEMP                       ; TEMP = 3N
  ; Compute start_of_slots offset = (frame_size - 7) - 3*N. The
  ; scope_block sits at frame_size - 7..-1 so the last slot ends just
  ; before it.
  PLA                            ; A = frame_size
  SEC
  SBC #7                         ; A = scope_block offset
  SEC
  SBC TEMP                       ; A = start_of_slots offset
  STA TEMP                       ; TEMP = current slot offset
  ; Advance HTTP16 past the count byte to land on param1's first byte.
  CLC
  LDA HTTP16
  ADC #$01
  STA HTTP16
  LDA HTTP16 + 1
  ADC #$00
  STA HTTP16 + 1
  ; Walk the param-name list. X is the number of names still to check;
  ; on each miss, advance HTTP16 past the null terminator, bump TEMP by
  ; 3 (next slot), and DEX. Termination is count-driven now that the
  ; trailing empty-string sentinel is gone.
.lps_iter:
  CPX #0
  BEQ .lps_not_found             ; walked all N names without a match
  LDY #0
.lps_cmp:
  LDA (HTTP16),Y
  CMP TOKEN,Y
  BNE .lps_skip
  CMP #0
  BEQ .lps_match
  INY
  BNE .lps_cmp                    ; tokens are < 256 chars
.lps_skip:
  ; Names differ. Advance past this param's null and try the next one.
  ; Y indexes into the param name; walk to its null.
.lps_to_null:
  LDA (HTTP16),Y
  BEQ .lps_past_null
  INY
  BNE .lps_to_null
.lps_past_null:
  TYA
  SEC                             ; +1 to skip the null
  ADCA16 HTTP16, HTTP16
  ; slot offset += 3
  LDA TEMP
  CLC
  ADC #3
  STA TEMP
  DEX
  JMP .lps_iter
.lps_match:
  ; Slot at offset TEMP holds [fwdref, value_L, value_H].
  LDY TEMP
  LDA (TABP16),Y
  STA IS_FWDREF
  INY
  LDA (TABP16),Y
  STA HEX16
  INY
  LDA (TABP16),Y
  STA HEX16 + 1
  ; Restore X and return C=0 (found).
  PLA
  TAX
  CLC
  RTS
.lps_not_found:
  PLA
  TAX
  SEC
  RTS


; Expand a macro invocation
; On entry: MACRO_DEF_PTR points to the macro entry
;           ([N], param1\0, ..., paramN\0, body\0)
;           TOKEN contains the macro name
; On exit: Memory source pushed
expand_macro:
  ; Save original macro entry address before MACRO_DEF_PTR is modified
  CP16 MACRO_DEF_PTR16, MACRO_ENTRY16
  ; Check for recursive macro invocation
  JSR check_macro_recursion
  ; Save X (output file handle); reused below as the byte cursor while
  ; writing parsed slots into the future frame's payload area.
  TXA
  PHA

  ; Read N (the count byte) from the def. MACRO_MAX_ARGS was validated
  ; at definition time, so we don't recheck here.
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  STA MACRO_ARG_REMAIN
  ; Advance MACRO_DEF_PTR past the count byte so the param-name walk
  ; below sees param1 at offset 0. After parsing every arg
  ; MACRO_DEF_PTR16 lands directly on the body's first byte (no
  ; terminator to skip).
  CLC
  LDA MACRO_DEF_PTR16
  ADC #$01
  STA MACRO_DEF_PTR16
  LDA MACRO_DEF_PTR16 + 1
  ADC #$00
  STA MACRO_DEF_PTR16 + 1

  ; Compute payload_size = 3*N + 7. TEMP = 3*N is used twice below
  ; (frame-size check + slot-base computation).
  ; Payload = N slots (3 bytes each) + 7-byte scope tail
  ; (LABEL_SCOPE16, CACHED_HASH, prev_macro_lookup, MACRO_ENTRY16).
  LDA MACRO_ARG_REMAIN
  ASL                       ; 2N
  CLC
  ADC MACRO_ARG_REMAIN      ; 3N
  STA TEMP                  ; TEMP = 3N (survives parse_expression)
  CLC
  ADC #$07                  ; A = 3N + 7 = payload_size
  STA SS_PAYLOAD_SIZE       ; reservation size for the eventual push

  ; Worst-case frame_size = 15 + name_len + 3*N. If > 255, raise
  ; err_too_many_arguments. (Memory parent's prev_data is 2 bytes,
  ; file parent's 1 byte; using 15 covers the worst case so the limit
  ; is independent of who's calling us.)
  LDY #$FF
.measure_name:
  INY
  LDA SS_NAME,Y
  BNE .measure_name
  TYA
  CLC
  ADC TEMP                  ; A = name_len + 3N
  BCC .frame_size_check_2
  JMP .too_many
.frame_size_check_2:
  CLC
  ADC #$0F                  ; A = 15 + name_len + 3N
  BCC .frame_size_ok
  JMP .too_many             ; would overflow frame_size byte
.frame_size_ok:

  ; Pre-OOM-check the upcoming frame so the slot writes below are
  ; guaranteed to land in protected memory. This sets SS_TEMP16 to
  ; the proposed new SS_P16, but we don't need that value -- the
  ; push at the end will recompute it.
  JSR check_source_frame_room

  ; ----- Pre-allocate the payload region without moving SS_P16 -----
  ;
  ; The future payload region will sit at (SS_P16 - payload_size) ..
  ; (SS_P16 - 1) once the frame is pushed. Until then, that range is
  ; unallocated source-stack memory just below SS_P16. Heap can't
  ; reach it (the OOM check above just verified there are at least
  ; payload_size + 256 bytes of buffer), and parse_expression doesn't
  ; allocate, so we can write slot data there now and push later.
  ;
  ; MACRO_PAYLOAD_BASE16 = (SS_P16 - payload_size). Indirect-Y writes into
  ; (MACRO_PAYLOAD_BASE16),Y populate slot[0..N-1] at offsets 0..3*N-1 and
  ; the scope tail at offsets 3*N..3*N+6. After the push,
  ; push_memory_source_reserve_payload skips the copy (sees the
  ; MACRO_PAYLOAD_BASE16=$0000 sentinel it sets internally) and the bytes we
  ; wrote here are exactly the frame's payload.
  ;
  ; Crucially, SS_P16 / SS_SRC_TYPE / SS_MEM_PTR16 / SS_CURR_LINE16
  ; are unchanged during arg parsing -- the parent's source stays
  ; active so read_char keeps reading args from where the invocation
  ; sits, and any error during arg parsing reports the correct
  ; line / source.
  SEC
  LDA SS_P16
  SBC SS_PAYLOAD_SIZE
  STA MACRO_PAYLOAD_BASE16
  LDA SS_P16 + 1
  SBC #$00
  STA MACRO_PAYLOAD_BASE16 + 1

  ; ----- Phase 1: parse args, writing slots into (MACRO_PAYLOAD_BASE16) -----
  ;
  ; X = byte offset within the payload region for the next slot. X is
  ; preserved across parse_expression (find_in_hash and
  ; ss_lookup_param_slot both preserve it), so it survives the loop
  ; without explicit save/restore.
  LDX #$00
.parse_loop:
  LDA MACRO_ARG_REMAIN
  BEQ .parse_done
  ; Skip past parameter name in the def
  LDY #$FF
.skip_param:
  INY
  LDA (MACRO_DEF_PTR16),Y
  BNE .skip_param
  TYA
  SEC                       ; +1 for the null
  ADCA16 MACRO_DEF_PTR16, MACRO_DEF_PTR16
  ; Check that an argument is present
  JSR check_for_end_of_line
  BCC .have_arg
  JMP err_too_few_arguments
.have_arg:
  ; Parse argument expression in PARENT'S scope (MACRO_LOOKUP_FRAME16
  ; still points at the parent macro frame, or $0000 at top level).
  JSR parse_expression
  ; Write slot at (MACRO_PAYLOAD_BASE16)[X..X+2] = [fwdref, value_L, value_H]
  TXA
  TAY
  LDA IS_FWDREF
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA OPERAND16
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA OPERAND16 + 1
  STA (MACRO_PAYLOAD_BASE16),Y
  ; Advance X past this slot
  INX
  INX
  INX
  ; Decrement remaining; if 0, last arg consumed.
  DEC MACRO_ARG_REMAIN
  BEQ .parse_done
  ; More params expected - require comma
  JSR check_for_end_of_line
  BCS .too_few_next
  CMP #','
  BNE .arg_err_comma
  JSR read_char
  JMP .parse_loop
.too_few_next:
  JMP err_too_few_arguments
.arg_err_comma:
  JMP err_comma_expected
.parse_done:
  ; No extra args allowed
  JSR check_for_end_of_line
  BCS .args_done_ok
  JMP .too_many
.args_done_ok:
  ; ----- Write parent's scope state into the scope_block region -----
  ;
  ; X currently equals 3*N (the scope-block offset within the payload)
  ; because we INX'd 3 per arg. Point Y at it for the indirect-Y
  ; stores below.
  TXA
  TAY
  LDA LABEL_SCOPE16
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA LABEL_SCOPE16 + 1
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA CACHED_HASH
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA MACRO_LOOKUP_FRAME16
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA MACRO_LOOKUP_FRAME16 + 1
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA MACRO_ENTRY16
  STA (MACRO_PAYLOAD_BASE16),Y
  INY
  LDA MACRO_ENTRY16 + 1
  STA (MACRO_PAYLOAD_BASE16),Y

  ; ----- Switch to the new scope -----
  ;
  ; Done AFTER scope_block is captured so the saved values are the
  ; parent's, not the new ones.
  INC16 EXPANSION_ID16
  CP16 EXPANSION_ID16, LABEL_SCOPE16
  LDA EXPANSION_ID16
  AND #$7F
  TAY
  LDA scramble_table,Y
  STA CACHED_HASH
  INC SCOPE_DEPTH

  ; ----- Push the frame -----
  ;
  ; The payload region is already populated; push_memory_source_reserve_payload
  ; sets MACRO_PAYLOAD_BASE16=$0000 internally so push_source_frame's copy
  ; loop is skipped.
  LDA SS_PAYLOAD_SIZE
  JSR push_memory_source_reserve_payload

  ; Anchor MACRO_LOOKUP_FRAME16 at the new top frame so identifier
  ; lookups inside the body resolve from this frame's slots.
  LDA SS_P16
  STA MACRO_LOOKUP_FRAME16
  LDA SS_P16 + 1
  STA MACRO_LOOKUP_FRAME16 + 1

  ; Install body pointer. The arg loop advanced MACRO_DEF_PTR16 past
  ; every param name; it now sits on the body's first byte.
  CP16 MACRO_DEF_PTR16, SS_MEM_PTR16

  ; Restore X (output file handle)
  PLA
  TAX
  RTS
.too_many:
  JMP err_too_many_arguments

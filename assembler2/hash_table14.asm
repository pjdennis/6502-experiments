; Requires:
;   HT_KEY       - the address of the key used for hash table operations
;   HT_VL;HT_VH  - zero page locations containing value in hash table
;   MEMPL;MEMPH  - addres of heap to store table entries
;   advance_heap - function to advance the heap
;   CURR_GLOBAL_HEAP_L;CURR_GLOBAL_HEAP_H - heap address of current global label (for local labels)


  .zeropage

HASH      DATA $00     ; 1 byte hash value
HTPL      DATA $00     ; 2 byte pointer to hash table
HTPH      DATA $00     ; "
TABPL     DATA $00     ; 2 byte table pointer
TABPH     DATA $00     ; "
HTTPL     DATA $00     ; 2 byte temporary pointer
HTTPH     DATA $00     ; "
IS_LOCAL_LABEL DATA $00 ; Flag: non-zero if storing local label
CT_REFPL  DATA $00     ; compare_token: reference string pointer
CT_REFPH  DATA $00     ; "
CT_SAVE_Y DATA $00     ; compare_token: saved Y position

  .code


; Contains each byte $00-$7F exactly once in random order
scramble_table
  DATA $01 $20 $33 $1B $1C $16 $29 $1F $3A $75 $62 $42 $68 $79 $00 $52
  DATA $32 $0B $22 $77 $72 $71 $10 $59 $06 $4D $17 $37 $40 $0C $66 $21
  DATA $1E $43 $3E $30 $13 $07 $7E $44 $6C $58 $15 $1A $5A $24 $0F $7A
  DATA $7B $39 $4B $53 $70 $73 $19 $69 $55 $7D $4C $2C $7C $47 $23 $61
  DATA $56 $48 $74 $2F $76 $26 $2E $2B $6B $57 $12 $4F $25 $64 $0A $27
  DATA $50 $65 $5D $31 $2A $46 $6F $5F $67 $54 $18 $49 $05 $11 $03 $6E
  DATA $02 $0E $34 $5E $63 $08 $6D $14 $6A $0D $3B $4E $3D $60 $41 $38
  DATA $45 $7F $3F $3C $5C $2D $35 $51 $04 $28 $09 $4A $78 $1D $36 $5B


; Initialize a hash table
; On entry HTPL;HTPH point to the hash table
; On exit hash entries are initialized to 0 (empty table)
;         X is preserved
;         A, Y are not preserved
init_hash_table
  LDY# $00
  TYA                  ; A <- 0
.loop
  STAZ(),Y HTPL
  INY
  BNE .loop
  RTS


; On entry HT_KEY contains the token to calculate hash from
; On exit HASH contains the calculated hash value
;         X is preserved
;         A, Y are not preserved
calculate_hash
  TXA
  PHA
  LDA# $00
  STAZ HASH
  LDX# $00
.loop
  LDA,X HT_KEY
  BEQ .done
  AND# $7F
  EORZ HASH
  TAY
  LDA,Y scramble_table
  STAZ HASH
  INX
  JMP .loop
.done
  ASLZ HASH
  PLA
  TAX
  RTS


; On entry HT_KEY contains the key to find
; On exit C = 0 if found or 1 if not found
; On exit HT_VL;HT_VH contains the value if found
;         X is preserved
;         A, Y are not preserverd
find_in_hash
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ .not_found
  ; Entry exists
  JSR load_hash_entry
  JSR find_token
  BCS .not_found
  ; Found
  LDAZ(),Y TABPL
  STAZ HT_VL
  INY
  LDAZ(),Y TABPL
  STAZ HT_VH
  CLC
  RTS
.not_found
  SEC
  RTS


; On entry HASH contains the hash value
; On exit Z set if entry is empty, clear otherwise
;         X is preserved
;         A, Y are not preserved
hash_entry_empty
  LDAZ HASH
  TAY
  LDAZ(),Y HTPL
  BNE .done
  INY
  LDAZ(),Y HTPL
.done
  RTS


; Load from hash table to TABPL;TABPH
; On entry HASH contains the hash value
; On exit TABPL;TABPH countains pointer corresponding to the hash value
;         X is preserved
;         A, Y are not preserved
load_hash_entry
  LDAZ HASH
  TAY
  LDAZ(),Y HTPL
  STAZ TABPL
  INY
  LDAZ(),Y HTPL
  STAZ TABPH
  RTS


; Store current memory pointer in hash table
; On entry HASH contains the hash code to store under
;          MEMPL;MEMPH contains the pointer to store in the hash table
; On exit X is preserved
;         A, Y are not preserved
store_hash_entry
  LDAZ HASH
  TAY
  LDAZ MEMPL
  STAZ(),Y HTPL
  INY
  LDAZ MEMPH
  STAZ(),Y HTPL
  RTS


; Store current memory pointer in table
; On entry TABPL;TABPH,Y points to location to store pointer
;          MEMPL;NENPL contains the pointer to store
; On exit TABPL;TABPH,Y points to the location following the stored pointer
;         X is preserved
;         A is not preserved
store_table_entry
  LDAZ MEMPL
  STAZ(),Y TABPL
  INY
  LDAZ MEMPH
  STAZ(),Y TABPL
  INY
  RTS


; On entry HT_KEY contains the token to compare with
;          TABPL;TABPH points to the value to compare with
; On exit Z set if equal, unset otherwise
;         Y points to terminating 0 if equal
;         X is preserved (saved/restored - X is globally the file handle)
;         A is not preserved
; Handles both normal strings and $01 escape format:
;   $01 <addr_lo> <addr_hi> <rest_of_string>
; where addr points to a prefix string to prepend
compare_token
  ; Save X (file handle) and HTTPL/HTTPH (used by find_token after we return)
  TXA
  PHA
  LDAZ HTTPL
  PHA
  LDAZ HTTPH
  PHA
  ; Copy TABPL to working pointer HTTPL (we advance HTTPL, leave TABPL unchanged)
  LDAZ TABPL
  STAZ HTTPL
  LDAZ TABPH
  STAZ HTTPH
  ; X = HT_KEY index
  LDX# $00
.loop
  LDY# $00
  LDAZ(),Y HTTPL        ; Get byte from stored token
  CMP# $01
  BEQ .handle_escape
  ; Normal compare
  CMP,X HT_KEY          ; Compare with HT_KEY[X]
  BNE .done_nomatch
  CMP# $00
  BEQ .done_match
  ; Advance both pointers
  INX                   ; HT_KEY index++
  INCZ HTTPL            ; Stored pointer++
  BNE .loop
  INCZ HTTPH
  JMP .loop

.handle_escape
  ; Read reference address from HTTPL[1,2]
  INY
  LDAZ(),Y HTTPL
  STAZ CT_REFPL
  INY
  LDAZ(),Y HTTPL
  STAZ CT_REFPH
  ; Advance HTTPL past escape header (3 bytes: $01 + 2 addr bytes)
  CLC
  LDAZ HTTPL
  ADC# $03
  STAZ HTTPL
  LDAZ HTTPH
  ADC# $00
  STAZ HTTPH
  ; Compare reference string with HT_KEY
  LDY# $00
.ref_loop
  LDAZ(),Y CT_REFPL     ; Get byte from reference
  BEQ .ref_done         ; Null = end of reference, continue with stored
  CMP,X HT_KEY          ; Compare with HT_KEY[X]
  BNE .done_nomatch
  INX                   ; Advance HT_KEY index
  INY                   ; Advance reference index
  JMP .ref_loop

.ref_done
  JMP .loop             ; Continue comparing rest of stored token

.done_match
  ; Calculate Y = HTTPL - TABPL (offset to null terminator)
  SEC
  LDAZ HTTPL
  SBCZ TABPL
  TAY
  ; Restore HTTPL/HTTPH and X
  PLA
  STAZ HTTPH
  PLA
  STAZ HTTPL
  PLA
  TAX
  LDA# $00              ; Set Z flag (match)
  RTS

.done_nomatch
  ; Restore HTTPL/HTTPH and X
  PLA
  STAZ HTTPH
  PLA
  STAZ HTTPL
  PLA
  TAX
  LDA# $01              ; Clear Z flag (no match)
  RTS


; On entry TABPL;TABPH point to head of list of entries
;          HT_KEY contains the token to find
; On exit C clear if found; set if not found
;         TABPL;TABPH,Y points to value if found
;         or to 'next' pointer if not found
;         X is preserved
;         A, Y are not preserved
find_token
.token_loop
  ; Store the current pointer
  LDAZ TABPL
  STAZ HTTPL
  LDAZ TABPH
  STAZ HTTPH
  ; Advance past 'next' pointer
  CLC
  LDA# $02
  ADCZ TABPL
  STAZ TABPL
  LDA# $00
  ADCZ TABPH
  STAZ TABPH
  ; Check for matching token
  JSR compare_token
  BNE .token_is_non_match
  ; Match
  INY                  ; point tab,Y to value
  CLC
  RTS
.token_is_non_match    ; Not a match - move to next
  ; Check if 'next' pointer is 0
  LDY# $00
  LDAZ(),Y HTTPL
  BNE .not_at_end
  INY
  LDAZ(),Y HTTPL
  BEQ .at_end
.not_at_end
  LDY# $00
  LDAZ(),Y HTTPL
  STAZ TABPL
  INY
  LDAZ(),Y HTTPL
  STAZ TABPH
  JMP .token_loop
.at_end
  ; point tabp,Y to the zero 'next' pointer
  LDAZ HTTPL
  STAZ TABPL
  LDAZ HTTPH
  STAZ TABPH
  LDY# $00
  SEC ; Carry set indicates not found
  RTS


; Stores null next pointer and key on heap
; and advances heap pointer
; On entry HT_KEY contains key to store
;          IS_LOCAL_LABEL: if non-zero, stores $01 escape format
;          CURR_GLOBAL_HEAP_L/H: pointer to global label (for local labels)
; On exit MEMPL;MEMPH points to where value should be stored
;         Y = 0
;         X is preserved (saved/restored - X is globally the file handle)
;         A is not preserved
store_token
  LDY# $00
  ; Store null pointer (pointer to next)
  LDA# $00
  STAZ(),Y MEMPL
  INY
  STAZ(),Y MEMPL
  INY
  JSR advance_heap
  ; Check if this is a local label
  LDAZ IS_LOCAL_LABEL
  BEQ .store_normal
  ; Store $01 escape format: $01 <addr_lo> <addr_hi> <local_part>
  ; Save X (file handle) since we need it to find '.'
  TXA
  PHA
  LDY# $00
  LDA# $01              ; Escape byte
  STAZ(),Y MEMPL
  INY
  LDAZ CURR_GLOBAL_HEAP_L
  STAZ(),Y MEMPL
  INY
  LDAZ CURR_GLOBAL_HEAP_H
  STAZ(),Y MEMPL
  INY
  JSR advance_heap      ; Advance past escape header (3 bytes)
  ; Find '.' in HT_KEY
  LDX# $00
.find_dot
  LDA,X HT_KEY
  CMP# "."
  BEQ .found_dot
  INX
  BNE .find_dot
.found_dot
  ; Copy from '.' onwards (including null terminator)
  LDY# $00
.copy_local
  LDA,X HT_KEY
  STAZ(),Y MEMPL
  BEQ .done_local
  INY
  INX
  BNE .copy_local
.done_local
  INY
  PLA
  TAX                   ; Restore X (file handle)
  JMP advance_heap      ; Tail call

.store_normal
  ; Store full token name (original format)
  LDY# $FF
.loop
  INY
  LDA,Y HT_KEY
  STAZ(),Y MEMPL
  BNE .loop
  INY
  JMP advance_heap      ; Tail call


; Add HT_KEY to hash table
; On entry HT_KEY contains key
; On exit C = 0 if added or 1 if already exists
;         If C = 0, MEMPL;MEMPH points to where value should be stored
;         Caller must store value and call advance_heap
;         A, X, Y are not preserved
hash_add
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ .entry_empty
  JSR load_hash_entry
  JSR find_token
  BCS .new
  SEC
  RTS
.new
  JSR store_table_entry
  JMP .store
.entry_empty
  JSR store_hash_entry
.store
  JSR store_token
  CLC
  RTS

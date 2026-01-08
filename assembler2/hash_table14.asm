; Requires:
;   HT_KEY       - the address of the key used for hash table operations
;   HT_VL;HT_VH  - zero page locations containing value in hash table
;   MEMPL;MEMPH  - addres of heap to store table entries
;   advance_heap - function to advance the heap
;   CURR_GLOBAL_HEAP_L;CURR_GLOBAL_HEAP_H - heap address of current global label (for local labels)


  .zeropage

HASH      DATA $00     ; 1 byte hash value
HASH_PRE_ASL DATA $00  ; Pre-ASL hash value (temporary, not committed)
CACHED_HASH DATA $00   ; Pre-ASL hash of current global (for local labels)
HTPL      DATA $00     ; 2 byte pointer to hash table
HTPH      DATA $00     ; "
TABPL     DATA $00     ; 2 byte table pointer
TABPH     DATA $00     ; "
HTTPL     DATA $00     ; 2 byte temporary pointer
HTTPH     DATA $00     ; "
IS_LOCAL_LABEL DATA $00 ; Flag: non-zero if storing local label

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


; Calculate hash for global labels
; On entry HT_KEY contains the token to calculate hash from
; On exit HASH contains the calculated hash value (post-ASL)
;         HASH_PRE_ASL contains pre-ASL value (NOT committed to CACHED_HASH)
;         X is preserved
;         A, Y are not preserved
; Note: Caller must call commit_cached_hash to update CACHED_HASH if needed
calculate_hash
  TXA
  PHA
  LDA# $00
  STAZ HASH
  LDX# $00
  JSR hash_loop
  LDAZ HASH
  STAZ HASH_PRE_ASL       ; Save pre-ASL value (not committed)
  ASLZ HASH
  PLA
  TAX
  RTS

; Commit the pre-ASL hash to CACHED_HASH
; Call this when updating CURR_GLOBAL for non-assignment global labels
; On exit A is not preserved
;         X, Y are preserved
commit_cached_hash
  LDAZ HASH_PRE_ASL
  STAZ CACHED_HASH
  RTS

; Calculate hash for local labels
; Continues from CACHED_HASH, hashes HT_KEY (which will contain just ".bar")
; On exit HASH contains the calculated hash value (post-ASL)
;         X is preserved
;         A, Y are not preserved
calculate_hash_local
  TXA
  PHA
  LDAZ CACHED_HASH
  STAZ HASH
  LDX# $00
  JSR hash_loop
  ASLZ HASH
  PLA
  TAX
  RTS

; Calculate hash for instructions (does NOT modify CACHED_HASH)
; On entry HT_KEY contains the token to calculate hash from
; On exit HASH contains the calculated hash value (post-ASL)
;         CACHED_HASH is NOT modified
;         X is preserved
;         A, Y are not preserved
calculate_hash_instruction
  TXA
  PHA
  LDA# $00
  STAZ HASH
  LDX# $00
  JSR hash_loop
  ASLZ HASH
  PLA
  TAX
  RTS

; Shared hash loop - X = start index, HASH = initial value
; On exit: HASH = pre-ASL result, X at null terminator
; Private by convention (used only by calculate_hash and calculate_hash_local)
hash_loop
  LDA,X HT_KEY
  BEQ .done
  AND# $7F
  EORZ HASH
  TAY
  LDA,Y scramble_table
  STAZ HASH
  INX
  JMP hash_loop
.done
  RTS


; On entry HT_KEY contains the key to find
;          IS_LOCAL_LABEL: if non-zero, uses cached hash from global
; On exit C = 0 if found or 1 if not found
; On exit HT_VL;HT_VH contains the value if found
;         X is preserved
;         A, Y are not preserverd
find_in_hash
  LDAZ IS_LOCAL_LABEL
  BEQ .use_global_hash
  JSR calculate_hash_local
  JMP .hash_done
.use_global_hash
  JSR calculate_hash
.hash_done
  JMP find_in_hash_common

; Find in hash table for instructions (does not modify CACHED_HASH)
; On entry HT_KEY contains the key to find
; On exit C = 0 if found or 1 if not found
; On exit HT_VL;HT_VH contains the value if found
;         X is preserved
;         A, Y are not preserverd
find_in_hash_instruction
  JSR calculate_hash_instruction
  ; Fall through to common code

find_in_hash_common
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
;          IS_LOCAL_LABEL: if non-zero, we're searching for a local label
;          CURR_GLOBAL_HEAP_L/H: current scope (for local label verification)
; On exit Z set if equal, unset otherwise
;         Y points to terminating 0 if equal
;         X is preserved (saved/restored - X is globally the file handle)
;         A is not preserved
; Handles both normal strings and $01 escape format:
;   $01 <addr_lo> <addr_hi> ".local" $00
; For escape format, verifies scope pointer matches before comparing
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

  ; Check if stored token is escape format
  LDY# $00
  LDAZ(),Y HTTPL
  CMP# $01
  BNE .compare_global_format

  ; === Escape format ($01 <ptr_lo> <ptr_hi> ".bar" $00) ===
  ; Verify scope pointer matches CURR_GLOBAL_HEAP
  INY
  LDAZ(),Y HTTPL
  CMPZ CURR_GLOBAL_HEAP_L
  BNE .done_nomatch
  INY
  LDAZ(),Y HTTPL
  CMPZ CURR_GLOBAL_HEAP_H
  BNE .done_nomatch

  ; Scope matches - advance past header, compare local part
  CLC
  LDAZ HTTPL
  ADC# $03
  STAZ HTTPL
  LDAZ HTTPH
  ADC# $00
  STAZ HTTPH
  JMP .compare_loop_setup

.compare_global_format
  ; === Global format (direct string) ===
  ; If we're searching for a local label, global format can't match
  LDAZ IS_LOCAL_LABEL
  BNE .done_nomatch
  ; Fall through to compare

.compare_loop_setup
  LDX# $00              ; HT_KEY index
  LDY# $00              ; HTTPL index

.compare_loop
  LDAZ(),Y HTTPL
  CMP,X HT_KEY
  BNE .done_nomatch
  CMP# $00
  BEQ .done_match
  INX
  INY
  BNE .compare_loop

.done_match
  ; Calculate Y = offset from TABPL to null terminator
  ; Y currently points to null in local string
  ; total offset = (HTTPL - TABPL) + Y
  TYA
  PHA                       ; Save Y on stack
  SEC
  LDAZ HTTPL
  SBCZ TABPL                ; A = header size (0 or 3)
  STAZ HTTPH                ; temp store (will be restored from stack below)
  PLA                       ; A = saved Y
  CLC
  ADCZ HTTPH                ; A = header + Y
  TAY                       ; Y = offset to null terminator from TABPL
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
;            (HT_KEY should already contain just ".bar" for local labels)
;          CURR_GLOBAL_HEAP_L/H: pointer to global label (for local labels)
; On exit MEMPL;MEMPH points to where value should be stored
;         Y = 0
;         X is preserved
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
  ; HT_KEY already contains just ".bar" - no scanning needed
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
  ; Copy HT_KEY directly (already just ".bar")
  LDY# $FF
.copy_local
  INY
  LDA,Y HT_KEY
  STAZ(),Y MEMPL
  BNE .copy_local
  INY
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
;          IS_LOCAL_LABEL: if non-zero, uses cached hash from global
; On exit C = 0 if added or 1 if already exists
;         If C = 0, MEMPL;MEMPH points to where value should be stored
;         Caller must store value and call advance_heap
;         A, X, Y are not preserved
hash_add
  LDAZ IS_LOCAL_LABEL
  BEQ .use_global_hash
  JSR calculate_hash_local
  JMP .hash_done
.use_global_hash
  JSR calculate_hash
.hash_done
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

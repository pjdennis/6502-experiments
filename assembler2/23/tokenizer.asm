; tokenizer.asm - Character classification, skipping, token and hex reading
;
; Provides: compare_end_of_token, skip_token, convert_hex_character,
;           skip_spaces, skip_rest_of_line, check_for_end_of_line,
;           read_hex_byte, read_hex_byte_or_word, read_token, read_filename
;
; Requires:
;   CURR_CHAR, TOKEN, HEX16, TEMP
;   read_char
;   err_invalid_hex, err_token_too_long

  .code


; Check whether the current character (in A) is NOT a token character
; On entry A contains the current character
; On exit C=0 if current character terminates the current token; C=1 otherwise
;         A, X, Y are preserved
compare_end_of_token:
  ; Check if A is a valid token character (0-9, A-Z, _, a-z)
  ; Returns C=0 if token char (not end), C=1 if not token char (end of token)
  ; Preserves A, X, Y
  CMP #'z'+$01
  BCS .end              ; > 'z'
  CMP #'a'
  BCS .not_end          ; 'a'-'z'
  CMP #'_'
  BEQ .not_end          ; '_'
  CMP #'Z'+$01
  BCS .end              ; > 'Z'
  CMP #'A'
  BCS .not_end          ; 'A'-'Z'
  CMP #'9'+$01
  BCS .end              ; > '9'
  CMP #'0'
  BCS .not_end          ; '0'-'9'
.end:
  CLC
  RTS                   ; Returns with C=0 -> end of token
.not_end:
  RTS                   ; Returns with C=1 -> not end of token (set from CMP)


; Skip characters until token terminator
; On exit: A contains terminating character
skip_token:
  JSR read_char
  JSR compare_end_of_token
  BCS skip_token
  RTS


; Convert hex character to associated value
; On entry, A contains a hex character A-Z|0-9
; On exit A contains the value (0-15)
;         X, Y are preserved
; Raises 'Invalid hex' error if input is not a valid hex character
convert_hex_character:
  CMP #'A'
  BCS .alpha           ; >= 'A'
  ; Numeric path: '0'-'9' → 0-9
  SBC #'0'-$01         ; Subtract 1 since carry is clear from CMP
  CMP #'9'-'0'+$01     ; Check if result 0-9
  BCS .error           ; >= 10, invalid
  RTS
.alpha:
  ; Alpha path: 'A'-'F' → 10-15
  SBC #'A'             ; Carry already set from CMP
  CMP #'F'-'A'+$01     ; Check if result 0-5
  BCS .error           ; >= 6, invalid
  ADC #'9'-'0'+$01     ; Add 10 (carry clear from CMP)
  RTS
.error:
  JMP err_invalid_hex


; read_char is provided by file_stack.asm

; Read and discard space characters
; On entry CURR_CHAR contains the current character
; On exit A contains the current character following the last space
;         X, Y are preserved
skip_spaces:
  LDA CURR_CHAR
.loop:
  CMP #' '
  BNE .done
  JSR read_char
  BCC .loop
.done:
  RTS


; Read and discard characters up to the end of the current line
; On entry CURR_CHAR contains the current character
; On exit A contains "\n"
;         X, Y are preserved
skip_rest_of_line:
  LDA CURR_CHAR
.loop:
  CMP #'\n'
  BEQ .done
  JSR read_char
  BCC .loop
.done:
  RTS


; Skips spaces and checks for end of line and skips past if at end
; On entry CURR_CHAR contains current character
; On exit C set if end of line, clear otherwise
;         A contains current character
;         X, Y are preserved
check_for_end_of_line:
  JSR skip_spaces
  CMP #';'
  BEQ .end
  CMP #'\n'
  BEQ .done
  ; Not at end
  CLC
  RTS
.end:
  JSR skip_rest_of_line
.done:
  SEC
  RTS



; Reads 1 byte (2 character) hex value
; On entry A contains first hex character
; On exit A contains 2 character value (0-255)
;         X, Y are preserved
;         TEMP is not preserved
; Raises 'Invalid hex' error if encountering non-hex characters
read_hex_byte:
  JSR convert_hex_character
  ASL
  ASL
  ASL
  ASL
  STA TEMP
  JSR read_char
  JSR convert_hex_character
  ORA TEMP
  RTS


; Reads 1 or 2 byte (2 or 4 character) hex value
; On entry, A contains the first hex character
; On exit HEX16 contains the read value
;         X, Y are preserved
;         A is not preserved
; Raises 'Invalid hex' error if encountering non-hex characters
read_hex_byte_or_word:
  JSR read_hex_byte    ; Read 2nd hex character and convert
  STA HEX16+$01
  JSR read_char        ; Read 3rd hex char or terminator
  JSR compare_end_of_token
  BCS .second
  LDA HEX16+$01        ; No second byte so move result
  STA HEX16
  LDA #$00
  STA HEX16+$01
  RTS
.second:
  JSR read_hex_byte    ; Read 4th hex char and convert
  STA HEX16
  JSR read_char        ; Read char after 4th hex digit
  RTS


; Reads token into TOKEN (zero terminated)
; On entry A contains first character of token
; On exit CURR_CHAR contains current character after token
;         X is preserved
;         Y is not preserved
read_token:
  STX TEMP
  LDX #$00
.loop:
  JSR compare_end_of_token
  BCC .done
  ; TOKEN buffer bounds check (conservative 127-char limit)
  STA TOKEN,X
  INX
  BMI .token_overflow
  JSR read_char
  BCC .loop
.done:
  LDA #$00
  STA TOKEN,X
  LDX TEMP
  RTS
.token_overflow:
  JMP err_token_too_long


; Reads filename into TOKEN (zero terminated)
; On entry A contains first character of filename
; On exit CURR_CHAR contains current character after filename
;         X is preserved
;         Y is not preserved
read_filename:
  STX TEMP
  LDX #$00
.loop:
  CMP #' '
  BEQ .done
  CMP #'\n'
  BEQ .done
  ; TOKEN buffer bounds check (conservative 127-char limit)
  STA TOKEN,X
  INX
  BMI .token_overflow
  JSR read_char
  BCC .loop
.done:
  LDA #$00
  STA TOKEN,X
  LDX TEMP
  RTS
.token_overflow:
  JMP err_token_too_long

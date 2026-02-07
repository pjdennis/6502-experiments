; Normal mode command handlers

  .zeropage

LAST_KEY    .data $00    ; Previous key for multi-key commands (dd, gg)
LINE_LEN    .data $00    ; Cached length of current line

  .code

; Handle a keystroke in normal mode
; Key code in A
normal_handle_key
  STA BUF_TEMP

  ; Movement keys
  CMP #'h'
  BNE .not_h
  JMP normal_move_left
.not_h
  CMP #KEY_LEFT
  BNE .not_left
  JMP normal_move_left
.not_left
  CMP #'l'
  BNE .not_l
  JMP normal_move_right
.not_l
  CMP #KEY_RIGHT
  BNE .not_right
  JMP normal_move_right
.not_right
  CMP #'j'
  BNE .not_j
  JMP normal_move_down
.not_j
  CMP #KEY_DOWN
  BNE .not_down
  JMP normal_move_down
.not_down
  CMP #'k'
  BNE .not_k
  JMP normal_move_up
.not_k
  CMP #KEY_UP
  BNE .not_up
  JMP normal_move_up
.not_up
  CMP #'0'
  BNE .not_0
  JMP normal_line_start
.not_0
  CMP #KEY_HOME
  BNE .not_home
  JMP normal_line_start
.not_home
  CMP #'$'
  BNE .not_dollar
  JMP normal_line_end
.not_dollar
  CMP #KEY_END
  BNE .not_end
  JMP normal_line_end
.not_end
  CMP #'G'
  BNE .not_G
  JMP normal_goto_last
.not_G
  CMP #'g'
  BNE .not_g
  JMP normal_g_key
.not_g

  ; Skip editing keys in read-only mode
  LDA READONLY
  BNE .readonly_skip
  LDA BUF_TEMP         ; Reload key

  ; Editing keys
  CMP #'x'
  BNE .not_x
  JMP normal_delete_char
.not_x
  CMP #KEY_DEL
  BNE .not_del
  JMP normal_delete_char
.not_del
  CMP #'d'
  BNE .not_d
  JMP normal_d_key
.not_d
  CMP #'i'
  BNE .not_i
  JMP normal_enter_insert
.not_i
  CMP #'a'
  BNE .not_a
  JMP normal_enter_insert_after
.not_a
  CMP #'A'
  BNE .not_A
  JMP normal_enter_insert_eol
.not_A
  CMP #'o'
  BNE .not_o
  JMP normal_open_below
.not_o
  CMP #'O'
  BNE .not_O
  JMP normal_open_above
.not_O

.readonly_skip
  LDA BUF_TEMP         ; Reload key

  ; Command mode
  CMP #':'
  BNE .not_colon
  JMP normal_enter_command
.not_colon

  ; Unknown key - clear last key
  LDA #$00
  STA LAST_KEY
  RTS

; --- Movement ---

normal_move_left
  LDA CURSOR_COL
  BEQ .done
  DEC CURSOR_COL
.done
  LDA #$00
  STA LAST_KEY
  RTS

normal_move_right
  JSR get_current_line_len
  STA LINE_LEN
  BEQ .done           ; Empty line
  SEC
  SBC #$01
  CMP CURSOR_COL
  BCC .done           ; Already at or past end
  BEQ .done
  INC CURSOR_COL
.done
  LDA #$00
  STA LAST_KEY
  RTS

normal_move_down
  ; Check if there's a next line
  CLC
  LDA FILE_LINE16
  ADC #$01
  STA BUF_PTR16
  LDA FILE_LINE16+$01
  ADC #$00
  STA BUF_PTR16+$01

  LDA BUF_PTR16+$01
  CMP LINE_COUNT16+$01
  BCC .can_move
  BNE .done
  LDA BUF_PTR16
  CMP LINE_COUNT16
  BCS .done

.can_move
  INC16 FILE_LINE16

  ; Check if we need to scroll
  LDA CURSOR_ROW
  CLC
  ADC #$02
  CMP SCREEN_ROWS
  BCC .no_scroll
  INC16 VIEW_TOP16
  JMP .clamp_col
.no_scroll
  INC CURSOR_ROW
.clamp_col
  JSR clamp_cursor_col
.done
  LDA #$00
  STA LAST_KEY
  RTS

normal_move_up
  LDA FILE_LINE16
  ORA FILE_LINE16+$01
  BEQ .done

  DEC16 FILE_LINE16

  LDA CURSOR_ROW
  BNE .no_scroll
  DEC16 VIEW_TOP16
  JMP .clamp_col
.no_scroll
  DEC CURSOR_ROW
.clamp_col
  JSR clamp_cursor_col
.done
  LDA #$00
  STA LAST_KEY
  RTS

normal_line_start
  LDA #$00
  STA CURSOR_COL
  STA LAST_KEY
  RTS

normal_line_end
  JSR get_current_line_len
  BEQ .empty
  SEC
  SBC #$01
  STA CURSOR_COL
  LDA #$00
  STA LAST_KEY
  RTS
.empty
  LDA #$00
  STA CURSOR_COL
  STA LAST_KEY
  RTS

normal_goto_last
  SEC
  LDA LINE_COUNT16
  SBC #$01
  STA FILE_LINE16
  LDA LINE_COUNT16+$01
  SBC #$00
  STA FILE_LINE16+$01

  ; VIEW_TOP = max(0, LINE_COUNT - (SCREEN_ROWS - 1))
  LDA SCREEN_ROWS
  SEC
  SBC #$01
  STA BUF_TEMP
  SEC
  LDA LINE_COUNT16
  SBC BUF_TEMP
  STA VIEW_TOP16
  LDA LINE_COUNT16+$01
  SBC #$00
  STA VIEW_TOP16+$01
  BCS .view_ok
  LDA #$00
  STA_LH16 VIEW_TOP16
.view_ok

  SEC
  LDA FILE_LINE16
  SBC VIEW_TOP16
  STA CURSOR_ROW

  LDA #$00
  STA CURSOR_COL
  STA LAST_KEY
  JSR clamp_cursor_col
  RTS

normal_g_key
  LDA LAST_KEY
  CMP #'g'
  BNE .set_g
  ; gg: go to top
  LDA #$00
  STA_LH16 FILE_LINE16
  STA_LH16 VIEW_TOP16
  STA CURSOR_ROW
  STA CURSOR_COL
  STA LAST_KEY
  JSR clamp_cursor_col
  RTS
.set_g
  LDA #'g'
  STA LAST_KEY
  RTS

; --- Editing ---

normal_delete_char
  JSR get_current_line_len
  BEQ .done
  STA LINE_LEN

  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_get_line_ptr
  CLC
  LDA BUF_PTR16
  ADC CURSOR_COL
  STA BUF_PTR16
  LDA BUF_PTR16+$01
  ADC #$00
  STA BUF_PTR16+$01

  LDA CURSOR_COL
  CMP LINE_LEN
  BCS .done

  JSR buf_delete_char
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
.done
  LDA #$00
  STA LAST_KEY
  RTS

normal_d_key
  LDA LAST_KEY
  CMP #'d'
  BNE .set_d

  ; dd: delete current line
  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_delete_line
  LDA #$FF
  STA MODIFIED

  ; Clamp file line if past end
  LDA FILE_LINE16+$01
  CMP LINE_COUNT16+$01
  BCC .no_clamp
  BNE .do_clamp
  LDA FILE_LINE16
  CMP LINE_COUNT16
  BCC .no_clamp
.do_clamp
  SEC
  LDA LINE_COUNT16
  SBC #$01
  STA FILE_LINE16
  LDA LINE_COUNT16+$01
  SBC #$00
  STA FILE_LINE16+$01
.no_clamp
  LDA #$00
  STA LAST_KEY
  JSR clamp_cursor_col
  RTS

.set_d
  LDA #'d'
  STA LAST_KEY
  RTS

normal_enter_insert
  LDA #MODE_INSERT
  STA MODE
  LDA #$00
  STA LAST_KEY
  RTS

normal_enter_insert_after
  JSR get_current_line_len
  BEQ .enter
  CMP CURSOR_COL
  BEQ .enter
  BCC .enter
  INC CURSOR_COL
.enter
  LDA #MODE_INSERT
  STA MODE
  LDA #$00
  STA LAST_KEY
  RTS

normal_enter_insert_eol
  JSR get_current_line_len
  STA CURSOR_COL
  LDA #MODE_INSERT
  STA MODE
  LDA #$00
  STA LAST_KEY
  RTS

normal_open_below
  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_get_line_ptr

  LDY #$00
.find_nl
  LDA (BUF_PTR16),Y
  CMP #$0A
  BEQ .found_nl
  INY
  BNE .find_nl
.found_nl
  INY
  TYA
  CLC
  ADC BUF_PTR16
  STA BUF_PTR16
  LDA #$00
  ADC BUF_PTR16+$01
  STA BUF_PTR16+$01

  LDA #$0A
  JSR buf_insert_char
  BCS .open_below_full
  JSR buf_rebuild_lines

  INC16 FILE_LINE16
  LDA #$00
  STA CURSOR_COL

  LDA CURSOR_ROW
  CLC
  ADC #$02
  CMP SCREEN_ROWS
  BCC .no_scroll
  INC16 VIEW_TOP16
  JMP .set_mode
.no_scroll
  INC CURSOR_ROW
.set_mode
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  LDA #$00
  STA LAST_KEY
  RTS
.open_below_full
  SET16 str_buffer_full STR_PTR16
  JSR show_status_message
  LDA #$00
  STA LAST_KEY
  RTS

normal_open_above
  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_get_line_ptr

  LDA #$0A
  JSR buf_insert_char
  BCS .open_above_full
  JSR buf_rebuild_lines

  LDA #$00
  STA CURSOR_COL
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  LDA #$00
  STA LAST_KEY
  RTS
.open_above_full
  SET16 str_buffer_full STR_PTR16
  JSR show_status_message
  LDA #$00
  STA LAST_KEY
  RTS

normal_enter_command
  LDA #MODE_COMMAND
  STA MODE
  LDA #$00
  STA LAST_KEY
  RTS

; --- Utilities ---

get_current_line_len
  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_get_line_len
  RTS

clamp_cursor_col
  JSR get_current_line_len
  BEQ .set_zero
  SEC
  SBC #$01
  CMP CURSOR_COL
  BCS .ok
  STA CURSOR_COL
.ok
  RTS
.set_zero
  LDA #$00
  STA CURSOR_COL
  RTS

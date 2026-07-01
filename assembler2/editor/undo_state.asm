; Undo/redo support for normal mode deletion commands
;
; Single-level undo: 'u' toggles between undo and redo.
; The yank buffer stores deleted content, so undo = paste it back,
; redo = re-delete it.
;
; UNDO_TYPE values:
;   0 = none (no undoable operation)
;   1 = line-delete (dd, 2dd, etc.)
;   2 = char-delete (x, D, dw, db, de)
;   3 = cc/S line-delete (like line-delete but cc inserted blank line)
;   4 = join (J, NJ)
;   5 = line-paste-below (p with line yank)
;   6 = line-paste-above (P with line yank)
;   7 = char-paste-below (p with char yank)
;   8 = char-paste-above (P with char yank)
;   9 = open-line (o/O opened blank line(s))
;  10 = indent (spaces were added; undo removes them via unindent)
;  11 = unindent (spaces were removed; undo re-inserts recorded counts)
;  12 = toggle case (~; self-inverse, undo/redo re-toggle the span)
;  13 = replace char (r; originals in UNDO_DATA_BUF, redo re-writes)
;
; Types 10/11 are self-morphing: undoing an indent re-records as an
; unindent and vice versa, so repeated 'u' toggles without UNDO_IS_REDO.

UNDO_NONE = 0
UNDO_LINE = 1
UNDO_CHAR = 2
UNDO_CC   = 3
UNDO_JOIN = 4
UNDO_LINE_PASTE_BELOW = 5
UNDO_LINE_PASTE_ABOVE = 6
UNDO_CHAR_PASTE_BELOW = 7
UNDO_CHAR_PASTE_ABOVE = 8
UNDO_OPEN = 9
UNDO_INDENT = 10
UNDO_UNINDENT = 11
UNDO_TILDE = 12
UNDO_REPLACE = 13

; Shared per-operation undo data (single-level undo, so one page serves
; all users): join = 16-bit offsets, indent/unindent = per-line widths.
UNDO_DATA_BUF = $D700     ; 256 bytes
JOIN_UNDO_MAX = 128       ; 256 / 2 bytes per entry

  .zeropage

UNDO_TYPE:       .byte    ; 0=none, 1-4=delete/cc/join, 5-8=paste
UNDO_LINE16:     .word    ; FILE_LINE16 at time of operation
UNDO_COL16:      .word    ; CURSOR_COL16 at time of operation
UNDO_IS_REDO:    .byte    ; 0=undo pending, $FF=redo pending
INSERT_CHANGED:  .byte    ; tracks if insert mode modified buffer
UNDO_JOIN_COUNT: .byte    ; Number of joins recorded (1-128)
UNDO_PASTE_COUNT16: .word ; Paste multiplier N (for redo), 16-bit

  .code

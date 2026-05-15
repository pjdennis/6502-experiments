; Buffer memory copy routines - low-level memory move operations

; Backward copy (safe when dst >= src or non-overlapping)
; Input: BUF_SRC16 = source start, BUF_PTR16 = source end (exclusive),
;        BUF_DST16 = destination start
; Preserves BUF_SRC16. Clobbers A, Y, BUF_PTR16, BUF_DST16
mem_copy_up:
  ; Check empty case (SRC >= END)
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BCC .not_empty
  BNE .done
  LDA BUF_SRC16
  CMP BUF_PTR16
  BCS .done
.not_empty:

  ; Compute offset = BUF_DST16 - BUF_SRC16 (constant shift amount)
  ; Store in BUF_DST16 temporarily
  SEC
  SBC16 BUF_DST16, BUF_SRC16, BUF_DST16

  ; Set up page-aligned end pointer and Y offset
  ; BUF_PTR16 points to (end-1), page-aligned. Y = low byte of (end-1).
  SEC
  LDA BUF_PTR16
  SBC #1
  TAY                      ; Y = low byte of last source byte
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_PTR16 + 1
  LDA #0
  STA BUF_PTR16            ; BUF_PTR16 = page-aligned base

  ; BUF_DST16 = BUF_PTR16 + offset (so (BUF_DST16),Y gives correct dest)
  CLC
  ADC16 BUF_PTR16, BUF_DST16, BUF_DST16

  ; Check if source start is on the same page
  LDA BUF_PTR16 + 1
  CMP BUF_SRC16 + 1
  BNE .full_page

  ; Same page: copy Y down to low byte of BUF_SRC16
.last_page:
  LDA (BUF_PTR16),Y
  STA (BUF_DST16),Y
  CPY BUF_SRC16
  BEQ .done
  DEY
  JMP .last_page

.full_page:
  ; Copy from Y down to 0 on this page
  LDA (BUF_PTR16),Y
  STA (BUF_DST16),Y
  DEY
  CPY #$FF
  BNE .full_page

  ; Move to previous page
  DEC BUF_PTR16 + 1
  DEC BUF_DST16 + 1
  LDY #$FF

  ; Check if this is the page containing the source start
  LDA BUF_PTR16 + 1
  CMP BUF_SRC16 + 1
  BNE .full_page

  JMP .last_page

.done:
  RTS

; Forward copy (safe when dst <= src or non-overlapping)
; Input: BUF_SRC16 = source start, BUF_PTR16 = source end (exclusive),
;        BUF_DST16 = destination start
; Preserves BUF_PTR16. Clobbers A, Y, BUF_SRC16, BUF_DST16
mem_copy_down:
  ; Check empty case (SRC >= END)
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BCC .not_empty
  BNE .done
  LDA BUF_SRC16
  CMP BUF_PTR16
  BCS .done
.not_empty:

  ; Set up page-aligned source and Y offset
  ; Y = low byte of BUF_SRC16, BUF_SRC16 = page base
  ; Adjust BUF_DST16 so (BUF_DST16),Y gives correct dest address:
  ;   BUF_DST16 = BUF_DST16 - SRC_low_byte
  LDA BUF_SRC16
  TAY                      ; Y = source low byte offset
  SEC
  LDA BUF_DST16
  SBC BUF_SRC16            ; Subtract source low byte only
  STA BUF_DST16
  BCS .no_borrow
  DEC BUF_DST16 + 1
.no_borrow:
  LDA #0
  STA BUF_SRC16            ; BUF_SRC16 = page-aligned base

  ; Check if end is on the same page as start
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .full_page

  ; Same page: copy Y up to (end low - 1)
.last_page:
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  CPY BUF_PTR16
  BNE .last_page
  JMP .done

.full_page:
  ; Copy from Y up through $FF on this page
  LDA (BUF_SRC16),Y
  STA (BUF_DST16),Y
  INY
  BNE .full_page

  ; Move to next page
  INC BUF_SRC16 + 1
  INC BUF_DST16 + 1
  LDY #0

  ; Check if this is the last page
  LDA BUF_SRC16 + 1
  CMP BUF_PTR16 + 1
  BNE .full_page

  ; Check if end low byte is 0 (end is at page boundary)
  LDA BUF_PTR16
  BEQ .done

  JMP .last_page

.done:
  RTS

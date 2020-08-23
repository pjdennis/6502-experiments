; Requires D_S_I_P - 2 bytes in zero page

  .include display_update_routines.inc

D_S_I_P_L = D_S_I_P
D_S_I_P_H = D_S_I_P + 1
CHAROUT = display_character

; Print the string immediately following the jsr statment which invokes this routine
; On exit A, X, Y are preserved
; Routine from http://www.6502.org/source/io/primm.htm
display_string_immediate:
	PHA     		; save A
	PHY  			; save Y
	PHX  			; save X
	TSX			; get stack pointer
	LDA $0104,X		; get return address low byte (+4 to
				;   correct pointer)
	STA D_S_I_P_L		; save in page zero
	LDA $0105,X		; get return address high byte (+5 to
				;   correct pointer)
	STA D_S_I_P_H		; save in page zero
	LDY #$01		; set index (+1 to allow for return
				;   address offset)
PRIM2:
	LDA (D_S_I_P),Y		; get byte from string
	BEQ PRIM3		; exit if null (end of text)

	JSR CHAROUT		; else display character
	INY			; increment index
	BNE PRIM2		; loop (exit if 256th character)

PRIM3:
	TYA			; copy index
	CLC			; clear carry
	ADC D_S_I_P_L		; add string pointer low byte to index
	STA $0104,X		; put on stack as return address low byte
				; (+4 to correct pointer, X is unchanged)
	LDA #$00		; clear A
	ADC D_S_I_P_H		; add string pointer high byte
	STA $0105,X		; put on stack as return address high byte
				; (+5 to correct pointer, X is unchanged)
	PLX  			; restore X
	PLY  			; restore Y
	PLA  			; restore A
	RTS

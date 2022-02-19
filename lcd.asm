DISP_DATA = $6001
DISP_DIR = $6003
B_DATA=$6000
B_DIR=$6002

E=%00010000
READ=%00100000
WRITE=%00000000
CMD=%00000000
CHAR=%01000000
DATA_WRITE=%11111111
DATA_READ=%11110000
HIGHNIB = $0211
LOWNIB = $0212
TEMPBYTE = $0210

LCD_LINE_1=$80
LCD_LINE_2=$C0
LCD_CLEAR=$01

LCD_HOME=$0213

	org $F000

port_init:
	pha
	lda #DATA_WRITE
	sta DISP_DIR
	sta B_DIR
	lda #$00
	sta DISP_DATA
	sta B_DATA
	pla
	rts
	
print:
	pha
	phx
	ldx #$00
print_next:
	lda LCD_HOME,x
	beq done_print
	jsr lcd_print
	inx
	jmp print_next
done_print:
	plx
	pla
	rts
	
lcd_init:
	pha
	
	lda #$33
	jsr lcd_instruction
	
	lda #$32
	jsr lcd_instruction
	
	lda #%00101000
	jsr lcd_instruction
		
	lda #%00001110 ; Display on; cursor on; blink off
	jsr lcd_instruction

	lda #%00000110 ; Increment and shift cursor; don't shift display
	jsr lcd_instruction

	lda #$00000001 ; Clear display
	jsr lcd_instruction
	
	
	pla
	rts


lcd_wait:
	pha
	lda #DATA_READ
	sta DISP_DIR
lcd_wait_loop:
	; get first nibble
	lda #(READ | CMD)
	sta DISP_DATA
	
	lda #(READ | CMD | E)
	sta DISP_DATA
	
	lda DISP_DATA
	; store first nibble
	pha
	
	;get second nibble
	lda #(READ | CMD)
	sta DISP_DATA
	
	lda #(READ | CMD | E)
	sta DISP_DATA
	
	lda DISP_DATA

	; the first nibble is all we care about
	; so get them back
	pla
	
	;test them to see if we are ready
	and %00001000
	bne lcd_wait_loop

	pla
	rts
	
	
lcd_instruction:
	pha
	
	lda #$F0
	sta B_DATA
	
	pla
	pha
	
	jsr split
	jsr lcd_wait
	
	lda #DATA_WRITE
	sta DISP_DIR
	
	lda HIGHNIB
	ora #(WRITE | CMD)
	sta DISP_DATA
	ora #E
	sta DISP_DATA

	lda #(WRITE | CMD)
	sta DISP_DATA
	
	lda LOWNIB
	ora #(WRITE | CMD)
	sta DISP_DATA
	ora #E
	sta DISP_DATA
	lda #(WRITE | CMD)
	sta DISP_DATA
	
	lda #$00
	sta B_DATA
	
	pla
	rts

	
lcd_print:
	pha
	
	lda #$0F
	sta B_DATA
	pla
	pha

	jsr split
	jsr lcd_wait
	
	lda #DATA_WRITE
	sta DISP_DIR
	
	lda HIGHNIB
	ora #(WRITE | CHAR)
	sta DISP_DATA
	ora #E
	sta DISP_DATA

	lda #(WRITE | CHAR)
	sta DISP_DATA
	
	lda LOWNIB
	ora #(WRITE | CHAR)
	sta DISP_DATA
	ora #E
	sta DISP_DATA
	lda #(WRITE | CHAR)
	sta DISP_DATA
	
	lda #$00
	sta B_DATA
	
	
	pla
	rts
	
split:
	pha
	sta TEMPBYTE
	and #%00001111
	sta LOWNIB
	lda TEMPBYTE
	and #%11110000
	lsr
	lsr
	lsr
	lsr
	sta HIGHNIB
	pla
	
	rts
	
hello:
	asciiz "Hello World!"
	byte $00

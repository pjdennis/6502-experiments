    include lcd.asm

	org $8000
start:
	
	ldx #$00
load_loop:
	lda hello,x
	beq store_zero
	sta LCD_HOME,x
	inx
	jmp load_loop

store_zero:
	lda #$00
	sta LCD_HOME,x
	
print_it:
	jsr port_init
	jsr lcd_init
	jsr print

end_loop:
	jmp end_loop

	org $FFFC
	word start

; Requires:
;   BF_ZERO_PAGE_BASE - location for zero page variables
;   bf_cells          - Address of 1024 bytes of cells
;   bf_cellsEnd       - Stop address for cells
;   bf_code           - Address of 24576 bytes of code
;   bf_codeEnd        - Stop address for code
;   bf_getchar        - Get char function
;   bf_putchar        - Put char function

; -----------------------------------------------------------------------------
; Implementation of the Brain F--k compiler in 6502 assembly.
;
; The goal of the challege is to create another Turing tarpit using the least
; number of instructions. But this time using the inherent simplicity of the
; Brain f--k VM to enforce it. Since Brain f--k is Turing complete you can (in
; theory) compute any problem with just the instructions required to write it.
;
; This version of the Brain f--k compiler compiles programs into 6502 machine
; code. When executed the machine code uses the underlying hardware as the code
; threading mechanism. Eliminating function calls creates a faster Brain f--k
; impementation than the prior versions.
;
; These optimizations further increase the speed:
; * [ and ] jump to the instruction following the matching brace, instead of
;   jumping to the matching brace which would needlessly retest the value of
;  the current cell
; * Multiple consecutive increments/decrements to cell values or to the data
;   pointer are consolidated into a single addition. The most efficient way of
;   updating the cell value or pointer is chosen based on the magnatude of the
;   consolidated value
; * The compiler keeps track of when the current cell value is reflected in the
;   Z flag so as to avoid reloading the current cell value unnecessarily
;
; Derived from prior version by Martin Heermance <mheermance@gmail.com>
;
; Updated to compile using vasm and without macros (as they're broken on my
; current vasm version: 1.8f
;
; Phil Dennis <pjdennis@gmail.com>
; -----------------------------------------------------------------------------


; Character set (ASCII)
AscLT		= $3C	; Character aliases for brain f commands.
AscGT		= $3E
AscPlus		= $2B
AscComma	= $2C
AscMinus	= $2D
AscDot		= $2E
AscLB		= $5B
AscRB		= $5D

bf_StateDefault	= $00	; Nothing pending
bf_StateModCell	= $01	; Collecting cell increments into delta
bf_StateModDptr	= $02	; Collecting pointer increments into delta
bf_StateCellCmp	= $03	; Current cell loaded for branch on Z flag

bf_cellsSize	= bf_cellsEnd - bf_cells
bf_codeSize 	= bf_codeEnd - bf_code

_bf_getch		= bf_getchar
_bf_putch		= bf_putchar


; Zero page variables
bf_dptr			= BF_ZERO_PAGE_BASE + $00 ; 2 bytes - word to hold the data pointer.
bf_iptr			= BF_ZERO_PAGE_BASE + $02 ; 2 bytes - word to hold the instruction pointer.
bf_temp			= BF_ZERO_PAGE_BASE + $04 ; 2 bytes - word to hold bf_temporary pointer.
bf_fixup		= BF_ZERO_PAGE_BASE + $06 ; 2 bytes - word to hold popped PC to bf_fixup forward branch.
bf_cptr			= BF_ZERO_PAGE_BASE + $08 ; 2 bytes - word to hold pointer for bf_code to copy.
bf_state		= BF_ZERO_PAGE_BASE + $0a ; 1 byte  - current parser bf_state
bf_count		= BF_ZERO_PAGE_BASE + $0b ; 2 bytes - bf_count cell or bf_dptr delta

BF_ZERO_PAGE_STOP	= BF_ZERO_PAGE_BASE + $0d


;
; Macros
;

	.include macros.inc


 	.macro emitCode,start,end
	lda #<(\start)
	ldx #>(\start)
	ldy #(\end)-(\start)
	jsr bf_copyCode
 	.endm


	.macro bf_emitByteFromMemoryUsingA,address
	lda \address
	jsr bf_emitByte
	.endm


	.macro bf_compile_and_run,bf_codeAddress
	lda #<(\bf_codeAddress)
	ldx #>(\bf_codeAddress)
	jmp bf_do_compile_and_run
	.endm


;
; Functions
;
doHello:
	; The classic hello world program.
	bf_compile_and_run helloWorld

doSierpinski:
	; The Sierpinski triangle program.
	bf_compile_and_run sierpinski

doGolden:
	; The Golden ratio program.
	bf_compile_and_run golden

doFibonacci:
	; The fibonacci program.
	bf_compile_and_run fibonacci

doLife:
	; The Conway game of life program.
	bf_compile_and_run life


; On entry A, X contains the address of the bf program
bf_do_compile_and_run:
	sta bf_iptr
	stx bf_iptr+1
	jsr bf_compile	; translate source into executable code
	jmp bf_code	; directly execute the code (tail call)


; compile scans the characters and produces a machine code stream.
bf_compile:
	; use bf_dptr as the index into the code
	sti16usingA bf_dptr,bf_code
	; Initialize parser state
	lda #bf_StateDefault
	sta bf_state
	stz16 bf_count
	; All programs start with memory cell initialization
	; Emit code to initialize the state of the data cells
	emitCode initCells,initCellsEnd

_bf_whileCompile:
	lda (bf_iptr)
	bne _bf_incCell
	jsr processState
	; Emit code to end the program
	emitCode endProgram,endProgramEnd
	rts


; Increment current cell '+'
_bf_incCell:
	cmp #AscPlus
	bne _bf_decCell

	lda bf_state
	cmp #bf_StateModCell
	beq .modifyingCell
	jsr processState
	lda #bf_StateModCell
	sta bf_state
.modifyingCell:
	inc bf_count
	jmp _bf_nextCompile


; Decrement current cell '-'
_bf_decCell:
	cmp #AscMinus
	bne _bf_decDptr

	cmp #bf_StateModCell
	beq .modifyingCell
	jsr processState
	lda #bf_StateModCell
	sta bf_state
.modifyingCell:
	dec bf_count
	jmp _bf_nextCompile


; Decrement bf_dptr '<'
_bf_decDptr:
	cmp #AscLT
	bne _bf_incDptr

	lda bf_state
	cmp #bf_StateModDptr
	beq .modifyingDptr
	jsr processState
	lda #bf_StateModDptr
	sta bf_state
.modifyingDptr:
	dec16usingA bf_count
	jmp _bf_nextCompile


; Increment bf_dptr '>'
_bf_incDptr:
	cmp #AscGT
	bne _bf_outputCell

	lda bf_state
	cmp #bf_StateModDptr
	beq .modifyingDptr
	jsr processState
	lda #bf_StateModDptr
	sta bf_state
.modifyingDptr:
	inc16 bf_count
	jmp _bf_nextCompile


; Output current cell '.'
_bf_outputCell:
	; no longer collecting increments so emit any pending code
	pha
	jsr processState
	pla

	cmp #AscDot
	bne _bf_inputCell

	; Emit code to output the current cell to the console
	emitCode outputCell,outputCellEnd
	lda #bf_StateDefault
	sta bf_state
	jmp _bf_nextCompile


; Input current cell ','
_bf_inputCell:
	cmp #AscComma
	bne _bf_leftBracket

	; Emit code to input from console into the current cell
	emitCode inputCell,inputCellEnd

	lda #bf_StateDefault
	sta bf_state
	jmp _bf_nextCompile


; Start loop '['
_bf_leftBracket:
	cmp #AscLB
	bne _bf_rightBracket
	
	lda bf_state
	cmp #bf_StateCellCmp
	beq .currentCellHasBeenComparedToZero
	; Emit code to load bf_dptr
	emitCode loadDptr,loadDptrEnd
.currentCellHasBeenComparedToZero:
	; Emit code to branch forward
	emitCode branchForward,branchForwardJumpInstruction+1
	; push current PC for later.
	push16usingA bf_dptr
	; Skip past reserved space for jump address
	; bf_dptr <- bf_dptr + 2
	add8iTo16usingA bf_dptr,2
	lda #bf_StateCellCmp
	sta bf_state
	jmp _bf_nextCompile


; End loop ']'
_bf_rightBracket:
	cmp #AscRB
	bne _bf_ignoreInput

	; Get the fixup address off the stack
	pop16usingA bf_fixup
	lda bf_state
	cmp #bf_StateCellCmp
	beq .currentCellHasBeenComparedToZero
	; Emit code to load bf_dptr
	emitCode loadDptr,loadDptrEnd
.currentCellHasBeenComparedToZero:
	; Emit code to branch backward
	emitCode branchBackward,branchBackwardJumpInstruction+1
	; Address of next instruction into bf_temp
	; bf_temp <- bf_dptr (word)
	copy16usingA bf_temp,bf_dptr
	; bf_temp <- bf_temp + 2 (word)
	add8iTo16usingA bf_temp,2
	; Fixup jump address for left bracket
	; Store low byte to fixup address
	lda bf_temp
	sta (bf_fixup)
	inc16 bf_fixup
	; Store high byte to fixup address
	lda bf_temp+1
	sta (bf_fixup)
	inc16 bf_fixup
	; Emit backwards jump address
	bf_emitByteFromMemoryUsingA bf_fixup
	bf_emitByteFromMemoryUsingA bf_fixup+1
	lda #bf_StateCellCmp
	sta bf_state
	jmp _bf_nextCompile


; All other characters are ignored
_bf_ignoreInput:
	; fall through


_bf_nextCompile:
	inc16 bf_iptr
	jmp _bf_whileCompile


; processState handles finalizing the current state prior to assigning a new state
processState:
	lda bf_state
	cmp #bf_StateDefault
	bne _bf_bf_stateCellCmp
	rts


; Current cell has been compared to 0. No further action needed
_bf_bf_stateCellCmp:
	cmp #bf_StateCellCmp
	bne _bf_bf_stateModCell
	rts


; Current cell has been modified. Emit code to do the modification
_bf_bf_stateModCell:
	cmp #bf_StateModCell
	bne _bf_bf_stateModDptr
	
	lda bf_count
	cmp #$01
	bne .decrement
	; Emit code to increment current cell
	emitCode incCell,incCellEnd
	jmp .done
.decrement:
	cmp #$ff
	bne .add
	; Emit code to decrement current cell
	emitCode decCell,decCellEnd
	jmp .done
.add:
	; Emit code to add (positive or negative value) to current cell
	emitCode modCell,modCellAdd+1
	bf_emitByteFromMemoryUsingA bf_count
	emitCode modCellAdd+2,modCellEnd
.done:
	; Reset bf_count
	stz bf_count
	lda #bf_StateCellCmp
	sta bf_state
	rts


; bf_dptr has been modified. Emit code to update based on bf_count (word)
_bf_bf_stateModDptr:
	; Choose the most efficient way of modifying bf_dptr
	lda bf_count+1
	bne .decrement
	lda bf_count
	cmp #$01
	bne .addPosByte
	; bf_count == 1: emit code to increment bf_dptr
	emitCode incDptr,incDptrEnd
	jmp .done
.addPosByte:
	; Emit code to add bf_count as a positive value < 256 to bf_dptr
	emitCode addDptrPosByte,addDptrPosByteAdd+1
	bf_emitByteFromMemoryUsingA bf_count
	emitCode addDptrPosByteAdd+2,addDptrPosByteEnd
	jmp .done
.decrement:
	lda bf_count+1
	cmp #$ff
	bne .addWord
	lda bf_count
	cmp #$ff
	bne .addNegByte
	; Emit code to decrement bf_dptr
	emitCode decDptr,decDptrEnd
	jmp .done
.addNegByte:
	; Emit code to add bf_count as a negative value >= -256 to bf_dptr
	emitCode addDptrNegByte,addDptrNegByteAdd+1
	bf_emitByteFromMemoryUsingA bf_count
	emitCode addDptrNegByteAdd+2,addDptrNegByteEnd
	jmp .done
.addWord:
	; Emit code to add bf_count as a signed word to bf_dptr
	emitCode addDptrWord,addDptrWordAddLow+1
	bf_emitByteFromMemoryUsingA bf_count
	emitCode addDptrWordAddLow+2,addDptrWordAddHigh+1
	bf_emitByteFromMemoryUsingA bf_count+1
	emitCode addDptrWordAddHigh+2,addDptrWordEnd
.done:
	; Reset bf_count
	stz16 bf_count
	lda #bf_StateDefault
	sta bf_state
	rts


; On entry A contains the byte to emit (store at the bf_dptr address)
; On exit bf_dptr has been incremented
bf_emitByte:
	sta (bf_dptr)
	inc16 bf_dptr
	rts


; Copy code to the output buffer
; On entry A, X contains the low, high bytes pointing to the bf_code
;          Y contains the number of bytes of bf_code to copy
bf_copyCode:
	sta bf_cptr
	stx bf_cptr+1
.loop:
	lda (bf_cptr)
	jsr bf_emitByte
	inc16 bf_cptr
	dey
	bne .loop
	rts


;
; These secions of code function as templates for compiled code to execute programs.
;

initCells:
	lda #<bf_cells
	sta bf_dptr
	lda #>bf_cells
	sta bf_dptr+1
.loop:
	lda #$00
	sta (bf_dptr)
	inc16 bf_dptr
	lda bf_dptr
	cmp #<bf_cellsEnd
	bne .loop
	lda bf_dptr+1
	cmp #>bf_cellsEnd
	bne .loop
	; set the bf_dptr back to the start of the cells.
	lda #<bf_cells
	sta bf_dptr
	lda #>bf_cells
	sta bf_dptr+1
initCellsEnd:


incCell:
	lda (bf_dptr)
	inc
	sta (bf_dptr)
incCellEnd:


decCell:
	lda (bf_dptr)
	dec
	sta (bf_dptr)
decCellEnd:


modCell:
	clc
	lda (bf_dptr)
modCellAdd:
	adc #0		; placeholder
	sta (bf_dptr)
modCellEnd:


decDptr:
	dec16usingA bf_dptr
decDptrEnd:


incDptr:
	inc16 bf_dptr
incDptrEnd:


addDptrNegByte:
	clc
	lda bf_dptr
addDptrNegByteAdd:
	adc #0		;placeholder
	sta bf_dptr
	bcs .over
	dec bf_dptr+1
.over:
addDptrNegByteEnd:


addDptrPosByte:
	clc
	lda bf_dptr
addDptrPosByteAdd:
	adc #0		; placeholder
	sta bf_dptr
	bcc .over
	inc bf_dptr+1
.over:
addDptrPosByteEnd:


addDptrWord:
	clc
	lda bf_dptr
addDptrWordAddLow:
	adc #0		; placeholder
	sta bf_dptr
	lda bf_dptr+1
addDptrWordAddHigh:
	adc #0		; placeholder
	sta bf_dptr+1
addDptrWordEnd:


outputCell:
	lda (bf_dptr)
	jsr _bf_putch
outputCellEnd:


inputCell:
	jsr _bf_getch
	sta (bf_dptr)
inputCellEnd:


loadDptr:
	lda (bf_dptr)
loadDptrEnd:


branchForward:
	bne bf_over	; Branch on data cell containing zero
branchForwardJumpInstruction:
	jmp 0		; placeholder
bf_over:


branchBackward:
	beq bb_over	; Branch on data cell containing zero
branchBackwardJumpInstruction:
	jmp 0		; placeholder
bb_over:


endProgram:
	rts		; return to calling program.
endProgramEnd:


;
; Sample programs
;

; Simple hello world program
helloWorld:
	.byte "++++++++"
	.byte "[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]"
	.byte ">>.>---.+++++++..+++.>>.<-.<.+++."
	.byte "------.--------.>>+.>++."
	.byte 0


; Fibonacci number generator by Daniel B Cristofani
; This program doesn't terminate; you will have to kill it.
fibonacci:
	.byte ">++++++++++>+>+["
	.byte "[+++++[>++++++++<-]>.<++++++[>--------<-]+<<<]>.>>["
        .byte "[-]<[>+<-]>>[<<+>+>-]<[>+<-[>+<-[>+<-[>+<-[>+<-[>+<-"
        .byte "[>+<-[>+<-[>+<-[>[-]>+>+<<<-[>+<-]]]]]]]]]]]+>>>"
	.byte "]<<<"
	.byte "]", 0


; Shows an ASCII representation of the Sierpinski triangle
; (c) 2016 Daniel B. Cristofani
sierpinski:
	.byte "++++++++[>+>++++<<-]>++>>+<[-[>>+<<-]+>>]>+["
	.byte "-<<<["
	.byte "->[+[-]+>++>>>-<<]<[<]>>++++++[<<+++++>>-]+<<++.[-]<<"
	.byte "]>.>+[>>]>+"
	.byte "]", 0


; Compute the "golden ratio". Because this number is infinitely long,
; this program doesn't terminate on its own. You will have to kill it.
golden:
	.byte "+>>>>>>>++>+>+>+>++<["
	.byte "  +["
	.byte "    --[++>>--]->--["
	.byte "      +["
	.byte "        +<+[-<<+]++<<[-[->-[>>-]++<[<<]++<<-]+<<]>>>>-<<<<"
	.byte "          <++<-<<++++++[<++++++++>-]<.---<[->.[-]+++++>]>[[-]>>]"
	.byte "          ]+>>--"
	.byte "      ]+<+[-<+<+]++>>"
	.byte "    ]<<<<[[<<]>>[-[+++<<-]+>>-]++[<<]<<<<<+>]"
	.byte "  >[->>[[>>>[>>]+[-[->>+>>>>-[-[+++<<[-]]+>>-]++[<<]]+<<]<-]<]]>>>>>>>"
	.byte "]", 0


; Conways game of life
;
; Adjust the number of '+' operations inside the parenthesis () to control the dimensions
; of the board.
life:
	.byte ">>>->+>+++++>(++++++++++)[[>>>+<<<-]>+++++>+>>+[<<+>>>>>+<<<-]<-]>>>>["
	.byte "  [>>>+>+<<<<-]+++>>+[<+>>>+>+<<<-]>>[>[[>>>+<<<-]<]<<++>+>>>>>>-]<-"
	.byte "]+++>+>[[-]<+<[>+++++++++++++++++<-]<+]>>["
	.byte "  [+++++++++.-------->>>]+[-<<<]>>>[>>,----------[>]<]<<["
	.byte "    <<<["
	.byte "      >--[<->>+>-<<-]<[[>>>]+>-[+>>+>-]+[<<<]<-]>++>[<+>-]"
	.byte "      >[[>>>]+[<<<]>>>-]+[->>>]<-[++>]>[------<]>+++[<<<]>"
	.byte "    ]<"
	.byte "  ]>["
	.byte "    -[+>>+>-]+>>+>>>+>[<<<]>->+>["
	.byte "      >[->+>+++>>++[>>>]+++<<<++<<<++[>>>]>>>]<<<[>[>>>]+>>>]"
	.byte "      <<<<<<<[<<++<+[-<<<+]->++>>>++>>>++<<<<]<<<+[-<<<+]+>->>->>"
	.byte "    ]<<+<<+<<<+<<-[+<+<<-]+<+["
	.byte "      ->+>[-<-<<[<<<]>[>>[>>>]<<+<[<<<]>-]]"
	.byte "      <[<[<[<<<]>+>>[>>>]<<-]<[<<<]]>>>->>>[>>>]+>"
	.byte "    ]>+[-<<[-]<]-["
	.byte "      [>>>]<[<<[<<<]>>>>>+>[>>>]<-]>>>[>[>>>]<<<<+>[<<<]>>-]>"
	.byte "    ]<<<<<<[---<-----[-[-[<->>+++<+++++++[-]]]]<+<+]>"
	.byte "  ]>>"
	.byte "]", 0


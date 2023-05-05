; Requires:
;   BF_ZERO_PAGE_BASE - location for zero page variables
;   cells             - Address of 1024 bytes of cells
;   cellsEnd          - Stop address for cells
;   code              - Address of 24576 bytes of code
;   codeEnd           - Stop address for code
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

StateDefault	= $00	; Nothing pending
StateModCell	= $01	; Collecting cell increments into delta
StateModDptr	= $02	; Collecting pointer increments into delta
StateCellCmp	= $03	; Current cell loaded for branch on Z flag

cellsSize	= cellsEnd - cells
codeSize 	= codeEnd - code

_getch		= bf_getchar
_putch		= bf_putchar


; Zero page variables
dptr			= BF_ZERO_PAGE_BASE + $00 ; 2 bytes - word to hold the data pointer.
iptr			= BF_ZERO_PAGE_BASE + $02 ; 2 bytes - word to hold the instruction pointer.
temp			= BF_ZERO_PAGE_BASE + $04 ; 2 bytes - word to hold temporary pointer.
fixup			= BF_ZERO_PAGE_BASE + $06 ; 2 bytes - word to hold popped PC to fixup forward branch.
cptr			= BF_ZERO_PAGE_BASE + $08 ; 2 bytes - word to hold pointer for code to copy.
state			= BF_ZERO_PAGE_BASE + $0a ; 1 byte  - current parser state
count			= BF_ZERO_PAGE_BASE + $0b ; 2 bytes - count cell or dptr delta

BF_ZERO_PAGE_STOP	= BF_ZERO_PAGE_BASE + $0d


;
; Macros
;

	.include macros.inc


 	.macro emitCode,start,end
	lda #<(\start)
	ldx #>(\start)
	ldy #(\end)-(\start)
	jsr copyCode
 	.endm


	.macro runBfProgram,codeAddress
	lda #<(\codeAddress)
	ldx #>(\codeAddress)
	jmp runProgram
	.endm


;
; Functions
;
doHello:
	; The classic hello world program.
	runBfProgram helloWorld

doSierpinski:
	; The Sierpinski triangle program.
	runBfProgram sierpinski

doGolden:
	; The Golden ratio program.
	runBfProgram golden

doFibonacci:
	; The fibonacci program.
	runBfProgram fibonacci

doLife:
	; The Conway game of life program.
	runBfProgram life


runProgram:
	sta iptr
	stx iptr+1
	jsr compile	; translate source into executable code
	jmp code	; directly execute the code


; compile scans the characters and produces a machine code stream.
compile:
	; use dptr as the index into the code
	sti16usingA dptr,code
	; Initialize parser state
	lda #StateDefault
	sta state
	stz16 count
	; All programs start with memory cell initialization
	; Emit code to initialize the state of the data cells
	emitCode initCells,initCellsEnd

_whileCompile:
	lda (iptr)
	bne _incCell
	jsr processState
	; Emit code to end the program
	emitCode endProgram,endProgramEnd
	rts


; Increment current cell '+'
_incCell:
	cmp #AscPlus
	bne _decCell

	lda state
	cmp #StateModCell
	beq .modifyingCell
	jsr processState
	lda #StateModCell
	sta state
.modifyingCell:
	inc count
	jmp _nextCompile


; Decrement current cell '-'
_decCell:
	cmp #AscMinus
	bne _decDptr

	cmp #StateModCell
	beq .modifyingCell
	jsr processState
	lda #StateModCell
	sta state
.modifyingCell:
	dec count
	jmp _nextCompile


; Decrement dptr '<'
_decDptr:
	cmp #AscLT
	bne _incDptr

	lda state
	cmp #StateModDptr
	beq .modifyingDptr
	jsr processState
	lda #StateModDptr
	sta state
.modifyingDptr:
	dec16usingA count
	jmp _nextCompile


; Increment dptr '>'
_incDptr:
	cmp #AscGT
	bne _outputCell

	lda state
	cmp #StateModDptr
	beq .modifyingDptr
	jsr processState
	lda #StateModDptr
	sta state
.modifyingDptr:
	inc16 count
	jmp _nextCompile


; Output current cell '.'
_outputCell:
	; no longer collecting increments so emit any pending code
	pha
	jsr processState
	pla

	cmp #AscDot
	bne _inputCell

	; Emit code to output the current cell to the console
	emitCode outputCell,outputCellEnd
	lda #StateDefault
	sta state
	jmp _nextCompile


; Input current cell ','
_inputCell:
	cmp #AscComma
	bne _leftBracket

	; Emit code to input from console into the current cell
	emitCode inputCell,inputCellEnd

	lda #StateDefault
	sta state
	jmp _nextCompile


; Start loop '['
_leftBracket:
	cmp #AscLB
	bne _rightBracket
	
	lda state
	cmp #StateCellCmp
	beq .currentCellHasBeenComparedToZero
	; Emit code to load dptr
	emitCode loadDptr,loadDptrEnd
.currentCellHasBeenComparedToZero:
	; Emit code to branch forward
	emitCode branchForward,branchForwardJumpInstruction+1
	; push current PC for later.
	push16usingA dptr
	; Skip past reserved space for jump address
	; dptr <- dptr + 2
	add8iTo16usingA dptr,2
	lda #StateCellCmp
	sta state
	jmp _nextCompile


; End loop ']'
_rightBracket:
	cmp #AscRB
	bne _ignoreInput

	; Get the fixup address off the stack
	pop16usingA fixup
	lda state
	cmp #StateCellCmp
	beq .currentCellHasBeenComparedToZero
	; Emit code to load dptr
	emitCode loadDptr,loadDptrEnd
.currentCellHasBeenComparedToZero:
	; Emit code to branch backward
	emitCode branchBackward,branchBackwardJumpInstruction+1
	; Address of next instruction into temp
	; temp <- dptr (word)
	copy16usingA temp,dptr
	; temp <- temp + 2 (word)
	add8iTo16usingA temp,2
	; Fixup jump address for left bracket
	; Store low byte to fixup address
	lda temp
	sta (fixup)
	inc16 fixup
	; Store high byte to fixup address
	lda temp+1
	sta (fixup)
	inc16 fixup
	; Store low byte
	lda fixup	; store backwards jump address
	jsr emitByte
	; Store high byte
	lda fixup+1
	jsr emitByte
	lda #StateCellCmp
	sta state
	jmp _nextCompile


; All other characters are ignored
_ignoreInput:
	; fall through


_nextCompile:
	inc16 iptr
	jmp _whileCompile


; processState handles finalizing the current state prior to assigning a new state
processState:
	lda state
	cmp #StateDefault
	bne _stateCellCmp
	rts


; Current cell has been compared to 0. No further action needed
_stateCellCmp:
	cmp #StateCellCmp
	bne _stateModCell
	rts


; Current cell has been modified. Emit code to do the modification
_stateModCell:
	cmp #StateModCell
	bne _stateModDptr
	
	lda count
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
	; Emit code to add (positive or negative value) to current cell (part 1)
	emitCode modCell,modCellAdd+1
	lda count
	jsr emitByte
	; Emit code to add (positive or negative value) to current cell (part 2)
	emitCode modCellAdd+2,modCellEnd
.done:
	; Reset count
	stz count
	lda #StateCellCmp
	sta state
	rts


; dptr has been modified. Emit code to update based on count (word)
_stateModDptr:
	; Choose the most efficient way of modifying dptr
	lda count+1
	bne .decrement
	lda count
	cmp #$01
	bne .addPosByte
	; count == 1: emit code to increment dptr
	emitCode incDptr,incDptrEnd
	jmp .done
.addPosByte:
	; Emit code to add count as a positive value < 256 to dptr (part 1)
	emitCode addDptrPosByte,addDptrPosByteAdd+1
	lda count
	jsr emitByte
	; Emit code to add count as a positive value < 256 to dptr (part 2)
	emitCode addDptrPosByteAdd+2,addDptrPosByteEnd
	jmp .done
.decrement:
	lda count+1
	cmp #$ff
	bne .addWord
	lda count
	cmp #$ff
	bne .addNegByte
	; Emit code to decrement dptr
	emitCode decDptr,decDptrEnd
	jmp .done
.addNegByte:
	; Emit code to add count as a negative value >= -256 to dptr (part 1)
	emitCode addDptrNegByte,addDptrNegByteAdd+1
	lda count
	jsr emitByte
	; Emit code to add count as a negative value >= -256 to dptr (part 2)
	emitCode addDptrNegByteAdd+2,addDptrNegByteEnd
	jmp .done
.addWord:
	; Emit code to add count as a signed word to dptr (part 1)
	emitCode addDptrWord,addDptrWordAddLow+1
	lda count
	jsr emitByte
	; Emit code to add count as a signed word to dptr (part 2)
	emitCode addDptrWordAddLow+2,addDptrWordAddHigh+1
	lda count+1
	jsr emitByte
	; Emit code to add count as a signed word to dptr (part 3)
	emitCode addDptrWordAddHigh+2,addDptrWordEnd
.done:
	; Reset count
	stz16 count
	lda #StateDefault
	sta state
	rts


; On entry A contains the byte to emit (store at the dptr address)
; On exit dptr has been incremented
emitByte:
	sta (dptr)
	inc16 dptr
	rts


; Copy code to the output buffer
; On entry A, X contains the low, high bytes pointing to the code
;          Y contains the number of bytes of code to copy
copyCode:
	sta cptr
	stx cptr+1
.loop:
	lda (cptr)
	jsr emitByte
	inc16 cptr
	dey
	bne .loop
	rts


;
; These secions of code function as templates for compiled code to execute programs.
;

initCells:
	lda #<cells
	sta dptr
	lda #>cells
	sta dptr+1
.loop:
	lda #$00
	sta (dptr)
	inc16 dptr
	lda dptr
	cmp #<cellsEnd
	bne .loop
	lda dptr+1
	cmp #>cellsEnd
	bne .loop
	; set the dptr back to the start of the cells.
	lda #<cells
	sta dptr
	lda #>cells
	sta dptr+1
initCellsEnd:


incCell:
	lda (dptr)
	inc
	sta (dptr)
incCellEnd:


decCell:
	lda (dptr)
	dec
	sta (dptr)
decCellEnd:


modCell:
	clc
	lda (dptr)
modCellAdd:
	adc #0		; placeholder
	sta (dptr)
modCellEnd:


decDptr:
	dec16usingA dptr
decDptrEnd:


incDptr:
	inc16 dptr
incDptrEnd:


addDptrNegByte:
	clc
	lda dptr
addDptrNegByteAdd:
	adc #0		;placeholder
	sta dptr
	bcs .over
	dec dptr+1
.over:
addDptrNegByteEnd:


addDptrPosByte:
	clc
	lda dptr
addDptrPosByteAdd:
	adc #0		; placeholder
	sta dptr
	bcc .over
	inc dptr+1
.over:
addDptrPosByteEnd:


addDptrWord:
	clc
	lda dptr
addDptrWordAddLow:
	adc #0		; placeholder
	sta dptr
	lda dptr+1
addDptrWordAddHigh:
	adc #0		; placeholder
	sta dptr+1
addDptrWordEnd:


outputCell:
	lda (dptr)
	jsr _putch
outputCellEnd:


inputCell:
	jsr _getch
	sta (dptr)
inputCellEnd:


loadDptr:
	lda (dptr)
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


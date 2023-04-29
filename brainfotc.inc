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
; Functions
;
do_hello:
	; The classic hello world program.
	lda #<helloWorld
	ldx #>helloWorld
	jmp runProgram

do_sierpinski:
	; The Sierpinski triangle program.
	lda #<sierpinski
	ldx #>sierpinski
	jmp runProgram

do_golden:
	; The Golden ratio program.
	lda #<golden
	ldx #>golden
	jmp runProgram

do_fibonacci:
	; The fibonacci program.
	lda #<fibonacci
	ldx #>fibonacci
	jmp runProgram

do_life:
	; The Conway game of life program.
	lda #<life
	ldx #>life
	jmp runProgram


runProgram:
	sta iptr
	stx iptr+1
	jsr compile	; translate source into executable code
	jmp code	; directly execute the code


; compile scans the characters and produces a machine code stream.
compile:
	lda #<code	; use dptr as the index into the code
	sta dptr
	lda #>code
	sta dptr+1
	
	; Initialize parser state
	lda #StateDefault
	sta state
	lda #0
	sta count
	sta count+1

	; All programs start with memory cell initialization
	; Emit code to initialize the state of the data cells
	lda #<initCells
	ldx #>initCells
	ldy #(initCellsEnd-initCells)
	jsr copyCode

_while_compile:
	lda (iptr)
	bne _incCell

	jsr processState

	; Emit code to end the program
	lda #<endProgram
	ldx #>endProgram
	ldy #(endProgramEnd-endProgram)
	jsr copyCode

	rts


; Increment current cell '+'
_incCell:
	cmp #AscPlus
	bne _decCell

	lda state
	cmp #StateModCell
	beq .over
	jsr processState
	lda #StateModCell
	sta state

.over:
	inc count
	jmp _next_compile


; Decrement current cell '-'
_decCell:
	cmp #AscMinus
	bne _decDptr

	cmp #StateModCell
	beq .over
	jsr processState
	lda #StateModCell
	sta state

.over:
	dec count
	jmp _next_compile


; Decrement dptr '<'
_decDptr:
	cmp #AscLT
	bne _incDptr

	lda state
	cmp #StateModDptr
	beq .over1
	jsr processState
	lda #StateModDptr
	sta state

.over1:
	lda count
	bne .over2
	dec count+1
.over2:

	dec count
	jmp _next_compile


; Increment dptr '>'
_incDptr:
	cmp #AscGT
	bne _outputCell

	lda state
	cmp #StateModDptr
	beq .over1
	jsr processState
	lda #StateModDptr
	sta state

.over1:
	inc count
	bne .over2
	inc count+1
.over2:

	jmp _next_compile


; Output current cell '.'
_outputCell:
	; no longer collecting increments so emit any pending code
	pha
	jsr processState
	pla

	cmp #AscDot
	bne _inputCell

	; Emit code to output the current cell to the console
	lda #<outputCell
	ldx #>outputCell
	ldy #(outputCellEnd-outputCell)
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next_compile


; Input current cell ','
_inputCell:
	cmp #AscComma
	bne _leftBracket

	; Emit code to input from console into the current cell
	lda #<inputCell
	ldx #>inputCell
	ldy #(inputCellEnd-inputCell)
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next_compile


; Start loop '['
_leftBracket:
	cmp #AscLB
	bne _rightBracket
	
	lda state
	cmp #StateCellCmp
	beq .over1

	; Emit code to load dptr
	lda #<loadDptr
	ldx #>loadDptr
	ldy #(loadDptrEnd-loadDptr)
	jsr copyCode

.over1:
	; Emit code to branch forward
	lda #<branchForward
	ldx #>branchForward
	ldy #(branchForwardJumpInstruction+1-branchForward)
	jsr copyCode

	lda dptr+1	; push current PC for later.
	pha
	lda dptr
	pha

	; Skip past reserved space for jump address
	; dptr <- dptr + 2
	clc
	lda dptr
	adc #2
	sta dptr
	bcc .over2
	inc dptr+1
.over2:

	lda #StateCellCmp
	sta state
	jmp _next_compile


; End loop ']'
_rightBracket:
	cmp #AscRB
	bne _ignoreInput

	; Get the fixup address off the stack
	pla
	sta fixup
	pla
	sta fixup+1

	lda state
	cmp #StateCellCmp
	beq .over1	; current cell already compared to 0

	; Emit code to load dptr
	lda #<loadDptr
	ldx #>loadDptr
	ldy #(loadDptrEnd-loadDptr)
	jsr copyCode

.over1:
	; Emit code to branch backward
	lda #<branchBackward
	ldx #>branchBackward
	ldy #(branchBackwardJumpInstruction+1-branchBackward)
	jsr copyCode

	; Address of next instruction into temp
	; temp <- dptr (word)
	lda dptr	
	sta temp
	lda dptr+1
	sta temp+1

	; temp <- temp + 2 (word)
	clc
	lda temp
	adc #2
	sta temp
	bcc .over2
	inc temp+1
.over2:

	; Fixup jump address for left bracket
	; Store low byte to fixup address
	lda temp
	sta (fixup)

	; fixup <- fixup + 1 (word)
	inc fixup
	bne .over3
	inc fixup+1
.over3:

	; Store high byte to fixup address
	lda temp+1
	sta (fixup)

	; fixup <- fixup + 1 (word)
	inc fixup
	bne .over4
	inc fixup+1
.over4:

	; Store low byte
	lda fixup	; store backwards jump address
	jsr emitByte

	; Store high byte
	lda fixup+1
	jsr emitByte

	lda #StateCellCmp
	sta state
	jmp _next_compile


; All other characters are ignored
_ignoreInput:
	; fall through


_next_compile:
	; iptr <- iptr + 1 (word)
	inc iptr
	bne .over
	inc iptr+1
.over:
	jmp _while_compile


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
	lda #<incCell
	ldx #>incCell
	ldy #(incCellEnd-incCell)
	jsr copyCode

	jmp .done
	
.decrement:
	cmp #$ff
	bne .add

	; Emit code to decrement current cell
	lda #<decCell
	ldx #>decCell
	ldy #(decCellEnd-decCell)
	jsr copyCode

	jmp .done

.add:
	; Emit code to add (positive or negative value) to current cell (part 1)
	lda #<modCell
	ldx #>modCell
	ldy #(modCellAdd+1-modCell)
	jsr copyCode

	lda count
	jsr emitByte

	; Emit code to add (positive or negative value) to current cell (part 2)
	lda #<(modCellAdd+2)
	ldx #>(modCellAdd+2)
	ldy #(modCellEnd-modCellAdd-2)
	jsr copyCode
	
.done:
	; Reset count
	lda #0
	sta count
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
	lda #<incDptr
	ldx #>incDptr
	ldy #(incDptrEnd-incDptr)
	jsr copyCode

	jmp .done

.addPosByte:
	; Emit code to add count as a positive value < 256 to dptr (part 1)
	lda #<addDptrPosByte
	ldx #>addDptrPosByte
	ldy #(addDptrPosByteAdd+1-addDptrPosByte)
	jsr copyCode

	lda count
	jsr emitByte

	; Emit code to add count as a positive value < 256 to dptr (part 2)
	lda #<(addDptrPosByteAdd+2)
	ldx #>(addDptrPosByteAdd+2)
	ldy #(addDptrPosByteEnd-addDptrPosByteAdd-2)
	jsr copyCode

	jmp .done

.decrement:
	lda count+1
	cmp #$ff
	bne .addWord

	lda count
	cmp #$ff
	bne .addNegByte

	; Emit code to decrement dptr
	lda #<decDptr
	ldx #>decDptr
	ldy #(decDptrEnd-decDptr)
	jsr copyCode

	jmp .done

.addNegByte:
	; Emit code to add count as a negative value >= -256 to dptr (part 1)
	lda #<addDptrNegByte
	ldx #>addDptrNegByte
	ldy #(addDptrNegByteAdd+1-addDptrNegByte)
	jsr copyCode

	lda count
	jsr emitByte

	; Emit code to add count as a negative value >= -256 to dptr (part 2)
	lda #<(addDptrNegByteAdd+2)
	ldx #>(addDptrNegByteAdd+2)
	ldy #(addDptrNegByteEnd-addDptrNegByteAdd-2)
	jsr copyCode

	jmp .done

.addWord:
	; Emit code to add count as a signed word to dptr (part 1)
	lda #<addDptrWord
	ldx #>addDptrWord
	ldy #(addDptrWordAddLow+1-addDptrWord)
	jsr copyCode

	lda count
	jsr emitByte

	; Emit code to add count as a signed word to dptr (part 2)
	lda #<(addDptrWordAddLow+2)
	ldx #>(addDptrWordAddLow+2)
	ldy #(addDptrWordAddHigh+1-addDptrWordAddLow-2)
	jsr copyCode

	lda count+1
	jsr emitByte

	; Emit code to add count as a signed word to dptr (part 3)
	lda #<(addDptrWordAddHigh+2)
	ldx #>(addDptrWordAddHigh+2)
	ldy #(addDptrWordEnd-addDptrWordAddHigh-2)
	jsr copyCode

.done:
	; Reset count
	lda #0
	sta count
	sta count+1
	lda #StateDefault
	sta state
	rts


; On entry A contains the byte to emit (store at the dptr address)
; On exit dptr has been incremented
emitByte:
	sta (dptr)

	; dptr <- dptr + 1 (word)
	inc dptr
	bne .over
	inc dptr+1
.over:
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

	inc cptr
	bne .over
	inc cptr+1
.over:

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

	inc dptr
	bne .over
	inc dptr+1
.over:
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
	lda dptr
	bne .over
	dec dptr+1
.over:
	dec dptr
decDptrEnd:


incDptr:
	inc dptr
	bne .over
	inc dptr+1
.over:
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


; Sample programs

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


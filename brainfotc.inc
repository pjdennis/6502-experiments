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

;
; Aliases
;

; Character set (ASCII)
AscLT		= $3C	; Character aliases for brain f commands.
AscGT		= $3E
AscQues		= $3F
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
main:
	; The classic hello world program.
	;lda #<helloWorld
	;ldx #>helloWorld
	;jsr runProgram

	; The Sierpinski triangle program.
	;lda #<sierpinski
	;ldx #>sierpinski
	;jsr runProgram

	; The Golden ratio program.
	;lda #<golden
	;ldx #>golden
	;jsr runProgram

	; The fibonacci program.
	;lda #<fibonacci
	;ldx #>fibonacci
	;jsr runProgram

	; The Conway game of life program.
	lda #<life
	ldx #>life
	jsr runProgram

	rts


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

	; All programs start with memory cell initialization.

; Emit Code
	lda #<initCells
	ldx #>initCells
	ldy #(initCellsEnd-initCells)
	jsr copyCode

_while_compile:
	lda (iptr)
	bne _incCell

	jsr processState

; Emit code
	lda #<endProgram
	ldx #>endProgram
	ldy #(endProgramEnd-endProgram)
	jsr copyCode

	rts

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

_outputCell:
	; no longer collecting increments so emit any pending code
	pha
	jsr processState
	pla

	cmp #AscDot
	bne _inputCell

; Emit Code
	lda #<outputCell
	ldx #>outputCell
	ldy #(outputCellEnd-outputCell)
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next_compile

_inputCell:
	cmp #AscComma
	bne _leftBracket

; Emit Code
	lda #<inputCell
	ldx #>inputCell
	ldy #(inputCellEnd-inputCell)
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next_compile

_leftBracket:
	cmp #AscLB
	bne _rightBracket
	
	lda state
	cmp #StateCellCmp
	beq .over1

; Emit Code
	lda #<branchForward
	ldx #>branchForward
	ldy #(branchForwardAfterLoad-branchForward)
	jsr copyCode

.over1:

; Emit Code
	lda #<branchForwardAfterLoad
	ldx #>branchForwardAfterLoad
	ldy #(branchForwardJumpInstruction+1-branchForwardAfterLoad)
	jsr copyCode

	lda dptr+1	; push current PC for later.
	pha
	lda dptr
	pha

; skip past reserved space for jump address
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

_rightBracket:
	cmp #AscRB
	bne _debugOut

	pla		; get the fixup address off the stack
	sta fixup
	pla
	sta fixup+1

	lda state
	cmp #StateCellCmp
	beq .over1

; Emit Code
	lda #<branchBackward
	ldx #>branchBackward
	ldy #(branchBackwardAfterLoad-branchBackward)
	jsr copyCode

.over1:

; Emit Code
	lda #<branchBackwardAfterLoad
	ldx #>branchBackwardAfterLoad
	ldy #(branchBackwardJumpInstruction+1-branchBackwardAfterLoad)
	jsr copyCode

	lda dptr	; address of next instruction into temp
	sta temp
	lda dptr+1
	sta temp+1

	clc
	lda temp
	adc #2
	sta temp
	bcc .over2
	inc temp+1
.over2:
	
	lda temp	; fixup jump address for left bracket
	sta (fixup)

	inc fixup
	bne .over3
	inc fixup+1
.over3:

	lda temp+1
	sta (fixup)

	inc fixup
	bne .over4
	inc fixup+1
.over4:

	lda fixup	; store backwards jump address
	sta (dptr)

	inc dptr
	bne .over5
	inc dptr+1
.over5:

	lda fixup+1
	sta (dptr)

	inc dptr
	bne .over6
	inc dptr+1
.over6:

	lda #StateCellCmp
	sta state
	jmp _next_compile

_debugOut:
	cmp #AscQues
	bne _ignoreInput


; Emit Code
	lda #<debugOut
	ldx #>debugOut
	ldy #(debugOutEnd-debugOut)
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next_compile

_ignoreInput:		; all other characters are ignored

_next_compile:
	inc iptr
	bne .over
	inc iptr+1
.over:
	jmp _while_compile


processState:
	lda state
	cmp #StateDefault
	bne _stateCellCmp

	rts

_stateCellCmp:
	cmp #StateCellCmp
	bne _stateModCell

	rts

_stateModCell:
	cmp #StateModCell
	bne _stateModDptr
	
	lda count
	cmp #$01
	bne .decrement
	; increment current cell

; Emit Code
	lda #<incCell
	ldx #>incCell
	ldy #(incCellEnd-incCell)
	jsr copyCode

	jmp .done
	
.decrement:
	cmp #$ff
	bne .add
	; decrement current cell

; Emit Code
	lda #<decCell
	ldx #>decCell
	ldy #(decCellEnd-decCell)
	jsr copyCode

	jmp .done

.add:
	; add to current cell

; Emit Code
	lda #<modCell
	ldx #>modCell
	ldy #(modCellAdd+1-modCell)
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over
	inc dptr+1
.over:

; Emit Code
	lda #<(modCellAdd+2)
	ldx #>(modCellAdd+1)
	ldy #(modCellEnd-modCellAdd-2)
	jsr copyCode
	
.done:
	lda #0
	sta count
	lda #StateCellCmp
	sta state
	rts

_stateModDptr:
	lda count+1
	bne .decrement

	; Choose most efficient way of modifying data pointer
	lda count
	cmp #$01
	bne .addPosByte
	; increment data pointer

; Emit Code
	lda #<incDptr
	ldx #>incDptr
	ldy #(incDptrEnd-incDptr)
	jsr copyCode

	jmp .done

.addPosByte:
	; add positive value < 256 to data pointer

; Emit Code
	lda #<addDptrPosByte
	ldx #>addDptrPosByte
	ldy #(addDptrPosByteAdd+1-addDptrPosByte)
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over1
	inc dptr+1
.over1:

; Emit Code
	lda #<(addDptrPosByteAdd+2)
	ldx #>(addDptrPosByteAdd+2)
	ldy #(addDptrPosByteEnd-addDptrPosByteAdd-2)
	jsr copyCode

	jmp .done

.decrement:
	lda count+1
	cmp #$ff
	bne .add

	lda count
	cmp #$ff
	bne .addNegByte
	; decrement data pointer

; Emit Code
	lda #<decDptr
	ldx #>decDptr
	ldy #(decDptrEnd-decDptr)
	jsr copyCode

	jmp .done

.addNegByte:
	; subract negative value >= -256 from data pointer

; Emit Code
	lda #<addDptrNegByte
	ldx #>addDptrNegByte
	ldy #(addDptrNegByteAdd+1-addDptrNegByte)
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over2
	inc dptr+1
.over2:

; Emit Code
	lda #<(addDptrNegByteAdd+2)
	ldx #>(addDptrNegByteAdd+2)
	ldy #(addDptrNegByteEnd-addDptrNegByteAdd-2)
	jsr copyCode

	jmp .done

.add:
	; add signed value to data pointer

; Emit Code
	lda #<modDptr
	ldx #>modDptr
	ldy #(modDptrAddLow+1-modDptr)
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over3
	inc dptr+1
.over3:

; Emit Code
	lda #<(modDptrAddLow+2)
	ldx #>(modDptrAddLow+2)
	ldy #(modDptrAddHigh+1-modDptrAddLow-2)
	jsr copyCode

	lda count+1
	sta (dptr)

	inc dptr
	bne .over4
	inc dptr+1
.over4:

; Emit Code
	lda #<(modDptrAddHigh+2)
	ldx #>(modDptrAddHigh+2)
	ldy #(modDptrEnd-modDptrAddHigh-2)
	jsr copyCode

.done:
	lda #0
	sta count
	sta count+1
	lda #StateDefault
	sta state
	rts


; Copy code to the output buffer
; On entry A, X contains the low, high bytes pointing to the code
;          Y contains the number of bytes of code to copy
copyCode:
	sta cptr
	stx cptr+1
.loop:
	lda (cptr)
	sta (dptr)

	inc cptr
	bne .over1
	inc cptr+1
.over1:
	inc dptr
	bne .over2
	inc dptr+1
.over2:
	dey
	bne .loop
	
	rts


;
; These secions of code function as the threaded code to execute programs.
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


modDptr:
	clc
	lda dptr
modDptrAddLow:
	adc #0		; placeholder
	sta dptr
	lda dptr+1
modDptrAddHigh:
	adc #0		; placeholder
	sta dptr+1
modDptrEnd:


outputCell:
	lda (dptr)
	jsr _putch
outputCellEnd:


inputCell:
	jsr _getch
	sta (dptr)
inputCellEnd:


branchForward:
	lda (dptr)
branchForwardAfterLoad:
	bne bf_over	; Branch on data cell containing zero
branchForwardJumpInstruction:
	jmp 0		; placeholder
bf_over:


branchBackward:
	lda (dptr)
branchBackwardAfterLoad:
	beq bb_over	; Branch on data cell containing zero
branchBackwardJumpInstruction:
	jmp 0		; placeholder
bb_over:


debugOut:
	brk		; unimplemented for now
debugOutEnd:


endProgram:
	rts		; return to calling program.
endProgramEnd:


; Sample programs

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


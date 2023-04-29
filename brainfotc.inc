; Requires:
;   BF_ZERO_PAGE_BASE - location for zero page variables
;   cells             - Address of 1024 bytes of cells
;   cellsEnd          - Stop address for cells
;   code              - Address of 24576 bytes of code
;   codeEnd           - Stop address for code

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

; Zero page variables
dptr			= BF_ZERO_PAGE_BASE + $00 ; 2 bytes - word to hold the data pointer.
iptr			= BF_ZERO_PAGE_BASE + $02 ; 2 bytes - word to hold the instruction pointer.
temp			= BF_ZERO_PAGE_BASE + $04 ; 2 bytes - word to hold temporary pointer.
fixup			= BF_ZERO_PAGE_BASE + $06 ; 2 bytes - word to hold popped PC to fixup forward branch.
cptr			= BF_ZERO_PAGE_BASE + $08 ; 2 bytes - word to hold pointer for code to copy.
ccnt			= BF_ZERO_PAGE_BASE + $0a ; 1 byte  - byte to hold count of code to copy.
state			= BF_ZERO_PAGE_BASE + $0b ; 1 byte  - current parser state
count			= BF_ZERO_PAGE_BASE + $0c ; 2 bytes - count cell or dptr delta

BF_ZERO_PAGE_STOP	= BF_ZERO_PAGE_BASE + $0e


;
; Functions
;
main:
	; Set the instruction pointer to the classic hello world program.
	lda #<helloWorld
	sta iptr
	lda #>helloWorld
	sta iptr+1
	jsr runProgram

	; set the instruction pointer to the Sierpinski triangle program.
	lda #<sierpinski
	sta iptr
	lda #>sierpinski
	sta iptr+1
	jsr runProgram

	; set the instruction pointer to the Golden ratio program.
	lda #<golden
	sta iptr
	lda #>golden
	sta iptr+1
	jsr runProgram
	brk

runProgram:
	jsr compile	; translate source into executable code
	jmp code	; directly execute the code

; compile scans the characters and produces a machine code stream.
compile:
.scope
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
	sta cptr
	lda #>initCells
	sta cptr+1
	lda #initCellsEnd-initCells
	sta ccnt
	jsr copyCode

_while:	lda (iptr)
	bne _incCell

	jsr processState

; Emit code
	lda #<endProgram
	sta cptr
	lda #>endProgram
	sta cptr+1
	lda #endProgramEnd-endProgram
	sta ccnt
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
	jmp _next

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
	jmp _next

_decDptr:
	cmp #AscLT
	bne _incDptr

	lda state
	cmp #StateModDptr
	beq .decrement
	jsr processState
	lda #StateModDptr
	sta state
.decrement:
	lda count
	bne .over
	dec count+1
.over:
	dec count
	jmp _next

_incDptr:
	cmp #AscGT
	bne _outputCell

	lda state
	cmp #StateModDptr
	beq .increment
	jsr processState
	lda #StateModDptr
	sta state
.increment:
	inc count
	bne .over
	inc count+1
.over:
	jmp _next

_outputCell:
	; no longer collecting increments so emit any pending code
	pha
	jsr processState
	pla

	cmp #AscDot
	bne _inputCell

; Emit Code
	lda #<outputCell
	sta cptr
	lda #>outputCell
	sta cptr+1
	lda #outputCellEnd-outputCell
	sta ccnt
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next

_inputCell:
	cmp #AscComma
	bne _leftBracket


; Emit Code
	lda #<inputCell
	sta cptr
	lda #>inputCell
	sta cptr+1
	lda #inputCellEnd-inputCell
	sta ccnt
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next

_leftBracket:
	cmp #AscLB
	bne _rightBracket
	
	lda state
	cmp #StateCellCmp
	beq .over

; Emit Code
	lda #<branchForward
	sta cptr
	lda #>branchForward
	sta cptr+1
	lda #branchForwardAfterLoad-branchForward
	sta ccnt
	jsr copyCode

.over:

; Emit Code
	lda #<branchForwardAfterLoad
	sta cptr
	lda #>branchForwardAfterLoad
	sta cptr+1
	lda #branchForwardJumpInstructions+1-branchForwardAfterLoad
	sta ccnt
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
	bcc .over
	inc dptr+1
.over:

	lda #StateCellCmp
	sta state
	jmp _next

_rightBracket:
	cmp #AscRB
	bne _debugOut

	pla		; get the fixup address off the stack
	sta fixup
	pla
	sta fixup+1

	lda state
	cmp #StateCellCmp
	beq .over

; Emit Code
	lda #<branchBackward
	sta cptr
	lda #>branchBackward
	sta cptr+1
	lda #branchBackwardAfterLoad-branchBackward
	sta ccnt
	jsr copyCode

.over:

; Emit Code
	lda #<branchBackwardAfterLoad
	sta cptr
	lda #>branchBackwardAfterLoad
	sta cptr+1
	lda #branchBackwardJumpInstruction+1-branchBackwardAfterLoad
	sta ccnt
	jsr copyCode

	lda dptr	; address of next instruction into temp
	sta temp
	lda dptr+1
	sta temp+1

	clc
	lda temp
	adc #2
	sta temp
	bcc .over
	inc temp+1
.over:
	
	lda temp	; fixup jump address for left bracket
	sta (fixup)

	inc fixup
	bne .over1
	inc fixup+1
.over1:

	lda temp+1
	sta (fixup)

	inc fixup
	bne .over2
	inc fixup+1
.over2:

	lda fixup	; store backwards jump address
	sta (dptr)

	inc dptr
	bne .over3
	inc dptr+1
.over3:

	lda fixup+1
	sta (dptr)

	inc dptr
	bne .over4
	inc dptr+1
.over4:	

	lda #StateCellCmp
	sta state
	jmp _next

_debugOut:
	cmp #AscQues
	bne _ignoreInput


; Emit Code
	lda #<debugOut
	sta cptr
	lda #>debugOut
	sta cptr+1
	lda #debugOutEnd-debugOut
	sta ccnt
	jsr copyCode

	lda #StateDefault
	sta state
	jmp _next

_ignoreInput:		; all other characters are ignored

_next:
	inc iptr
	bne .over
	inc iptr+1
.over:
	jmp _while
.scend

processState:
.scope
	lda state
	cmp #StateDefault
	bne _stateCellCmp

	rts

_stateCellCmp:
	cmp #StateCellCmp
	bne _stateModCell

	rts

_stateModCell:
.scope
	cmp #StateModCell
	bne _stateModDptr
	
	lda count
	cmp #$01
	bne _decrement
	; increment current cell

; Emit Code
	lda #<incCell
	sta cptr
	lda #>incCell
	sta cptr+1
	lda #incCellEnd-incCell
	sta ccnt
	jsr copyCode

	jmp _done
	
_decrement:
	cmp #$ff
	bne _add
	; decrement current cell

; Emit Code
	lda #<decCell
	sta cptr
	lda #>decCell
	sta cptr+1
	lda #decCellEnd-decCell
	sta ccnt
	jsr copyCode

	jmp _done

_add:
	; add to current cell

; Emit Code
	lda #<modCell
	sta cptr
	lda #>modCell
	sta cptr+1
	lda #modCellAdd+1-modCell
	sta ccnt
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over
	inc dptr+1
.over:

; Emit Code
	lda #<modCellAdd+2
	sta cptr
	lda #>modCellAdd+1
	sta cptr+1
	lda #modCellEnd-modCellAdd-2
	sta ccnt
	jsr copyCode
	
_done:
	lda #0
	sta count
	lda #StateCellCmp
	sta state
	rts
.scend

_stateModDptr:
.scope
	lda count+1
	bne _decrement

	; Choose most efficient way of modifying data pointer
	lda count
	cmp #$01
	bne _addPosByte
	; increment data pointer

; Emit Code
	lda #<incDptr
	sta cptr
	lda #>incDptr
	sta cptr+1
	lda #incDptrEnd-incDptr
	sta ccnt
	jsr copyCode

	jmp _done

_addPosByte:
	; add positive value < 256 to data pointer

; Emit Code
	lda #<addDptrPosByte
	sta cptr
	lda #>addDptrPosByte
	sta cptr+1
	lda #addDptrPosByteAdd+1-addDptrPosByte
	sta ccnt
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over
	inc dptr+1
.over:

; Emit Code
	lda #<addDptrPosByteAdd+2
	sta cptr
	lda #>addDptrPosByteAdd+2
	sta cptr+1
	lda #addDptrPosByteEnd-addDptrPosByteAdd-2
	sta ccnt
	jsr copyCode

	jmp _done

_decrement:
	lda count+1
	cmp #$ff
	bne _add

	lda count
	cmp #$ff
	bne _addNegByte
	; decrement data pointer

; Emit Code
	lda #<decDptr
	sta cptr
	lda #>decDptr
	sta cptr+1
	lda #decDptrEnd-decDptr
	sta ccnt
	jsr copyCode

	jmp _done

_addNegByte:
	; subract negative value >= -256 from data pointer

; Emit Code
	lda #<addDptrNegByte
	sta cptr
	lda #>addDptrNegByte
	sta cptr+1
	lda #addDptrNegByteAdd+1-addDptrNegByte
	sta ccnt
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over
	inc dptr+1
over:

; Emit Code
	lda #<addDptrNegByteAdd+2
	sta cptr
	lda #>addDptrNegByteAdd+2
	sta cptr+1
	lda #addDptrNegByteEnd-addDptrNegByteAdd-2
	sta ccnt
	jsr copyCode

	jmp _done

_add:
	; add signed value to data pointer

; Emit Code
	lda #<modDptr
	sta cptr
	lda #>modDptr
	sta cptr+1
	lda #modDptrAddLow+1-modDptr
	sta ccnt
	jsr copyCode

	lda count
	sta (dptr)

	inc dptr
	bne .over1
	inc dptr+1
.over1:

; Emit Code
	lda #<modDptrAddLow+2
	sta cptr
	lda #>modDptrAddLow+2
	sta cptr+1
	lda #modDptrAddHigh+1-modDptrAddLow-2
	sta ccnt
	jsr copyCode

	lda count+1
	sta (dptr)

	inc dptr
	bne .over2
	inc dptr+1
.over2:

; Emit Code
	lda #<modDptrAddHigh+2
	sta cptr
	lda #>modDptrAddHigh+2
	sta cptr+1
	lda #modDptrEnd-modDptrAddHigh-2
	sta ccnt
	jsr copyCode

_done:
	lda #0
	sta count
	sta count+1
	lda #StateDefault
	sta state
	rts
.scend
.scend

copyCode:
_loop:
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

	dec ccnt
	bne _loop
	
	rts

;
; These secions of code function as the threaded code to execute programs.
;

initCells:
	lda #<cells
	sta dptr
	lda #>cells
	sta dptr+1
.scope
_loop:
	lda #$00
	sta (dptr)

	inc dptr
	bne .over
	inc dptr+1
.over:

	lda dptr+1
	cmp #>cellsEnd
	bne _loop

	; set the dptr back to the start of the cells.
	lda #<cells
	sta dptr
	lda #>cells
	sta dptr+1
.scend
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
	.byte "]",0

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
	.byte "]"

; conio functions unique to each platform.
.alias _py65_putc	$f001	; Definitions for the py65mon emulator
.alias _py65_getc	$f004

_getch:
.scope
*	lda _py65_getc
	beq -
	cmp #13		; convert CR to LF so as to be compliant on Windows
	bne +
	lda #10
*	rts
.scend

_putch:
.scope
	sta _py65_putc
	rts
.scend

; Interrupt handler for RESET button, also boot sequence.
; Note: This doesn't count for the restricted instruction challenge as
; these steps are required to set the hardware to a known state.
.scope
resetv:
	sei		; diable interupts, until interupt vectors are set.
	cld		; clear decimal mode
	ldx #$FF	; reset stack pointer
	txs

	lda #$00	; clear all three registers
	tax
	tay

	pha		; clear all flags
	plp
	jmp main	; go to monitor or main program initialization.
.scend

; redirect the NMI interrupt vector here to be safe, but this 
; should never be reached for py65mon.
irqv:
nmiv:
panic:
	brk

; Interrupt vectors.
.advance $FFFA

.word nmiv		; NMI vector 
.word resetv		; RESET vector
.word irqv		; IRQ vector

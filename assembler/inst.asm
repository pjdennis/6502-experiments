IHASHTABL
  DATA $00 $00 $00 $00 <i_BCC $00 $00 $00
  DATA $00 $00 $00 <i_TAY <i_ADC# $00 $00 $00
  DATA $00 <i_TYA <i_LSRA $00 $00 $00 $00 $00
  DATA $00 <i_LDX# $00 $00 $00 $00 $00 $00
  DATA <i_LDAZ(),Y <i_ORAZ <i_LDA# $00 $00 $00 $00 <i_JSR
  DATA $00 <i_BCS $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 <i_BEQ $00 $00 $00
  DATA $00 <i_CMP# $00 $00 $00 $00 <i_BITZ $00
  DATA <i_INCZ $00 $00 $00 $00 $00 <i_LDAZ,X $00
  DATA $00 $00 $00 $00 $00 $00 $00 <i_INY
  DATA $00 $00 $00 <i_ASLA $00 $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 <i_PLA $00 $00 $00 $00 <i_STAZ
  DATA $00 $00 <i_BMI $00 $00 $00 $00 $00
  DATA $00 $00 <i_STA,X $00 $00 $00 $00 $00
  DATA $00 $00 <i_CMP,Y $00 <i_LDY# $00 <i_JMP $00
  DATA $00 $00 $00 $00 $00 $00 <i_INX $00
  DATA $00 <i_CLC $00 <i_BPL $00 $00 $00 $00
  DATA $00 $00 $00 $00 <i_STA,Y $00 $00 $00
  DATA <i_STAZ,X $00 $00 <i_DATA $00 $00 $00 $00
  DATA $00 $00 $00 $00 <i_SBCZ <i_BRK $00 <i_RTS
  DATA <i_STA <i_AND# $00 $00 $00 $00 <i_LDAZ $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 <i_LDA,X $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 <i_EORZ $00 $00 <i_BNE $00 $00 $00
  DATA $00 $00 $00 $00 <i_PHA $00 $00 <i_LDA,Y
  DATA $00 <i_SEC $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 <i_ADCZ $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 <i_STAZ(),Y
  DATA $00 $00 $00 $00 $00 $00 $00 $00
IHASHTABH
  DATA $00 $00 $00 $00 >i_BCC $00 $00 $00
  DATA $00 $00 $00 >i_TAY >i_ADC# $00 $00 $00
  DATA $00 >i_TYA >i_LSRA $00 $00 $00 $00 $00
  DATA $00 >i_LDX# $00 $00 $00 $00 $00 $00
  DATA >i_LDAZ(),Y >i_ORAZ >i_LDA# $00 $00 $00 $00 >i_JSR
  DATA $00 >i_BCS $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 >i_BEQ $00 $00 $00
  DATA $00 >i_CMP# $00 $00 $00 $00 >i_BITZ $00
  DATA >i_INCZ $00 $00 $00 $00 $00 >i_LDAZ,X $00
  DATA $00 $00 $00 $00 $00 $00 $00 >i_INY
  DATA $00 $00 $00 >i_ASLA $00 $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 >i_PLA $00 $00 $00 $00 >i_STAZ
  DATA $00 $00 >i_BMI $00 $00 $00 $00 $00
  DATA $00 $00 >i_STA,X $00 $00 $00 $00 $00
  DATA $00 $00 >i_CMP,Y $00 >i_LDY# $00 >i_JMP $00
  DATA $00 $00 $00 $00 $00 $00 >i_INX $00
  DATA $00 >i_CLC $00 >i_BPL $00 $00 $00 $00
  DATA $00 $00 $00 $00 >i_STA,Y $00 $00 $00
  DATA >i_STAZ,X $00 $00 >i_DATA $00 $00 $00 $00
  DATA $00 $00 $00 $00 >i_SBCZ >i_BRK $00 >i_RTS
  DATA >i_STA >i_AND# $00 $00 $00 $00 >i_LDAZ $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 >i_LDA,X $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 >i_EORZ $00 $00 >i_BNE $00 $00 $00
  DATA $00 $00 $00 $00 >i_PHA $00 $00 >i_LDA,Y
  DATA $00 >i_SEC $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 >i_ADCZ $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 $00
  DATA $00 $00 $00 $00 $00 $00 $00 >i_STAZ(),Y
  DATA $00 $00 $00 $00 $00 $00 $00 $00
i_BCC
  DATA $0000 "BCC" $00 $00 $90
i_TAY
  DATA $0000 "TAY" $00 $00 $A8
i_ADC#
  DATA $0000 "ADC#" $00 $00 $69
i_TYA
  DATA $0000 "TYA" $00 $00 $98
i_LSRA
  DATA $0000 "LSRA" $00 $00 $4A
i_LDX#
  DATA $0000 "LDX#" $00 $00 $A2
i_LDAZ(),Y
  DATA $0000 "LDAZ(),Y" $00 $00 $B1
i_ORAZ
  DATA $0000 "ORAZ" $00 $00 $05
i_LDA#
  DATA $0000 "LDA#" $00 $00 $A9
i_JSR
  DATA $0000 "JSR" $00 $00 $20
i_BCS
  DATA $0000 "BCS" $00 $00 $B0
i_BEQ
  DATA $0000 "BEQ" $00 $00 $F0
i_CMP#
  DATA $0000 "CMP#" $00 $00 $C9
i_BITZ
  DATA $0000 "BITZ" $00 $00 $24
i_INCZ
  DATA $0000 "INCZ" $00 $00 $E6
i_LDAZ,X
  DATA $0000 "LDAZ,X" $00 $00 $B5
i_INY
  DATA $0000 "INY" $00 $00 $C8
i_ASLA
  DATA $0000 "ASLA" $00 $00 $0A
i_PLA
  DATA $0000 "PLA" $00 $00 $68
i_STAZ
  DATA $0000 "STAZ" $00 $00 $85
i_BMI
  DATA $0000 "BMI" $00 $00 $30
i_STA,X
  DATA $0000 "STA,X" $00 $00 $9D
i_CMP,Y
  DATA $0000 "CMP,Y" $00 $00 $D9
i_LDY#
  DATA $0000 "LDY#" $00 $00 $A0
i_JMP
  DATA $0000 "JMP" $00 $00 $4C
i_INX
  DATA $0000 "INX" $00 $00 $E8
i_CLC
  DATA $0000 "CLC" $00 $00 $18
i_BPL
  DATA $0000 "BPL" $00 $00 $10
i_STA,Y
  DATA $0000 "STA,Y" $00 $00 $99
i_STAZ,X
  DATA $0000 "STAZ,X" $00 $00 $95
i_DATA
  DATA $0000 "DATA" $00 $01 $00
i_SBCZ
  DATA $0000 "SBCZ" $00 $00 $E5
i_BRK
  DATA $0000 "BRK" $00 $00 $00
i_RTS
  DATA $0000 "RTS" $00 $00 $60
i_STA
  DATA $0000 "STA" $00 $00 $8D
i_AND#
  DATA $0000 "AND#" $00 $00 $29
i_LDAZ
  DATA $0000 "LDAZ" $00 $00 $A5
i_LDA,X
  DATA i_SBC# "LDA,X" $00 $00 $BD
i_SBC#
  DATA $0000 "SBC#" $00 $00 $E9
i_EORZ
  DATA $0000 "EORZ" $00 $00 $45
i_BNE
  DATA $0000 "BNE" $00 $00 $D0
i_PHA
  DATA $0000 "PHA" $00 $00 $48
i_LDA,Y
  DATA $0000 "LDA,Y" $00 $00 $B9
i_SEC
  DATA $0000 "SEC" $00 $00 $38
i_ADCZ
  DATA $0000 "ADCZ" $00 $00 $65
i_STAZ(),Y
  DATA $0000 "STAZ(),Y" $00 $00 $91

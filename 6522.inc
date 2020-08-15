; 6522 registers
T1CL    = $6004
T1CH    = $6005
T1LL    = $6006
T1LH    = $6007
T2CL    = $6008
T2CH    = $6009
SR      = $600A
ACR     = $600B
PCR     = $600C
IFR     = $600D
IER     = $600E
PORTANH = $600F


; 6522 flag masks
IERSETCLEAR        = %10000000
IT1                = %01000000
IT2                = %00100000
ICB1               = %00010000
ICB2               = %00001000
ISR                = %00000100
ICA1               = %00000010
ICA2               = %00000001

ACR_T1_CONT        = %01000000
ACR_T1_TIMED       = %10000000
ACR_T1_CONT_SQWAVE = %11000000

ACR_T2_COUNT_DOWN  = %00100000

ACR_SR_IN_T2       = %00000100
ACR_SR_IN_CK       = %00001000
ACR_SR_IN_CB1      = %00001100
ACR_SR_OUT_FR_T2   = %00010000
ACR_SR_OUT_T2      = %00010100
ACR_SR_OUT_CK      = %00011000
ACR_SR_OUT_CB1     = %00011100

PCR_CA2_IND_NEG_E  = %00000010 ; CA2 Independent interrupt input - negative edge
PCR_CA2_IND_POS_E  = %00000110 ; CA2 Independent interrupt input - positive edge
PCR_CB2_IND_NEG_E  = %00100000 ; CB2 Independent interrupt input - negative edge
PCR_CB2_IND_POS_E  = %01100000 ; CB2 Independent interrupt input - positive edge
PCR_CB2_LOW_OUT    = %11000000 ; CB2 Low output
PCR_CB2_HIGH_OUT   = %11100000 ; CB2 High output

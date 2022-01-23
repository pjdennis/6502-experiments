; 6522 registers
PORTB   = $6000
PORTA   = $6001
DDRB    = $6002
DDRA    = $6003
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

DDR_OFFSET = DDRB - PORTB

; 6522 flag masks
IERSETCLEAR        = %10000000
IT1                = %01000000
IT2                = %00100000
ICB1               = %00010000
ICB2               = %00001000
ISR                = %00000100
ICA1               = %00000010
ICA2               = %00000001

ACR_T1_TIMED       = %00000000
ACR_T1_CONT        = %01000000
ACR_T1_OUTPUT      = %10000000
ACR_T1_CONT_SQWAVE = %11000000

ACR_T2_TIMED       = %00000000
ACR_T2_COUNT_DOWN  = %00100000

ACR_SR_IN_T2       = %00000100
ACR_SR_IN_CK       = %00001000
ACR_SR_IN_CB1      = %00001100
ACR_SR_OUT_FR_T2   = %00010000
ACR_SR_OUT_T2      = %00010100
ACR_SR_OUT_CK      = %00011000
ACR_SR_OUT_CB1     = %00011100

ACR_PB_LATCH_EN    = %00000010
ACR_PA_LATCH_EN    = %00000001

PCR_CA1_NEG_E      = %00000000 ; CA1 Negative edge
PCR_CA1_POS_E      = %00000001 ; CA1 Positive edge

PCR_CA2_NEG_E      = %00000000 ; CA2 Input - negative edge
PCR_CA2_IND_NEG_E  = %00000010 ; CA2 Independent interrupt input - negative edge
PCR_CA2_POS_E      = %00000100 ; CA2 Input - positive edge
PCR_CA2_IND_POS_E  = %00000110 ; CA2 Independent interrupt input - positive edge
PCR_CA2_HAND_OUT   = %00001000 ; CA2 Handshake output
PCR_CA2_PULSE_OUT  = %00001010 ; CA2 Pulse output
PCR_CA2_LOW_OUT    = %00001100 ; CA2 Low output
PCR_CA2_HIGH_OUT   = %00001110 ; CA2 High output

PCR_CB1_NEG_E      = %00000000 ; CB1 Negative edge
PCR_CB1_POS_E      = %00010000 ; CB1 Positive edge

PCR_CB2_NEG_E      = %00000000 ; CB2 Input - negative edge
PCR_CB2_IND_NEG_E  = %00100000 ; CB2 Independent interrupt input - negative edge
PCR_CB2_POS_E      = %01000000 ; CB2 Input - positive edge
PCR_CB2_IND_POS_E  = %01100000 ; CB2 Independent interrupt input - positive edge
PCR_CB2_HAND_OUT   = %10000000 ; CB2 Handshake output
PCR_CB2_PULSE_OUT  = %10100000 ; CB2 Pulse output
PCR_CB2_LOW_OUT    = %11000000 ; CB2 Low output
PCR_CB2_HIGH_OUT   = %11100000 ; CB2 High output

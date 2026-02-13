; test_runner.asm - Native 6502 test runner for the assembler
;
; Runs assembler test files entirely within the emulated environment.
; The assembler code is called as a black box via JSR start.
;
; Build:
;   (cd 17 && ../emulator.out out/asm.out asm.asm out/test_runner.out define:enable_test_runner)
;
; Usage:
;   (cd 17 && ../emulator.out out/test_runner.out tests/asm/01-instructions.txt)


test_runner_start:
  SHOW_MESSAGEI tr_msg_started
  BRK
  .byte 0

tr_msg_started:
  .asciiz "Test runner started\n"

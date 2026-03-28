* = $1000

  .include 23/environment.asm

start
  ; Set bind port to 8080 ($1F90)
  LDA #$90
  STA port_bind_l
  LDA #$1F
  STA port_bind_h

  ; Create socket
  JSR socket_create
  STA LISTEN_HANDLE

  ; Bind
  LDA LISTEN_HANDLE
  JSR socket_bind

  ; Listen
  LDA LISTEN_HANDLE
  JSR socket_listen

  ; Print listening message
  LDA #<listening_msg
  STA MSG_PTR
  LDA #>listening_msg
  STA MSG_PTR+$01
  JSR print_msg

accept_loop
  ; Accept a connection
  LDA LISTEN_HANDLE
  JSR socket_accept
  STA CLIENT_HANDLE

  ; Read request headers until \r\n\r\n
  LDA #$00
  STA HEADER_STATE

read_loop
  LDA CLIENT_HANDLE
  JSR socket_recv
  BCS client_closed

  ; Track \r\n\r\n pattern
  ; State 0: waiting for \r
  ; State 1: got \r, waiting for \n
  ; State 2: got \r\n, waiting for \r
  ; State 3: got \r\n\r, waiting for \n
  LDX HEADER_STATE

  CPX #$00
  BEQ .check_cr
  CPX #$01
  BEQ .check_lf1
  CPX #$02
  BEQ .check_cr2
  ; State 3: expecting \n
  CMP #$0A
  BEQ headers_done
  JMP .reset_state

.check_cr
  CMP #$0D
  BNE .reset_state
  LDA #$01
  STA HEADER_STATE
  JMP read_loop

.check_lf1
  CMP #$0A
  BNE .reset_state
  LDA #$02
  STA HEADER_STATE
  JMP read_loop

.check_cr2
  CMP #$0D
  BNE .reset_state
  LDA #$03
  STA HEADER_STATE
  JMP read_loop

.reset_state
  LDA #$00
  STA HEADER_STATE
  JMP read_loop

headers_done
  ; Send HTTP response
  LDA #<http_response
  STA MSG_PTR
  LDA #>http_response
  STA MSG_PTR+$01

  LDY #$00
send_loop
  LDA (MSG_PTR),Y
  BEQ send_done
  LDX CLIENT_HANDLE
  JSR socket_send
  INY
  BNE send_loop
  ; Handle crossing page boundary
  INC MSG_PTR+$01
  JMP send_loop

send_done
client_closed
  ; Close client socket
  LDA CLIENT_HANDLE
  JSR socket_close

  ; Loop back to accept next connection
  JMP accept_loop


; Print a null-terminated message to stderr
; MSG_PTR/MSG_PTR+1 = pointer to message
print_msg
  LDY #$00
.loop
  LDA (MSG_PTR),Y
  BEQ .done
  JSR write_d
  INY
  BNE .loop
.done
  RTS


  .zeropage

* = $01

LISTEN_HANDLE  .byte
CLIENT_HANDLE  .byte
HEADER_STATE   .byte
MSG_PTR        .word

  .code

listening_msg
  .byte "Listening on port 8080\n", $00

http_response
  .byte "HTTP/1.0 200 OK\r\n"
  .byte "Content-Type: text/html\r\n"
  .byte "Connection: close\r\n"
  .byte "\r\n"
  .byte "<html><body>"
  .byte "<h1>Hello from 6502 asm</h1>"
  .byte "<p>This page is served by a 6502 assembly web server running in an emulator.</p>"
  .byte "</body></html>"
  .byte $00

  .word start

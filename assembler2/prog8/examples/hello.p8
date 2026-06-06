; The Phase-1 walking skeleton: clear the LCD, print "hi from prog8",
; loop forever. Run with:
;
;   python3 -m p8c examples/hello.p8 --run
;
; Equivalent in spirit to hello_ram_4000_wendy2c.s in the repo root.

%address $4000
%output raw
%import txt
%import lcd

main {
  sub start() {
    lcd.clear()
    txt.print("hi from prog8")
  }
}

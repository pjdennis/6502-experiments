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

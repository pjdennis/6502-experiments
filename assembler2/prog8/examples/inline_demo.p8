; Phase 3: inline sub. Each call splices the body in place; no JSR.

%address $4000
%output raw
%import txt
%import lcd

inline sub print_bracket(ubyte ch) {
    txt.print("[")
    txt.print_ub(ch)
    txt.print("]")
}

main {
  sub start() {
    lcd.clear()
    print_bracket($1a)
    print_bracket($b2)
    print_bracket($ff)
  }
}

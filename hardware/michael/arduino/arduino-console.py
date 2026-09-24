from asciimatics.screen import Screen

def run(screen):
  n = 1
  while True:
    screen.print_at('Line ' + str(n), 0, screen.height -1)
    screen.scroll(lines = -1)
    screen.refresh()
    n += 1

Screen.wrapper(run)

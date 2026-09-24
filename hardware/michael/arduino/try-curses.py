import curses
import datetime

stdscr = curses.initscr()
curses.noecho()
stdscr.nodelay(1) # set getch() non-blocking

stdscr.addstr(0,0,"Press \"p\" to show count, \"q\" to exit...")
line = 1
try:
    n = 0
    while 1:
        n += 1
        c = stdscr.getch()
        if c == ord('p'):
            stdscr.addstr(line,0,"Some text here - " + str(n))
            line += 1
        elif c == ord('q'): break

        """
        Do more things
        """

finally:
    curses.endwin()

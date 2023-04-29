  .org $2000

BF_ZERO_PAGE_BASE = $00

bf_getchar = 0
bf_putchar = 0

  .include brainfotc.inc

cells:
cellsEnd = cells + 1024
code     = cellsEnd
codeEnd  = code + 24576

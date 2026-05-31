"""Stdlib symbol declarations.

The actual implementation lives in `stdlib/*.p8` (eventually a mix of
Prog8 source and inline-asm wrappers around the repo's existing .inc
helpers). For Phase 1 we just declare the symbols and let codegen emit
JSRs to fixed entry points exported by the wendy2c boot ROM / include
files.
"""
from __future__ import annotations

from .ast import Symbol, STR, UBYTE, VOID


# txt.print(str) -- print zero-terminated string at the LCD cursor.
# Lowers to: lda #<str ; ldx #>str ; jsr display_string.
TXT_PRINT = Symbol(
    name="print", mangled="display_string", type=VOID, kind="extsub",
    asm_target="display_string",
)

# lcd.clear() -- clear LCD and home cursor.
LCD_CLEAR = Symbol(
    name="clear", mangled="clear_display", type=VOID, kind="extsub",
    asm_target="clear_display",
)


STDLIB_SYMBOLS: dict[str, list[Symbol]] = {
    "txt": [TXT_PRINT],
    "lcd": [LCD_CLEAR],
}

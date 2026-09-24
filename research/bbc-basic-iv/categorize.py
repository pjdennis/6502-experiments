# Each tuple: (start_line, top_category, subcategory)
# Region runs from its start line up to (but not including) the next region's start.
segs = [
(1,    "harness",   "build preamble"),
(8,    "harness",   "equates (OS vectors, token consts)"),
(26,   "harness",   "build preamble"),
(30,   "startup",   "ROM header + powers-of-ten"),
(47,   "startup",   "language startup"),
(65,   "variables", "FN/PROC + variable name lookup"),
(122,  "progmgmt",  "search for program line"),
(149,  "fpmath",    "integer division (DIV/MOD)"),
(197,  "fpmath",    "FP core: int<->real, normalise, float->int, add/sub"),
(531,  "tokeniser", "keyword/token table"),
(676,  "interp",    "function/command dispatch table"),
(795,  "assembler", "built-in 6502 assembler"),
(1515, "tokeniser", "tokenise line"),
(1684, "tokeniser", "parser helpers (skip spaces/comma)"),
(1716, "progmgmt",  "CHAIN/RUN/LOAD/OLD/END"),
(1750, "startup",   "BASIC startup"),
(1783, "interp",    "NEW + immediate loop"),
(1807, "interp",    "*command, DATA/DEF/REM"),
(1854, "interp",    "command dispatch, LET, =expr, STOP"),
(1949, "strings",   "string assignment/store"),
(2009, "io",        "PRINT# (file output)"),
(2058, "io",        "PRINT + formatting (TAB/SPC)"),
(2231, "interp",    "CALL"),
(2279, "progmgmt",  "DELETE"),
(2302, "progmgmt",  "RENUMBER"),
(2434, "progmgmt",  "AUTO"),
(2456, "variables", "DIM"),
(2596, "interp",    "env cmds (HIMEM/LOMEM/PAGE/CLEAR/TRACE/TIME)"),
(2676, "evaluator", "integer-eval helpers"),
(2727, "control",   "PROC / LOCAL"),
(2775, "io",        "graphics/VDU (GCOL/COLOUR/MODE/MOVE/DRAW/PLOT/CLG/CLS/VDU/REPORT)"),
(2923, "variables", "variable processing, find/allocate, arrays"),
(3324, "evaluator", "expression evaluator core (levels 7-3, compares)"),
(4002, "harness",   "intermediate SAVE directive"),
(4005, "evaluator", "level 2 ^ (power)"),
(4065, "numstr",    "integer/hex output"),
(4137, "numstr",    "float -> decimal string formatting"),
(4394, "numstr",    "scan decimal number (parse literal)"),
(4523, "fpmath",    "transcendentals (SIN/COS/TAN/ASN/ACS/ATN/LN/LOG/EXP/SQR/RAD/DEG) + FP mul/div"),
(5429, "io",        "NOT/POS/USR/VPOS"),
(5465, "io",        "file funcs (PTR/BGET/OPENIN/OUT/UP) + PI"),
(5515, "evaluator", "EVAL"),
(5549, "numstr",    "VAL / INT"),
(5607, "functions", "ASC/INKEY/EOF/TRUE/FALSE/SGN/POINT"),
(5691, "strings",   "INSTR"),
(5762, "evaluator", "ABS/negate/unary-minus/string-parse"),
(5844, "evaluator", "level 1 value (indirection, &hex, immediate)"),
(5943, "functions", "pseudo-var & IO readers (ADVAL/TOP/PAGE/LEN/COUNT/LOMEM/HIMEM/ERL/ERR/GET/TIME/GET$/LEFT$/RIGHT$/INKEY$)"),
(6092, "strings",   "MID$/STR$/STRING$"),
(6199, "control",   "FN/PROC call: search in program"),
(6270, "harness",   "intermediate SAVE directive"),
(6273, "control",   "FN/PROC call mechanism"),
(6444, "variables", "read variable value + CHR$"),
(6536, "error",     "search for error line number"),
(6568, "error",     "BRKV error handler + ON ERROR OFF + default handler"),
(6604, "io",        "SOUND/ENVELOPE/WIDTH"),
(6661, "variables", "assign value to variable"),
(6705, "progmgmt",  "EDIT / LIST"),
(6877, "control",   "NEXT"),
(6992, "control",   "FOR"),
(7083, "control",   "GOSUB/RETURN/GOTO"),
(7144, "control",   "ON [ERROR/GOTO/GOSUB]"),
(7254, "io",        "INPUT / INPUT#"),
(7405, "control",   "RESTORE / READ"),
(7503, "control",   "UNTIL / REPEAT"),
(7544, "io",        "input-string (OSWORD line input)"),
(7606, "tokeniser", "tokenise line & enter into program"),
(7686, "interp",    "clear/reset variables & pointers"),
(7710, "evaluator", "runtime stack value management (push/pop int/real/string)"),
(7856, "io",        "print/detokenise/hex/number output helpers"),
(7979, "progmgmt",  "LOAD program + find TOP"),
(8053, "io",        "SAVE/OSCLI/EXT=/PTR=/CLOSE/BPUT"),
(8113, "io",        "PRINT inline text + OSWORD byte read + NEW"),
(8155, "fpmath",    "FP routine entry table"),
(8171, "fpmath",    "FP constants (PI, trig/log/exp series)"),
(8224, "harness",   "build tail (SAVE, FN defs)"),
(8238, "END", "END"),
]

# compute line counts
rows=[]
total=0
for i in range(len(segs)-1):
    s=segs[i][0]; e=segs[i+1][0]-1
    n=e-s+1
    rows.append((segs[i][1], segs[i][2], s, e, n))
    total+=n

from collections import defaultdict
cat=defaultdict(int)
sub=defaultdict(list)
for c,sc,s,e,n in rows:
    cat[c]+=n
    sub[c].append((sc,n,s,e))

rom_total = total - cat["harness"]
print(f"TOTAL source lines counted: {total}")
print(f"Harness/build lines (excluded from ROM): {cat['harness']}")
print(f"ROM source lines (analysed): {rom_total}\n")

order=sorted(cat.items(), key=lambda x:-x[1])
print(f"{'CATEGORY':<14}{'lines':>7}{'% ROM':>8}")
print("-"*30)
for c,n in order:
    if c=="harness": continue
    print(f"{c:<14}{n:>7}{100*n/rom_total:>7.1f}%")
print("-"*30)
print(f"{'(harness)':<14}{cat['harness']:>7}")
print()
print("=== Sub-breakdowns per category (lines, %ROM) ===")
for c,n in order:
    if c=="harness": continue
    print(f"\n## {c}  ({n} lines, {100*n/rom_total:.1f}% of ROM)")
    for sc,sn,s,e in sorted(sub[c], key=lambda x:-x[1]):
        print(f"   {sn:<70} {sn and ''}{sn!='' and ''}  {str(s)+'-'+str(e):>10} {sn and ''}{100*sn/rom_total:>5.1f}%  ({sn})")

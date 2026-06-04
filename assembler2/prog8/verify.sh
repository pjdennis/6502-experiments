#!/bin/bash
# p8c self-host check: build both pipeline passes with the host p8c, run them on
# p1.p8, and diff the emitted asm against the p8c oracle for p1.p8. PASS = the
# p8c-compiled pipeline reproduces p8c's own output byte-for-byte (0-line diff).
#
# The pipeline source (p1_pass1_sh.p8 / p1_pass2_sh.p8) is upstream-dialect and
# carries no %target, so it is built with `--target nmos`. p1.p8 (the self-host
# input + oracle) still uses its own directives.
set -e
cd "$(dirname "$0")"
EMU=../emulator/emulator.out
CAP=30000000000

python3 -m p8c --target nmos p1/p1_pass1_sh.p8 -o /tmp/_p1.s >/dev/null 2>&1
O1=$(vasm6502_oldstyle -Fbin -dotdir -ignore-mult-inc -esc -wfail -o /tmp/p1.bin /tmp/_p1.s 2>&1) \
   || { echo "PASS1 VASM FAIL"; echo "$O1" | grep -i error; exit 1; }
python3 -m p8c --target nmos p1/p1_pass2_sh.p8 -o /tmp/_p2.s >/dev/null 2>&1
O2=$(vasm6502_oldstyle -Fbin -dotdir -ignore-mult-inc -esc -wfail -o /tmp/p2.bin /tmp/_p2.s 2>&1) \
   || { echo "PASS2 VASM FAIL"; echo "$O2" | grep -iE 'error|overlap'; exit 1; }
s1=$(echo "$O1" | grep 'org0001' | grep -oE '[0-9]+ bytes' | grep -oE '[0-9]+')
s2=$(echo "$O2" | grep 'org0001' | grep -oE '[0-9]+ bytes' | grep -oE '[0-9]+')

$EMU /tmp/p1.bin --cycle-cap $CAP p1/p1.p8 /tmp/p1dump.bin >/dev/null 2>&1 \
   || { echo "PASS1 RUN FAIL"; exit 1; }
$EMU /tmp/p2.bin --cycle-cap $CAP --no-dump /tmp/p1dump.bin /tmp/p1out.s >/dev/null 2>&1 \
   || { echo "PASS2 RUN FAIL"; exit 1; }
python3 -m p8c p1/p1.p8 -o /tmp/p1_oracle.s >/dev/null 2>&1
n=$(diff <(sed 's/^; source:.*/X/' /tmp/p1out.s) <(sed 's/^; source:.*/X/' /tmp/p1_oracle.s) | wc -l)
python3 -c "print(f'pass1 top \${0x200+$s1:04X} ({0xF000-0x200-$s1} B free)  pass2 top \${0x200+$s2:04X} ({0xF000-0x200-$s2} B free)')"
echo "SELF-HOST normalized diff: $n lines"
[ "$n" -eq 0 ] && echo "PASS: p8c-compiled p1 pipeline self-hosts byte-identically to p8c."

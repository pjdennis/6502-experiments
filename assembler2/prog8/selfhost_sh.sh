#!/bin/bash
# True self-host gate: build both pipeline passes with host p8c, then run the
# pipeline on EACH _sh source and diff the emitted asm against p8c's own output
# for that source. PASS = the on-target pipeline reproduces p8c byte-for-byte
# for its OWN sources (the files that make up the pipeline).
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
python3 -c "print(f'pass1 top \${0x200+$s1:04X} ({0xF000-0x200-$s1} B free)  pass2 top \${0x200+$s2:04X} ({0xF000-0x200-$s2} B free)')"

fail=0
for f in p1_pass1_sh p1_pass2_sh; do
  $EMU /tmp/p1.bin --cycle-cap $CAP p1/$f.p8 /tmp/${f}_dump.bin >/dev/null 2>&1 \
     || { echo "$f: PASS1 RUN FAIL"; fail=1; continue; }
  $EMU /tmp/p2.bin --cycle-cap $CAP --no-dump /tmp/${f}_dump.bin /tmp/${f}_out.s >/dev/null 2>&1 \
     || { echo "$f: PASS2 RUN FAIL"; fail=1; continue; }
  python3 -m p8c --target nmos p1/$f.p8 -o /tmp/${f}_oracle.s >/dev/null 2>&1
  n=$(diff <(sed 's/^; source:.*/X/' /tmp/${f}_out.s) <(sed 's/^; source:.*/X/' /tmp/${f}_oracle.s) | wc -l)
  if [ "$n" -eq 0 ]; then echo "$f: SELF-HOST diff=0 PASS"; else echo "$f: SELF-HOST diff=$n FAIL"; fail=1; fi
done
exit $fail

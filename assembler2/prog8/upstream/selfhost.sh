#!/bin/bash
# Upstream-bootstrapped self-host: build the p1 pipeline (pass1_sh + pass2_sh)
# with the UPSTREAM Prog8 compiler (prog8c) for the custom `nmos` target, run it
# on the emulator to compile p1.p8, and check the result is byte-identical to
# the p8c host oracle. This is the goal of the whole upstream-bootstrap effort.
#
# Prereqs (see setup.sh): /tmp/prog8c.jar, 64tass on PATH, the emulator built.
set -e
cd "$(dirname "$0")/.."                      # .../assembler2/prog8
HERE=upstream
EMU=../emulator/emulator.out
JAR=/tmp/prog8c.jar
CAP=30000000000
mkdir -p /tmp/pass1 /tmp/pass2

build_pass() {                               # $1=sh source  $2=tag
    python3 $HERE/port_pipeline.py p1/$1 /tmp/$2_up.p8 /tmp/$2.properties $HERE/nmos.properties
    ( cd $HERE && java -jar $JAR -target /tmp/$2.properties -out /tmp/$2 /tmp/$2_up.p8 >/tmp/$2_build.log 2>&1 ) \
        || { echo "$2 COMPILE FAILED"; tail -5 /tmp/$2_build.log; exit 1; }
    python3 $HERE/mkimage.py /tmp/$2/$2_up.bin /tmp/$2/img.bin >/dev/null
}

echo "building pass1 (upstream prog8c)..."; build_pass p1_pass1_sh.p8 pass1
echo "building pass2 (upstream prog8c)..."; build_pass p1_pass2_sh.p8 pass2

echo "running pass1(p1.p8) -> AST/sym dump..."
$EMU /tmp/pass1/img.bin --cycle-cap $CAP p1/p1.p8 /tmp/p1dump.bin >/dev/null 2>&1
echo "running pass2(dump) -> p1.s..."
$EMU /tmp/pass2/img.bin --cycle-cap $CAP --no-dump /tmp/p1dump.bin /tmp/p1out.s >/dev/null 2>&1

python3 -m p8c p1/p1.p8 -o /tmp/p1oracle.s >/dev/null 2>&1
n=$(diff <(sed 's/^; source:.*/X/' /tmp/p1out.s) <(sed 's/^; source:.*/X/' /tmp/p1oracle.s) | wc -l)
echo "upstream-pipeline output: $(wc -c </tmp/p1out.s) B   p8c oracle: $(wc -c </tmp/p1oracle.s) B"
echo "UPSTREAM-BOOTSTRAP SELF-HOST normalized diff: $n lines"
[ "$n" -eq 0 ] && echo "PASS: upstream-compiled p1 pipeline self-hosts byte-identically to p8c."

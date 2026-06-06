#!/bin/bash
# HARD REQUIREMENT GATE: both pipeline passes MUST compile with the UPSTREAM
# Prog8 compiler (prog8c), not just the in-repo p8c backend.
#
# The pipeline sources (p1/p1_pass1_sh.p8, p1/p1_pass2_sh.p8) are upstream-dialect
# Prog8. They have TWO consumers:
#   1. upstream prog8c (via upstream/port_pipeline.py) -- the reference build.
#   2. the in-repo p8c backend (the on-target self-hosting toolchain).
#
# p8c is more lenient than upstream, so it is EASY to introduce changes that p8c
# accepts but upstream rejects. Known traps (do NOT do these):
#   * Un-wrapping the `main { ... }` block / putting decls at top level.
#     Upstream requires every declaration inside a block; p8c tolerates
#     top-level decls. (This is why the on-target pass1 must learn to parse a
#     main-wrapped program rather than the source being un-wrapped.)
#   * Bare truthy conditions like `if some_call(...)` / `while arr[i]`.
#     Upstream requires boolean conditions -- write `... != 0` explicitly
#     (port_pipeline only auto-wraps a subset).
#
# Run this after ANY edit to the _sh pipeline sources.
# Prereq: upstream prog8c jar at $PROG8C (default /tmp/prog8c.jar) + 64tass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
JAR="${PROG8C:-/tmp/prog8c.jar}"
cd "$HERE"                       # port_pipeline.py reads ./nmos.properties + imports port_p1
mkdir -p /tmp/upchk
fail=0
for src in p1_pass1_sh p1_pass2_sh; do
  python3 "$HERE/port_pipeline.py" "$HERE/../p1/$src.p8" \
      "/tmp/${src}_up.p8" "/tmp/${src}.properties" >/dev/null 2>&1 \
    || { echo "FAIL: port_pipeline.py errored on $src"; fail=1; continue; }
  rm -f "/tmp/upchk/${src}_up.asm"
  if java -jar "$JAR" -target "/tmp/${src}.properties" -out /tmp/upchk \
        "/tmp/${src}_up.p8" >"/tmp/${src}_up.log" 2>&1 \
      && [ -f "/tmp/upchk/${src}_up.asm" ]; then
    echo "PASS: upstream prog8c compiles $src"
  else
    echo "FAIL: upstream prog8c rejects $src --"
    grep -iE 'error|exception' "/tmp/${src}_up.log" | head -4
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "OK: both passes compile with upstream prog8c." \
                  || echo "BROKEN: upstream compatibility regression (hard requirement)."
exit $fail

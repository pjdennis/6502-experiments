#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/../../../firmware/vasm" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc $1 && python3 transfer_with_length.py a.out

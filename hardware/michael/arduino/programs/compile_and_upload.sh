#!/bin/sh
# Usage: compile_and_upload.sh <program.s> -- assemble, then load it into the
# Arduino-emulated memory with the Arduino's "l" command (see ../host/).
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/../../../../firmware/vasm" -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc $1 && python3 "$HERE/../host/transfer_with_length.py" a.out

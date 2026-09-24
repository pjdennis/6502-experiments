#!/bin/sh
# Fetch the Tom Harte ProcessorTests data into emulator/tests/harte/data/.
# This is multi-GB; run only when you actually want to run `make harte`.

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$HERE/data"

if [ -d "$DATA_DIR/.git" ]; then
    echo "Updating existing $DATA_DIR ..."
    git -C "$DATA_DIR" pull --depth 1 origin main
else
    echo "Cloning SingleStepTests/65x02 (this is large) into $DATA_DIR ..."
    git clone --depth 1 https://github.com/SingleStepTests/65x02.git "$DATA_DIR"
fi

echo "Done. Try: make harte HARTE_LIMIT=10"

#!/bin/bash
# Check that all .asm and .txt files in the assembler/editor source tree
# contain only ASCII characters (bytes 0x00-0x7F).
# Scans: 22/, 23/, editor/ (excluding Python scripts and output directories)

found=0

while IFS= read -r file; do
    # grep for any byte with high bit set (0x80-0xFF)
    matches=$(grep -Pn '[^\x00-\x7F]' "$file")
    if [ -n "$matches" ]; then
        echo "=== $file ==="
        echo "$matches"
        echo
        found=1
    fi
done < <(find 22 23 editor -type f \( -name '*.asm' -o -name '*.txt' \) ! -path '*/out/*')

if [ "$found" -eq 0 ]; then
    echo "All files are ASCII-clean."
fi

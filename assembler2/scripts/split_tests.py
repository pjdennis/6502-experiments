#!/usr/bin/env python3
"""Split asm_tests.txt into modular test files."""

from pathlib import Path

SPLITS = {
    '01-instructions.txt': (15, 400),
    '02-expressions_basic.txt': (401, 705),
    '03-expressions_operators.txt': (706, 1006),
    '04-expressions_advanced.txt': (1007, 1286),
    '05-labels_basics.txt': (1287, 1500),
    '06-labels_forward_refs.txt': (1501, 1740),
    '07-directives_data.txt': (1741, 2000),
    '08-directives_strings.txt': (2001, 2300),
    '09-directives_includes.txt': (2301, 2522),
    '10-multi_directive.txt': (2523, 2637),
    '11-conditionals_basic.txt': (2638, 2861),
    '12-conditionals_nesting.txt': (2862, 3108),
    '13-conditionals_edge_cases.txt': (3109, 3277),
    '14-macros.txt': (3278, 3603),
    '15-macros_advanced.txt': (3604, 3850),
    '16-macros_edge_cases.txt': (3851, 4083),
    '17-errors.txt': (4084, 4194),
    '18-memory_limits.txt': (4195, 4461),
}


def split_file(input_file, output_dir):
    """Split input file into multiple files based on line ranges."""
    input_path = Path(input_file)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    lines = input_path.read_text().splitlines(keepends=True)
    total_lines = len(lines)

    print(f"Input file: {input_file} ({total_lines} lines)")
    print(f"Output dir: {output_dir}")
    print()

    for filename, (start, end) in SPLITS.items():
        output_file = output_path / filename
        content = ''.join(lines[start-1:end])
        output_file.write_text(content)

        file_size = len(content)
        size_kb = file_size / 1024
        line_count = end - start + 1

        print(f"Created {output_file.name:30s} {line_count:4d} lines  {size_kb:5.1f} KB")


if __name__ == '__main__':
    import sys
    if len(sys.argv) != 3:
        print("Usage: split_tests.py <input_file> <output_dir>")
        sys.exit(1)

    split_file(sys.argv[1], sys.argv[2])

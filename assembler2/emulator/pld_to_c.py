#!/usr/bin/env python3
"""Translate a 22V10 GAL .pld file into a C header for the emulator.

The .pld dialect used in this repo:
  * Each combinational output is a sum-of-products expression
        OUT = /A * B + C            ; (NOT A AND B) OR C
  * `*` is AND, `+` is OR, `/X` is NOT X.
  * `.R` suffix on the LHS marks a registered (sequential) output -- we
    skip these; the emulator hand-codes clock generation in C.
  * Semicolons start end-of-line comments.
  * The DESCRIPTION section at the bottom is free-form prose; we stop
    parsing once we hit the literal token DESCRIPTION.

The script emits a header with static inline functions:
    int pld_romcs(int a15, .., int c0);
    int pld_viacs(int a15, .., int c0);
    int pld_ramcs(int a15, .., int c0);
    int pld_r15 (int a15, .., int c0);
    int pld_r16 (int a15, .., int c0);
    int pld_r17 (int a15, .., int c0);
    int pld_r18 (int a15, .., int c0);

clock_22v10.c includes the header and calls these in its tick path,
so a change to the .pld immediately flows to the emulator's PLD
behavior (after `make` regenerates the header).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Input variables this generator recognizes. The parameter order of
# every emitted function is fixed and matches this list.
INPUT_VARS = ['a15', 'a14', 'a13', 'a12', 'a11',
              'c4',  'c3',  'c2',  'c1',  'c0']

# Outputs we emit. The boolean in the tuple is True when the .pld
# defines the output in its NEGATED form (/X = ...), so the generated
# C function must invert the result.
#                C-name  .pld names (try in order)   negated?
OUTPUT_SPECS = [
    ('romcs', ['ROMCS', '/ROMCS'], False),
    ('viacs', ['VIACS', '/VIACS'], False),
    ('ramcs', ['RAMCS', '/RAMCS'], False),
    ('r15',   ['R15'],              False),
    ('r16',   ['R16'],              False),
    ('r17',   ['R17'],              False),
    ('r18',   ['R18'],              False),
]


# ---------------------------------------------------------------------------
# Parsing


def _strip_comment(line: str) -> str:
    """Drop the trailing ;-comment (if any)."""
    return line.split(';', 1)[0]


def parse_pld(text: str) -> dict[str, str]:
    """Return {equation_LHS: RHS_string} for every combinational equation.

    Multi-line equations are flattened: a line starting with `+` (after
    whitespace) is treated as a continuation of the previous equation.
    """
    # The DESCRIPTION block at the bottom is prose; stop parsing there.
    if 'DESCRIPTION' in text:
        text = text[:text.index('DESCRIPTION')]

    equations: dict[str, str] = {}
    current_name: str | None = None
    current_expr = ''

    for raw in text.split('\n'):
        line = _strip_comment(raw).rstrip()
        if not line.strip():
            continue

        # Pin-list lines look like "OSC A15 A14 ..." -- no `=` and no
        # leading `+`. Skip them.
        if '=' in line:
            # New equation -- commit the previous one.
            if current_name is not None:
                equations[current_name] = current_expr.strip()
            lhs, rhs = line.split('=', 1)
            current_name = lhs.strip()
            current_expr = rhs.strip()
        elif line.lstrip().startswith('+'):
            current_expr += ' ' + line.strip()
        # else: pin-list or stray line, ignore.

    if current_name is not None:
        equations[current_name] = current_expr.strip()

    return equations


# ---------------------------------------------------------------------------
# Translation


def _split_terms(expr: str) -> list[str]:
    """Split a sum-of-products by `+`, skipping the leading + that
    appears at the start of a continuation line after `lstrip`."""
    expr = expr.strip()
    if expr.startswith('+'):
        expr = expr[1:]
    return [t.strip() for t in expr.split('+') if t.strip()]


def _translate_term(term: str) -> tuple[str, set[str]]:
    """Translate one product-of-literals into a C expression. Returns
    the C expression and the set of input vars it references."""
    used: set[str] = set()
    parts: list[str] = []
    for raw in term.split('*'):
        f = raw.strip()
        if not f:
            continue
        negated = f.startswith('/')
        var = (f[1:] if negated else f).strip().lower()
        if var not in INPUT_VARS:
            raise ValueError(
                f"unknown variable {var!r} in term {term!r}; expected "
                f"one of {INPUT_VARS}"
            )
        used.add(var)
        parts.append(f"(!{var})" if negated else var)
    if not parts:
        return ('1', used)
    return (' & '.join(parts), used)


def translate_expr(expr: str) -> tuple[str, set[str]]:
    """Translate a sum-of-products PLD expression into a C boolean.

    Returns (c_expression, set_of_referenced_inputs).
    """
    used: set[str] = set()
    c_terms: list[str] = []
    for term in _split_terms(expr):
        c_term, term_used = _translate_term(term)
        c_terms.append(f"({c_term})")
        used |= term_used
    if not c_terms:
        return ('0', used)
    return (' | '.join(c_terms), used)


# ---------------------------------------------------------------------------
# Emission


def _params_list() -> str:
    return ', '.join(f'int {v}' for v in INPUT_VARS)


def _unused_casts(used: set[str], indent: str) -> str:
    unused = [v for v in INPUT_VARS if v not in used]
    if not unused:
        return ''
    return indent + ' '.join(f'(void){v};' for v in unused) + '\n'


def emit_function(c_name: str, expr: str, negated: bool) -> str:
    c_expr, used = translate_expr(expr)
    body_indent = '    '
    unused = _unused_casts(used, body_indent)
    if negated:
        ret = f'({c_expr}) ? 0 : 1'
    else:
        ret = f'({c_expr}) ? 1 : 0'
    return (
        f"static inline int pld_{c_name}({_params_list()}) {{\n"
        f"{unused}"
        f"{body_indent}return {ret};\n"
        f"}}\n"
    )


def generate_header(equations: dict[str, str], pld_path: str) -> str:
    lines = [
        f"/* GENERATED FROM {pld_path} by pld_to_c.py -- DO NOT EDIT.",
        f" *",
        f" * Each function evaluates one combinational output of the PLD",
        f" * directly from the addr+config bits. Re-run pld_to_c.py to",
        f" * refresh after editing the .pld source.",
        f" */",
        f"#ifndef EMULATOR_CHIPS_CLOCK_22V10_PLD_GENERATED_H",
        f"#define EMULATOR_CHIPS_CLOCK_22V10_PLD_GENERATED_H",
        f"",
    ]

    for c_name, candidates, _ in OUTPUT_SPECS:
        # Look for either positive or negated form.
        found = None
        for cand in candidates + ['/' + n for n in candidates if not n.startswith('/')]:
            if cand in equations:
                found = cand
                break
        if found is None:
            print(f"warning: no equation for {candidates[0]}", file=sys.stderr)
            continue
        negated = found.startswith('/')
        rhs = equations[found]
        lines.append(emit_function(c_name, rhs, negated))

    lines.append("#endif")
    lines.append("")
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Driver


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('pld', help='input .pld file')
    p.add_argument('-o', '--output', default='-',
                   help='output header (default: stdout)')
    args = p.parse_args()

    text = Path(args.pld).read_text()
    equations = parse_pld(text)
    header = generate_header(equations, args.pld)

    if args.output == '-':
        sys.stdout.write(header)
    else:
        Path(args.output).write_text(header)
    return 0


if __name__ == '__main__':
    sys.exit(main())

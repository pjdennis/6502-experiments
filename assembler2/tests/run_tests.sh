#!/bin/bash
#
# Test runner for assembler
# Usage: ./run_tests.sh [test_file] [assembler] [test_name]
#   test_file: Path to test file (default: tests/asm21_tests.txt)
#   assembler: Path to assembler (default: out/asm21_debug.out)
#   test_name: If provided, only runs that specific test
#

# Don't use set -e as arithmetic expressions can return non-zero

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSEMBLER2_DIR="$(dirname "$SCRIPT_DIR")"
TEST_FILE="${1:-$SCRIPT_DIR/asm21_tests.txt}"
ASSEMBLER="${2:-$ASSEMBLER2_DIR/out/asm21_debug.out}"
EMULATOR="$ASSEMBLER2_DIR/emulator.out"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Filter for single test
FILTER="${3:-}"

# Temp files
TMP_ASM=$(mktemp /tmp/test_XXXXXX.asm)
TMP_BIN=$(mktemp /tmp/test_XXXXXX.bin)
TMP_ERR=$(mktemp /tmp/test_XXXXXX.err)

cleanup() {
    rm -f "$TMP_ASM" "$TMP_BIN" "$TMP_ERR"
}
trap cleanup EXIT

# Check prerequisites
if [[ ! -x "$EMULATOR" ]]; then
    echo "Error: Emulator not found at $EMULATOR"
    echo "Run the build first"
    exit 1
fi

if [[ ! -f "$ASSEMBLER" ]]; then
    echo "Error: Assembler not found at $ASSEMBLER"
    echo "Run the build first"
    exit 1
fi

# Strip line number prefix from input line
# Pattern: optional digits followed by colon and space at start of line
strip_line_prefix() {
    sed 's/^[0-9]*: //'
}

# Run the assembler and capture output
# Args: input [extra_args...]
run_assembler() {
    local input="$1"
    shift
    echo "$input" | strip_line_prefix > "$TMP_ASM"
    "$EMULATOR" "$ASSEMBLER" 2000 /dev/null /dev/null "$TMP_ASM" "$TMP_BIN" debug "$@" 2>"$TMP_ERR"
    return $?
}

# Extract forward reference count from stderr
get_fwdref_count() {
    grep "Forward references forced to absolute:" "$TMP_ERR" | sed -n 's/.*: \([0-9]*\)$/\1/p'
}

# Get hex dump of binary output
get_hex() {
    xxd -p "$TMP_BIN" | tr -d '\n' | sed 's/\(..\)/\1 /g' | sed 's/ $//'
}

# Normalize hex string (lowercase, single spaces)
normalize_hex() {
    echo "$1" | tr 'A-F' 'a-f' | tr -s ' ' | sed 's/^ //;s/ $//'
}

# Run a positive test (expects successful assembly)
run_positive_test() {
    local name="$1"
    local input="$2"
    local expected_hex="$3"
    local expected_fwdref="$4"
    local extra_args="$5"

    if [[ -n "$FILTER" && "$name" != "$FILTER" ]]; then
        return 0
    fi

    printf "  %-40s " "$name"

    if run_assembler "$input" $extra_args; then
        local actual_hex=$(get_hex)
        local norm_expected=$(normalize_hex "$expected_hex")
        local norm_actual=$(normalize_hex "$actual_hex")
        local failed=0
        local details=""

        if [[ "$norm_expected" != "$norm_actual" ]]; then
            details="${details}    Expected hex: $norm_expected\n"
            details="${details}    Actual hex:   $norm_actual\n"
            failed=1
        fi

        # Check forward reference count if expected
        if [[ -n "$expected_fwdref" ]]; then
            local actual_fwdref=$(get_fwdref_count)
            if [[ "$actual_fwdref" != "$expected_fwdref" ]]; then
                details="${details}    Expected fwdref count: $expected_fwdref\n"
                details="${details}    Actual fwdref count:   $actual_fwdref\n"
                failed=1
            fi
        fi

        if [[ $failed -eq 0 ]]; then
            echo -e "${GREEN}PASS${NC}"
            ((PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            echo -e "$details" | sed 's/\\n/\n/g'
            ((FAILED++))
        fi
    else
        echo -e "${RED}FAIL${NC} (unexpected error)"
        cat "$TMP_ERR" | sed 's/^/    /'
        ((FAILED++))
    fi
}

# Run a negative test (expects assembly failure)
run_negative_test() {
    local name="$1"
    local input="$2"
    local expected_error="$3"
    local expected_line="$4"
    local expected_msg="$5"
    local extra_args="$6"

    if [[ -n "$FILTER" && "$name" != "$FILTER" ]]; then
        return 0
    fi

    printf "  %-40s " "$name"

    if run_assembler "$input" $extra_args; then
        echo -e "${RED}FAIL${NC} (expected error, got success)"
        ((FAILED++))
        return
    fi

    local error_output=$(cat "$TMP_ERR" | head -1)

    # Parse error output: "Error N in file ... at line L: message"
    local actual_error=$(echo "$error_output" | sed -n 's/^Error \([0-9]*\).*/\1/p')
    local actual_line=$(echo "$error_output" | sed -n 's/.*at line \([0-9]*\).*/\1/p')
    local actual_msg=$(echo "$error_output" | sed -n 's/.*: \(.*\)$/\1/p')

    local failed=0
    local details=""

    if [[ "$actual_error" != "$expected_error" ]]; then
        details="${details}    Error code: expected $expected_error, got $actual_error\n"
        failed=1
    fi

    if [[ "$actual_line" != "$expected_line" ]]; then
        details="${details}    Line: expected $expected_line, got $actual_line\n"
        failed=1
    fi

    if [[ ! "$actual_msg" =~ "$expected_msg" ]]; then
        details="${details}    Message: expected '$expected_msg', got '$actual_msg'\n"
        failed=1
    fi

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        echo -e "$details" | sed 's/\\n/\n/g'
        ((FAILED++))
    fi
}

# Run a stderr test (expects assembly failure with specific full stderr output)
# Use this for testing error traceback format and other multi-line diagnostics
# Supports {{MAIN_FILE}} placeholder which is replaced with the temp file path
run_stderr_test() {
    local name="$1"
    local input="$2"
    local expected_stderr="$3"
    local extra_args="$4"

    if [[ -n "$FILTER" && "$name" != "$FILTER" ]]; then
        return 0
    fi

    printf "  %-40s " "$name"

    if run_assembler "$input" $extra_args; then
        echo -e "${RED}FAIL${NC} (expected error, got success)"
        ((FAILED++))
        return
    fi

    # Get actual stderr, filtering out emulator status lines and stripping trailing whitespace
    # Emulator status lines start with the path or contain "cycles" or "was not closed"
    local actual_stderr=$(cat "$TMP_ERR" | grep -v "^out/" | grep -v "cycles$" | grep -v "was not closed$" | sed 's/[[:space:]]*$//')
    # Replace {{MAIN_FILE}} placeholder with actual temp file path and strip trailing whitespace
    local norm_expected=$(echo "$expected_stderr" | sed "s|{{MAIN_FILE}}|$TMP_ASM|g" | sed 's/[[:space:]]*$//')

    if [[ "$actual_stderr" == "$norm_expected" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Expected stderr:"
        echo "$norm_expected" | sed 's/^/      /'
        echo "    Actual stderr:"
        echo "$actual_stderr" | sed 's/^/      /'
        ((FAILED++))
    fi
}

# Parse and run tests from test file
parse_and_run_tests() {
    local in_test=0
    local name=""
    local input=""
    local expect_hex=""
    local expect_fwdref=""
    local expect_error=""
    local expect_line=""
    local expect_msg=""
    local expect_stderr=""
    local extra_args=""
    local in_input=0
    local in_stderr=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines outside of multi-line sections
        if [[ $in_input -eq 0 && $in_stderr -eq 0 ]]; then
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
        fi

        # Test separator
        if [[ "$line" == "---" ]]; then
            # Run previous test if we have one
            if [[ -n "$name" ]]; then
                if [[ -n "$expect_hex" ]]; then
                    run_positive_test "$name" "$input" "$expect_hex" "$expect_fwdref" "$extra_args"
                elif [[ -n "$expect_stderr" ]]; then
                    run_stderr_test "$name" "$input" "$expect_stderr" "$extra_args"
                elif [[ -n "$expect_error" ]]; then
                    run_negative_test "$name" "$input" "$expect_error" "$expect_line" "$expect_msg" "$extra_args"
                fi
            fi
            # Reset for next test
            name=""
            input=""
            expect_hex=""
            expect_fwdref=""
            expect_error=""
            expect_line=""
            expect_msg=""
            expect_stderr=""
            extra_args=""
            in_input=0
            in_stderr=0
            in_test=1
            continue
        fi

        # Parse fields
        if [[ "$line" =~ ^NAME:[[:space:]]*(.*) ]]; then
            name="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^INPUT: ]]; then
            in_input=1
            in_stderr=0
            input=""
        elif [[ "$line" =~ ^EXPECT_STDERR: ]]; then
            in_stderr=1
            in_input=0
            expect_stderr=""
        elif [[ "$line" =~ ^EXPECT_HEX:[[:space:]]*(.*) ]]; then
            expect_hex="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^EXPECT_FWDREF:[[:space:]]*(.*) ]]; then
            expect_fwdref="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^EXPECT_ERROR:[[:space:]]*(.*) ]]; then
            expect_error="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^EXPECT_LINE:[[:space:]]*(.*) ]]; then
            expect_line="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^EXPECT_MSG:[[:space:]]*(.*) ]]; then
            expect_msg="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ "$line" =~ ^ARGS:[[:space:]]*(.*) ]]; then
            extra_args="${BASH_REMATCH[1]}"
            in_input=0
            in_stderr=0
        elif [[ $in_input -eq 1 ]]; then
            # Accumulate input lines
            if [[ -n "$input" ]]; then
                input="${input}"$'\n'"${line}"
            else
                input="${line}"
            fi
        elif [[ $in_stderr -eq 1 ]]; then
            # Accumulate expected stderr lines
            if [[ -n "$expect_stderr" ]]; then
                expect_stderr="${expect_stderr}"$'\n'"${line}"
            else
                expect_stderr="${line}"
            fi
        fi
    done < "$TEST_FILE"

    # Run final test
    if [[ -n "$name" ]]; then
        if [[ -n "$expect_hex" ]]; then
            run_positive_test "$name" "$input" "$expect_hex" "$expect_fwdref" "$extra_args"
        elif [[ -n "$expect_stderr" ]]; then
            run_stderr_test "$name" "$input" "$expect_stderr" "$extra_args"
        elif [[ -n "$expect_error" ]]; then
            run_negative_test "$name" "$input" "$expect_error" "$expect_line" "$expect_msg" "$extra_args"
        fi
    fi
}

# Main
echo "========================================"
echo "Assembler Test Suite"
echo "========================================"
echo ""
echo "Running tests from $(basename "$TEST_FILE")"
echo ""

parse_and_run_tests

echo ""
echo "========================================"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "========================================"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0

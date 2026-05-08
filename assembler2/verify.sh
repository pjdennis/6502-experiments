#!/bin/bash

set -e

./asmtestgen.sh && editor/tests/editor_tests.py -q && tests/terminal_tests.py

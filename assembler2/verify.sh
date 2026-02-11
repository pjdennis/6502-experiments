#!/bin/bash

set -e

./asmtestgen.sh && ./run_tests.py -q && editor/tests/editor_tests.py -q

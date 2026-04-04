#!/bin/bash

set -e

./asmtestgen.sh && ./run_tests.py -q && tests/editor_tests.py -q

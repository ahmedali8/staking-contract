#!/usr/bin/env bash

# Pre-requisites:
# - foundry (https://getfoundry.sh)
# - lcov (https://github.com/linux-test-project/lcov)

# Strict mode: https://gist.github.com/vncsna/64825d5609c146e80de8b1fd623011ca
set -euo pipefail

# Generates a coverage report with Forge
rm -rf coverage
forge coverage \
    --report lcov \
    --report summary \
    --no-match-coverage '(tests|script|node_modules)' \
    --ir-minimum # https://github.com/foundry-rs/foundry/issues/3357

# Fix for lcov v2.0+
lcov --extract lcov.info --rc derive_function_end_line=0 --output-file lcov.info

# Opens it in the browser
genhtml lcov.info --rc derive_function_end_line=0 --output-dir coverage
open coverage/index.html

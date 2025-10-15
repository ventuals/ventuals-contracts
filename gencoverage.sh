#!/bin/bash
# gencoverage.sh - Run coverage and generate HTML report
#
# Prerequisites:
# - Foundry installed
# - genhtml installed (`brew install lcov`)
#
# Usage:
#   ./gencoverage.sh

forge coverage --report lcov

# Generate HTML report
genhtml lcov.info -o coverage

# Open HTML report
open coverage/index.html
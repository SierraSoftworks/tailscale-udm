#!/usr/bin/env bash
set -e

for test_file in "$(dirname "$0")"/*.test.sh; do
    echo "$test_file:"
    chmod +x "$test_file"
    "$test_file"
    echo ""
done
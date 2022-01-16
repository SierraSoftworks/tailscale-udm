#!/usr/bin/env bash
set -e

for test_file in $(find "$(dirname $0)" -name '*.test.sh'); do
    echo "$test_file:"
    "$test_file"
    echo ""
done
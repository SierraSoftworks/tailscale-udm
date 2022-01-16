#!/usr/bin/env bash

assert() {
    local TEST_RESULT=$?
    local TEST_NAME="${1?You must specify the test name as the first argument}"

    if [[ $TEST_RESULT -eq 0 ]]; then
        echo "✅  $TEST_NAME"
    else
        echo "❌  $TEST_NAME"
        exit 1
    fi
}

assert_eq() {
    local ACTUAL_OUTPUT="${1?You must specify the actual output first argument}"
    local EXPECTED_OUTPUT="${2?You must specify the expected output as the second argument}"
    local TEST_NAME="${3?You must specify the test name as the third argument}"
    
    if [ "$ACTUAL_OUTPUT" = "$EXPECTED_OUTPUT" ]; then
        echo "✅  $TEST_NAME"
    else
        echo "❌  $TEST_NAME"
        echo "    Expected: $EXPECTED_OUTPUT"
        echo "    Actual:   $ACTUAL_OUTPUT"
        exit 1
    fi
}
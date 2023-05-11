#!/usr/bin/env bash

set -e

cd testdata

if ! diff -u test-expected.txt <(../templating.sh test-template.txt) ; then
    echo
    echo "FAILED"
    exit 1
fi

echo "PASSED"


#!/bin/bash

# We mostly test if we can parse the outputfile and if it is not too short

if [ -z "$1" ]; then
    echo "No input file specified" >&2
    exit 1
fi

if [ -z $(command -v jq) ]; then
    echo "jq not installed" >&2
    exit 1
fi

echo -n "+ Checking if json is valid... "
out=$(jq < "${1}" 2>&1)
if [ $? -ne 0 ]; then
    echo "failed"
    echo "error: $out"
    echo "file contents"
    echo "==============================="
    cat "${1}"
    echo "==============================="
    exit 1
fi
echo "ok"

echo -n "+ Checking if we did output enough image data... "
out=$(jq < "${1}" | wc -l)
if [ $out -le 4 ]; then
    echo "failed"
    echo "==============================="
    echo "file contents: "
    echo "==============================="
    cat "${1}"
    exit 1
fi
echo "ok"

exit 0

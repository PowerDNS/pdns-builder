#!/bin/sh
# Test if rocky-8 RPM builds are reproducible
# Must be run from demo dir

set -ex

# First build
./builder/build.sh -B MYCOOLARG=iLikeTests rocky-8

# Record hashes
sha256sum \
    builder/tmp/latest/rocky-8/dist/noarch/*.rpm \
    builder/tmp/latest/sdist/*.tar.gz \
    > /tmp/sha256sum.txt

# Second build after cleaning and adding a file to invalidate the build context
rm -rf ./builder/tmp/latest/rocky-8
rm -rf ./builder/tmp/latest/sdist
./builder/build.sh -B MYCOOLARG=iLikeTests -b build-again rocky-8

# Check hashes, should be identical
sha256sum -c /tmp/sha256sum.txt


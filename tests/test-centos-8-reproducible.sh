#!/bin/sh
# Test if centos-8 RPM builds are reproducible
# Must be run from demo dir

set -ex

# First build
./builder/build.sh -B MYCOOLARG=iLikeTests centos-8

# Record hashes
sha256sum \
    builder/tmp/latest/centos-8/dist/noarch/*.rpm \
    builder/tmp/latest/sdist/*.tar.gz \
    > /tmp/sha256sum.txt

# Second build after cleaning and adding a file to invalidate the build context
rm -rf ./builder/tmp/latest/centos-8
rm -rf ./builder/tmp/latest/sdist
./builder/build.sh -B MYCOOLARG=iLikeTests -b build-again centos-8

# Check hashes, should be identical
sha256sum -c /tmp/sha256sum.txt


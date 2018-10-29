#!/bin/bash
# Prepare demo
# This copies the builder from the parent dir to a builder/ subdir.
# This is needed, because Docker will not include symlinked parent directories into the
# build context.

set -x
mkdir builder/
git tag 0.1.42
rsync -rv --exclude .git --exclude demo --exclude tmp --exclude cache --exclude tests ../ builder/

set +x
echo
echo "DONE. Now run ./builder/build.sh"

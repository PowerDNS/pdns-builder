#!/bin/bash

# TODO: remove this and replace it with the `meson rewrite`
# tooling pdns-recursor and dnsdist use.
sed -E -i -e "s/version: run_command.*/version: '${BUILDER_VERSION}',/" meson.build

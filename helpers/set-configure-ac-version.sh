#!/bin/bash

sed -E -i -e "s/AC_INIT[[( ]+([^]]+).*/AC_INIT([\1], [${BUILDER_VERSION}])/" configure.ac

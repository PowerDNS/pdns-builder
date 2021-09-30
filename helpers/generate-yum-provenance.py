#!/usr/bin/env python

"""
This script uses yum and rpm to generate in-toto material provenance and
writes the resulting JSON to stdout or to argv[0] if provided.
"""

from __future__ import print_function
import yum
import json
import sys
import urllib

yb = yum.YumBase()
yb.setCacheDir()

in_toto_data = list()
in_toto_fmt = "pkg:rpm/{origin}/{name}@{epoch}{version}-{release}?arch={arch}"

sack = yb.rpmdb
sack.preloadPackageChecksums()

for pkg in sack.returnPackages():
    in_toto_data.append(
        {
            "uri": in_toto_fmt.format(
                origin=urllib.quote(pkg.vendor),
                name=pkg.name,
                epoch=pkg.epoch + ':' if pkg.epoch != '0' else '',
                version=pkg.version,
                release=pkg.release,
                arch=pkg.arch
            ),
            "digest": {
                'sha256': pkg.yumdb_info.checksum_data
            }
        }
    )

if len(sys.argv) > 1:
    with open(sys.argv[1], 'w') as f:
        json.dump(in_toto_data, f)
else:
    print(json.dumps(in_toto_data))

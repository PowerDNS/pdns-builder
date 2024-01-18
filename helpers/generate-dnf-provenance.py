#!/usr/libexec/platform-python
"""
This script uses yum and rpm to generate in-toto material provenance and
writes the resulting JSON to stdout or to argv[0] if provided.
"""

import dnf
import json
import sys
import urllib.parse

in_toto_data = list()
in_toto_fmt = "pkg:rpm/{origin}/{name}@{epoch}{version}-{release}?arch={arch}"

with dnf.Base() as db:
    db.fill_sack()
    q = db.sack.query()

    for pkg in q.installed():
        in_toto_data.append(
            {
                "uri": in_toto_fmt.format(
                    origin=urllib.parse.quote(pkg.vendor),
                    name=pkg.name,
                    epoch=str(pkg.epoch) + ':' if pkg.epoch != 0 else '',
                    version=pkg.version,
                    release=pkg.release,
                    arch=pkg.arch
                ),
                "digest": {
                    # The DNF documentation says:
                    #     The checksum is returned only for packages from
                    #     repository. The checksum is not returned for
                    #     installed package or packages from commandline
                    #     repository.
                    # Which is super lame, so we use the header checksum to
                    # have _something_.
                    'sha1': pkg.hdr_chksum[1].hex()
                }
            }
        )

if len(sys.argv) > 1:
    with open(sys.argv[1], 'w') as f:
        json.dump(in_toto_data, f)
else:
    print(json.dumps(in_toto_data))

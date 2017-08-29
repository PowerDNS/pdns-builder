#!/bin/bash
# Build multiple rpm specs, after installing the build dependencies

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

specs=()
for spec in "$@"; do
    # If BUILDER_PACKAGE_MATCH is set, only build the specs that match, otherwise build all
    if [ -z "$BUILDER_PACKAGE_MATCH" ] || [[ $spec = *$BUILDER_PACKAGE_MATCH* ]]; then
        specs+=($spec)
    fi
done

if [ "${#specs[@]}" = "0" ]; then
    echo "No specs matched, nothing to do"
    exit 0
fi

# Parse the specfiles to evaluate conditionals for builddeps, and store them in tempfiles
# Also check for specs we need to skip (BUILDER_SKIP)
tmpdir=$(mktemp -d /tmp/build-specs.parsed.XXXXXX)
trap "rm -rf -- '$tmpdir'" INT TERM HUP EXIT
declare -A skip_specs # associative array (dict)
if [ -x /usr/bin/rpmspec ]; then
    # RHEL >= 7 has this tool
    for spec in "${specs[@]}"; do
        name=$(basename "$spec")
        tmpfile="$tmpdir/$name"
        rpmspec -P "$spec" > "$tmpfile"
        if grep --silent 'BUILDER_SKIP' "$tmpfile"; then
            echo "BUILDER_SKIP: $spec will be skipped"
            skip_specs["$spec"]=1
            rm -f "$tmpfile"
        fi
    done
    reqs=`$helpers/buildrequires-from-specs $tmpdir/*.spec`
else
    # For RHEL 6 let's just try to install all we find
    # You can add 'BUILDER_EL6_SKIP' somewhere in the spec to skip it (comment is ok for this one)
    reqs=`$helpers/buildrequires-from-specs "${specs[@]}"`
    for spec in "${specs[@]}"; do
        if grep --silent 'BUILDER_EL6_SKIP' "$spec"; then
            echo "BUILDER_EL6_SKIP: $spec will be skipped"
            skip_specs["$spec"]=1
        fi
    done
fi

set -ex

if [ ! -z "$reqs" ]; then
    yum install -y $reqs
fi

for spec in "${specs[@]}"; do
    echo "==================================================================="
    echo "-> $spec"
    if [ -z "${skip_specs[$spec]}" ]; then
        # Download sources
        spectool -g -R "$spec"
        # Build the rpm
        rpmbuild --define "_sdistdir /sdist" -bb "$spec"
    else
        echo "Skipping spec (BUILDER_SKIP)"
    fi
done


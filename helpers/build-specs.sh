#!/bin/bash
# Build multiple rpm specs, after installing the build dependencies

set -e # exit on helper error

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "$helpers/functions.sh"

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

# Used for caching rpms between builds
rpm_file_root=/root/rpmbuild/RPMS/
function rpm_file_list {
    find "$rpm_file_root" -type f | sed "s|$rpm_file_root||" | sort
}
function file_hash {
    local spec="$1"
    local n=$(basename "$spec" .spec)
    local h=$(sha1sum "$1" | cut -d' ' -f1)
    echo "$n.$h"
}
function check_cache {
    local spec="$1"
    local h=$(file_hash "$spec")
    if [ -f "/cache/old/$h.tar" ]; then
        echo "* FOUND IN CACHE: $spec"
        tar -C "$rpm_file_root" -xvf "/cache/old/$h.tar"
        return 0
    fi
    return 1
}
cache=
if [ ! -z "$BUILDER_CACHE" ] && [ ! -z "$BUILDER_CACHE_THIS" ]; then
    cache=1
    mkdir -p /cache/new
fi

set_rpm_versions
set_python_src_versions
# Parse the specfiles to evaluate conditionals for builddeps, and store them in tempfiles
# Also check for specs we need to skip (BUILDER_SKIP)
tmpdir=$(mktemp -d /tmp/build-specs.parsed.XXXXXX)
trap "rm -rf -- '$tmpdir'" INT TERM HUP EXIT
declare -A skip_specs # associative array (dict)
if [ -x /usr/bin/rpmspec ]; then
    # RHEL >= 7 has this tool
    for spec in "${specs[@]}"; do
        # First check if we have the rpms cached
        if [ "$cache" = "1" ] && check_cache "$spec"; then
            skip_specs["$spec"]=1
            echo "::: $spec (cached)"
            continue
        fi

        name=$(basename "$spec")
        tmpfile="$tmpdir/$name"
        rpmspec -P "$spec" > "$tmpfile"
        if grep --silent 'BUILDER_SKIP' "$tmpfile"; then
            echo "BUILDER_SKIP: $spec will be skipped"
            skip_specs["$spec"]=1
            rm -f "$tmpfile"
        fi
    done
    touch "$tmpdir/__empty.spec" # To prevent an error because of an empty dir
    reqs=`$helpers/buildrequires-from-specs $tmpdir/*.spec`
else
    # For RHEL 6 let's just try to install all we find
    # You can add 'BUILDER_EL6_SKIP' somewhere in the spec to skip it (comment is ok for this one)
    reqs=`$helpers/buildrequires-from-specs "${specs[@]}"`
    for spec in "${specs[@]}"; do
        # First check if we have the rpms cached
        if [ "$cache" = "1" ] && check_cache "$spec"; then
            skip_specs["$spec"]=1
            continue
        fi

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

function new_rpms {
    diff -u /tmp/rpms-before /tmp/rpms-after | tee /tmp/rpms-diff | grep -v '^[+][+]' | grep '^[+]' | sed 's/^[+]//'
}

rpmbuild_options=""
if [ -n "${BUILDER_SKIP_CHECKS}" ]; then
    rpmbuild_options="--nocheck"
fi

for spec in "${specs[@]}"; do
    echo "==================================================================="
    echo "-> $spec"
    if [ -z "${skip_specs[$spec]}" ]; then
        echo "::: $spec"

        if [ -n "${BUILDER_EPOCH}" ] && grep -q BUILDER_RPM_VERSION "$spec"; then
          sed -i "/Name:/a Epoch: ${BUILDER_EPOCH}" "$spec"
        fi

        # Use the modification time of the spec file as the SOURCE_DATE_EPOCH if
        # BUILDER_SOURCE_DATE_FROM_SPEC_MTIME is set. This is useful for vendor packages
        # that have independent versioning.
        if [ -n "${BUILDER_SOURCE_DATE_FROM_SPEC_MTIME}" ]; then
            SOURCE_DATE_EPOCH=$(stat -c '%Y' "$spec")
            export SOURCE_DATE_EPOCH
        fi

        # Download sources
        spectool -g -R "$spec"

        # Build the rpm and record which files are new
        rpm_file_list > /tmp/rpms-before
        # NOTE: source_date_epoch_from_changelog is always overridden by SOURCE_DATE_EPOCH if that is set.
        # See https://fossies.org/linux/rpm/build/build.c#l_298
        rpmbuild \
            ${rpmbuild_options} \
            --define "_sdistdir /sdist" \
            --define "_buildhost reproducible" \
            --define "source_date_epoch_from_changelog Y" \
            --define "clamp_mtime_to_source_date_epoch Y" \
            --define "use_source_date_epoch_as_buildtime Y" \
            -ba "$spec"
        rpm_file_list > /tmp/rpms-after

        new_rpms | sed 's/^/NEW: /'
        cat /tmp/rpms-diff | sed 's/^/DIFF: /'
        if [ "$cache" = "1" ]; then
            h=$(file_hash "$spec")
            tar -C "$rpm_file_root" -cvf "/cache/new/$h.tar" $(new_rpms)
        fi
    else
        echo "Skipping spec (BUILDER_SKIP or in cache)"
    fi
done

#!/bin/bash
# Build debian packages, after installing dependencies
# This assumes the source is unpacked and a debian/ directory exists

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "$helpers/functions.sh"

dirs=()
for dir in "$@"; do
  # If BUILDER_PACKAGE_MATCH is set, only build the packages that match, otherwise build all
  if [ -z "$BUILDER_PACKAGE_MATCH" ] || [[ $dir = *$BUILDER_PACKAGE_MATCH* ]]; then
    if [ ! -d ${dir}/debian ]; then
      echo "${dir}/debian does not exist, can not build!"
      continue
    fi
    dirs+=($dir)
  fi
done

if [ "${#dirs[@]}" = "0" ]; then
    echo "No debian package directories matched, nothing to do"
    exit 0
fi

for dir in "${dirs[@]}"; do
  # Install all build-deps
  pushd "${dir}"
  mk-build-deps -i -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' || exit 1
  popd
done

for dir in "${dirs[@]}"; do
  echo "==================================================================="
  echo "-> ${dir}"
  pushd "${dir}"
  # If there's a changelog, this is probably a vendor dependency or versioned
  # outside of pdns-builder
  if [ ! -f debian/changelog ]; then
    # Parse the Source name
    sourcename=`grep '^Source: ' debian/control | sed 's,^Source: ,,'`
    if [ -z "${sourcename}" ]; then
      echo "Unable to parse name of the source from ${dir}"
      exit 1
    fi
    # Let's try really hard to find the release name of the distribution
    # Prefer something that sorts well over time
    distro_release="$(source /etc/os-release; [ ! -z ${ID} ] && [ ! -z ${VERSION_ID} ] && echo -n ${ID}${VERSION_ID})" # this will look like 'debian12' or 'ubuntu22.04'
    if [ -z "${distro_release}" ]; then
      # we should only end up here on Debian Testing
      distro="$(source /etc/os-release; echo -n ${ID})"
      if [ ! -z "${distro}" ]; then
        releasename="$(perl -n -e '/PRETTY_NAME="Debian GNU\/Linux (.*)\/sid"/ && print $1' /etc/os-release)"
        if [ ! -z "${releasename}" ]; then
          apt-get -y --no-install-recommends install distro-info-data
          releasenum="$(grep ${releasename} /usr/share/distro-info/debian.csv | cut -f1 -d,)"
          if [ ! -z "${releasenum}" ]; then
            distro_release="${distro}${releasenum}"
          fi
        fi
      fi
    fi
    if [ -z "${distro_release}" ]; then
      echo 'Unable to determine distribution codename!'
      exit 1
    fi
    if [ -z "$BUILDER_EPOCH" ]; then
      epoch_string=""
    else
      epoch_string="${BUILDER_EPOCH}:"
    fi
    echo "EPOCH_STRING=${epoch_string}"
    set_debian_versions
    cat > debian/changelog << EOF
$sourcename (${epoch_string}${BUILDER_DEB_VERSION}-${BUILDER_DEB_RELEASE}.${distro_release}) unstable; urgency=medium

  * Automatic build

 -- PowerDNS.COM AutoBuilder <noreply@powerdns.com>  $(date -R)
EOF
  fi

  # allow build to use all available processors
  export DEB_BUILD_OPTIONS='parallel='`nproc`

  dpkg-buildpackage -b || exit 1
  popd
done

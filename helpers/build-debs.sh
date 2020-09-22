#!/bin/bash
# Build debian packages, after installing dependencies
# This assumes the the source is unpacked and a debian/ directory exists

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
    distro_release="$(source /etc/os-release; printf ${VERSION_CODENAME})"
    if [ -z "${distro_release}" -a -n "$(grep 'VERSION_ID="14.04"' /etc/os-release)" ]; then
      distro_release='trusty'
    fi
    if [ -z "${distro_release}" ]; then
      distro_release="$(perl -n -e '/VERSION=".* \((.*)\)"/ && print $1' /etc/os-release)"
    fi
    if [ -z "${distro_release}" ]; then
      distro_release="$(perl -n -e '/PRETTY_NAME="Debian GNU\/Linux (.*)\/sid"/ && print $1' /etc/os-release)"
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

  if [ -n "$BUILDER_PARALLEL" ]; then
      export DEB_BUILD_OPTIONS="parallel=$BUILDER_PARALLEL"
  fi
  fakeroot debian/rules binary || exit 1
  popd
done

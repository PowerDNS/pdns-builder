#!/bin/bash
# Build debian packages, after installing dependencies
# This assumes the the source is unpacked and a debian/ directory exists

helpers=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

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
    echo 'Unable to determine distribution codename!'
    exit 1
  fi
  cat > debian/changelog << EOF
$sourcename (${BUILDER_VERSION}-${BUILDER_RELEASE}.${distro_release}) unstable; urgency=medium

  * Automatic build

 -- PowerDNS.COM AutoBuilder <noreply@powerdns.com>  $(date -R)
EOF

  fakeroot debian/rules binary || exit 1
  popd
done

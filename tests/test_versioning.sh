#!/bin/bash

exitcode=0
assert_equal() {
  if [ "$2" != "$3" ]; then
    echo "${1}: ${2} != ${3}"
    exitcode=1
  fi
}

set -e

source "helpers/functions.sh"

builder_release='1pdns'

src_versions=(1.0.0
              1.0.0.dirty
              1.0.0-beta1
              1.0.0-beta1.dirty
              1.1.0-rc2.0.g123456
              1.1.0-rc2.0.g123456.dirty
              1.1.0.15.g123456
              1.1.0.15.g123456.dirty
              1.1.0.15.branchname.g123456
              1.1.0.15.branchname.g123456.dirty
              1.2.0-alpha1.10.branch.g123456
              1.2.0-alpha1.10.branch.g123456.dirty
              1.2.3.130.HEAD.gbac839b2)
deb_versions=(1.0.0
              1.0.0+dirty
              1.0.0~beta1
              1.0.0~beta1+dirty
              1.1.0~rc2+0.g123456
              1.1.0~rc2+0.g123456.dirty
              1.1.0+15.g123456
              1.1.0+15.g123456.dirty
              1.1.0+branchname.15.g123456
              1.1.0+branchname.15.g123456.dirty
              1.2.0~alpha1+branch.10.g123456
              1.2.0~alpha1+branch.10.g123456.dirty
              1.2.3+HEAD.130.gbac839b2)
rpm_versions=(1.0.0
              1.0.0
              1.0.0
              1.0.0
              1.1.0
              1.1.0
              1.1.0
              1.1.0
              1.1.0
              1.1.0
              1.2.0
              1.2.0
              1.2.3)
rpm_releases=($builder_release
              dirty.$builder_release
              0.beta1.$builder_release
              0.beta1.dirty.$builder_release
              0.rc2.0.g123456.$builder_release
              0.rc2.0.g123456.dirty.$builder_release
              15.g123456.$builder_release
              15.g123456.dirty.$builder_release
              branchname.15.g123456.$builder_release
              branchname.15.g123456.dirty.$builder_release
              0.alpha1.branch.10.g123456.$builder_release
              0.alpha1.branch.10.g123456.dirty.$builder_release
              HEAD.130.gbac839b2.$builder_release)

# These comply to PEP 440
py_versions=(1.0.0
             1.0.0+dirty
             1.0.0b1
             1.0.0b1+dirty
             1.1.0rc2+0.g123456
             1.1.0rc2+0.g123456.dirty
             1.1.0+15.g123456
             1.1.0+15.g123456.dirty
             1.1.0+15.branchname.g123456
             1.1.0+15.branchname.g123456.dirty
             1.2.0a1+10.branch.g123456
             1.2.0a1+10.branch.g123456.dirty
             1.2.3+130.head.gbac839b2)

for ctr in ${!src_versions[@]}; do
  BUILDER_VERSION=${src_versions[$ctr]}
  BUILDER_RELEASE=$builder_release
  set_debian_versions
  assert_equal BUILDER_DEB_VERSION $BUILDER_DEB_VERSION ${deb_versions[$ctr]}
  assert_equal BUILDER_DEB_RELEASE $BUILDER_DEB_RELEASE $builder_release

  set_rpm_versions
  assert_equal BUILDER_RPM_VERSION $BUILDER_RPM_VERSION ${rpm_versions[$ctr]}
  assert_equal BUILDER_RPM_RELEASE $BUILDER_RPM_RELEASE ${rpm_releases[$ctr]}

  set_python_src_versions
  assert_equal BUILDER_PYTHON_SRC_VERSION $BUILDER_PYTHON_SRC_VERSION ${py_versions[$ctr]}

  assert_equal BUILDER_VERSION $BUILDER_VERSION ${src_versions[$ctr]}
  assert_equal BUILDER_RELEASE $BUILDER_RELEASE $builder_release
done

exit "$exitcode"

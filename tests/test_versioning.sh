#!/bin/bash

assert_equal() {
  if [ "$1" != "$2" ]; then
    echo "${1} != ${2}"
    exit 1
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
              1.2.0-alpha1.10.branch.g123456.dirty)
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
              1.2.0~alpha1+branch.10.g123456.dirty)
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
              1.2.0)
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
              0.alpha1.branch.10.g123456.dirty.$builder_release)

# note, these do not comply to PEP 440
py_versions=(1.0.0
             1.0.0.dirty
             1.0.0b1
             1.0.0-beta1.dirty
             1.1.0-rc2.0.g123456
             1.1.0-rc2.0.g123456.dirty
             1.1.0.15.g123456
             1.1.0.15.g123456.dirty
             1.1.0.15.branchname.g123456
             1.1.0.15.branchname.g123456.dirty
             1.2.0-alpha1.10.branch.g123456
             1.2.0-alpha1.10.branch.g123456.dirty)

for ctr in ${!src_versions[@]}; do
  BUILDER_VERSION=${src_versions[$ctr]}
  BUILDER_RELEASE=$builder_release
  set_debian_versions
  assert_equal $BUILDER_DEB_VERSION ${deb_versions[$ctr]}
  assert_equal $BUILDER_DEB_RELEASE $builder_release

  set_rpm_versions
  assert_equal $BUILDER_RPM_VERSION ${rpm_versions[$ctr]}
  assert_equal $BUILDER_RPM_RELEASE ${rpm_releases[$ctr]}

  set_python_src_versions
  assert_equal $BUILDER_PYTHON_SRC_VERSION ${py_versions[$ctr]}

  assert_equal $BUILDER_VERSION ${src_versions[$ctr]}
  assert_equal $BUILDER_RELEASE $builder_release
done

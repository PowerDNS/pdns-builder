# https://stackoverflow.com/questions/1527049/join-elements-of-an-array#17841619
function join_by { local IFS="$1"; shift; echo "$*"; }

set_debian_versions() {
  # Examples (BUILDER_RELEASE before is assumed to be 1pdns
  # BUILDER_VERSION                BUILDER_DEB_VERSION after    BUILDER_DEB_RELEASE after
  # 1.2.3                       => 1.2.3                        1pdns
  # 1.2.3.0.g123456             => 1.2.3+0.g123456              1pdns
  # 1.2.3-alpha1                => 1.2.3~alpha1                 1pdns
  # 1.2.3-alpha1.0.g123456      => 1.2.3~alpha1+0.g123456       1pdns
  # 1.2.3-alpha1.15.g123456     => 1.2.3~alpha1+15.g123456      1pdns
  # 1.2.3-rc2.12.branch.g123456 => 1.2.3~rc2+branch.12.g123456  1pdns
  # 1.2.3.15.mybranch.g123456   => 1.2.3+mybranch.15.g123456    1pdns
  # 1.2.3.15.g123456            => 1.2.3+15.g123456             1pdns
  OIFS=$IFS
  IFS='-' version_elems=($BUILDER_VERSION)
  IFS=$OIFS
  version=''
  if [ ${#version_elems[@]} -gt 1 ]; then
    version=${version_elems[0]}
    OIFS=$IFS
    IFS='.' version_elems=(${version_elems[1]})
    IFS=$OIFS

    # version_elems now contains e.g.
    # alpha1
    # alpha1 15 g123456
    # alpha1 15 mybranch g123456
    version="${version}~${version_elems[0]}"
    if [ ${#version_elems[@]} -eq 3 ]; then
      version="${version}+$(join_by . ${version_elems[@]:1})"
    elif [ ${#version_elems[@]} -eq 4 ]; then
      version="${version}+${version_elems[2]}.${version_elems[1]}.${version_elems[3]}"
    fi
  else
    OIFS=$IFS
    IFS='.' version_elems=(${BUILDER_VERSION})
    IFS=$OIFS
    # version_elems now contains e.g.
    # 1 2 3
    # 1 2 3 15 g123456
    # 1 2 3 15 mybranch g123456
    version=$(join_by . ${version_elems[@]:0:3})
    if [ ${#version_elems[@]} -eq 5 ]; then
      version="${version}+$(join_by . ${version_elems[@]:3})"
    elif [ ${#version_elems[@]} -eq 6 ]; then
      version="${version}+${version_elems[4]}.${version_elems[3]}.${version_elems[5]}"
    fi
  fi
  export BUILDER_DEB_VERSION=$version
  export BUILDER_DEB_RELEASE=${BUILDER_RELEASE}
}

set_rpm_versions() {
  # Examples (BUILDER_RELEASE before is assumed to be 1pdns
  # BUILDER_VERSION                BUILDER_RPM_VERSION after  BUILDER_RPM_RELEASE after
  # 1.2.3                       => 1.2.3                      1pdns
  # 1.2.3.0.g123456             => 1.2.3                      0.g123456.1pdns
  # 1.2.3-alpha1                => 1.2.3                      0.alpha1.1pdns
  # 1.2.3-alpha1.0.g123456      => 1.2.3                      0.alpha1.0.g12456.1pdns
  # 1.2.3-alpha1.15.g123456     => 1.2.3                      0.alpha1.15.g12456.1pdns
  # 1.2.3-rc2.12.branch.g123456 => 1.2.3                      0.rc2.branch.12.g123456.1pdns
  # 1.2.3.15.mybranch.g123456   => 1.2.3                      mybranch.15.g123456.1pdns
  # 1.2.3.15.g123456            => 1.2.3                      15.g123456.1pdns
  OIFS=$IFS
  IFS='-' version_elems=($BUILDER_VERSION)
  IFS=$OIFS
  prerel=''
  if [ ${#version_elems[@]} -gt 1 ]; then
    # There's a dash in the version number, indicating a pre-release
    # Take the version number
    BUILDER_RPM_VERSION=${version_elems[0]}
    OIFS=$IFS
    IFS='.' version_elems=(${version_elems[1]})
    IFS=$OIFS
    prerel="0.${version_elems[0]}."
    version_elems=(${version_elems[@]:1})
  else
    OIFS=$IFS
    IFS='.' version_elems=(${version_elems})
    IFS=$OIFS
    BUILDER_RPM_VERSION=$(join_by . ${version_elems[@]:0:3})
    version_elems=(${version_elems[@]:3})
  fi

  # version_elems now contains everything _after_ the version, sans pre-release info
  # e.g.
  # (empty)
  # 0 g123456
  # 12 branch g123456
  release=''
  if [ ${#version_elems[@]} -eq 0 ]; then
    # This is a release
    export BUILDER_RPM_RELEASE="${prerel}${BUILDER_RELEASE}"
  elif [ ${#version_elems[@]} -gt 2 ]; then
    # we have branch info
    export BUILDER_RPM_RELEASE="${prerel}${version_elems[1]}.${version_elems[0]}.${version_elems[2]}.${BUILDER_RELEASE}"
  else
    export BUILDER_RPM_RELEASE="${prerel}${version_elems[0]}.${version_elems[1]}.${BUILDER_RELEASE}"
  fi
  export BUILDER_RPM_VERSION
}

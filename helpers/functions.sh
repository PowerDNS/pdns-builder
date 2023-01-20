# https://stackoverflow.com/questions/1527049/join-elements-of-an-array#17841619
function join_by { local IFS="$1"; shift; echo "$*"; }

set_python_src_versions() {
  # setuptools is very strict about PEP 440
  # See https://peps.python.org/pep-0440/

  # BUILDER_VERSION                BUILDER_PYTHON_SRC_VERSION
  # 1.2.3                       => 1.2.3
  # 1.2.3.dirty                 => 1.2.3+dirty
  # 1.2.3.0.g123456             => 1.2.3+0.g123456
  # 1.2.3-alpha1                => 1.2.3a1
  # 1.2.3-alpha1.0.g123456      => 1.2.3a1+0.g123456
  # 1.2.3-alpha1.15.g123456     => 1.2.3a1+15.g123456
  # 1.2.3-rc2.12.branch.g123456 => 1.2.3rc2+branch.12.g123456
  # 1.2.3.15.mybranch.g123456   => 1.2.3+15.mybranch.g123456
  # 1.2.3.15.g123456            => 1.2.3+15.g123456
  # 1.2.3.15.g123456.dirty      => 1.2.3+15.g123456.dirty
  # 1.2.3.130.HEAD.gbac839b2    => 1.2.3+130.head.gbac839b2
  export BUILDER_PYTHON_SRC_VERSION="$(echo ${BUILDER_VERSION} | perl -pe 's,-alpha([0-9]+),a\1+,' | perl -pe 's,-beta([0-9]+),b\1+,' | perl -pe 's,-rc([0-9]+),rc\1+,' | perl -pe 's,\+$,,' | perl -pe 's,\+\.,+,' | perl -pe 's,^([0-9]+\.[0-9]+\.[0-9]+)\.(.*)$,\1+\2,' | tr A-Z a-z )"
}

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
    # alpha1 dirty
    # alpha1 15 g123456
    # alpha1 15 g123456 dirty
    # alpha1 15 mybranch g123456
    # alpha1 15 mybranch g123456 dirty
    version="${version}~${version_elems[0]}"
    if [ ${#version_elems[@]} -eq 2 ]; then
      version="${version}+$(join_by . ${version_elems[@]:1})"
    fi
    if [ ${#version_elems[@]} -ge 3 ]; then
      if [[ "${version_elems[2]}" =~ ^g[0-9a-e]+ ]]; then
        version="${version}+$(join_by . ${version_elems[@]:1})"
      else
        version="${version}+${version_elems[2]}.${version_elems[1]}.$(join_by . ${version_elems[@]:3})"
      fi
    fi
  else
    OIFS=$IFS
    IFS='.' version_elems=(${BUILDER_VERSION})
    IFS=$OIFS
    # version_elems now contains e.g.
    # 1 2 3
    # 1 2 3 15 g123456
    # 1 2 3 15 g123456 dirty
    # 1 2 3 15 mybranch g123456
    # 1 2 3 15 mybranch g123456 dirty
    version=$(join_by . ${version_elems[@]:0:3})
    if [ ${#version_elems[@]} -eq 4 ]; then
      version="${version}+$(join_by . ${version_elems[@]:3})"
    fi
    if [ ${#version_elems[@]} -ge 5 ]; then
      if [[ "${version_elems[4]}" =~ ^g[0-9a-e]+ ]]; then
        version="${version}+$(join_by . ${version_elems[@]:3})"
      else
        version="${version}+${version_elems[4]}.${version_elems[3]}.$(join_by . ${version_elems[@]:5})"
      fi
    fi
  fi
  export BUILDER_DEB_VERSION=$version
  export BUILDER_DEB_RELEASE=${BUILDER_RELEASE}
}

set_rpm_versions() {
  # Examples (BUILDER_RELEASE before is assumed to be 1pdns
  # BUILDER_VERSION                BUILDER_RPM_VERSION after  BUILDER_RPM_RELEASE after
  # 1.2.3                       => 1.2.3                      1pdns
  # 1.2.3.dirty                 => 1.2.3                      dirty.1pdns
  # 1.2.3.0.g123456             => 1.2.3                      0.g123456.1pdns
  # 1.2.3.0.g123456.dirty       => 1.2.3                      0.g123456.dirty.1pdns
  # 1.2.3-alpha1                => 1.2.3                      0.alpha1.1pdns
  # 1.2.3-alpha1.dirty          => 1.2.3                      0.alpha1.dirty.1pdns
  # 1.2.3-alpha1.0.g123456      => 1.2.3                      0.alpha1.0.g12456.1pdns
  # 1.2.3-alpha1.0.g123456.dirty=> 1.2.3                      0.alpha1.0.g12456.dirty.1pdns
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
  # dirty
  # 0 g123456
  # 12 g123456 dirty
  # 12 branch g123456
  # 12 branch g123456 dirty
  release=''
  if [ ${#version_elems[@]} -eq 0 ]; then
    # This is a release
    export BUILDER_RPM_RELEASE="${prerel}${BUILDER_RELEASE}"
  elif [ ${#version_elems[@]} -le 2 ]; then
    export BUILDER_RPM_RELEASE="${prerel}$(join_by . ${version_elems[@]}).${BUILDER_RELEASE}"
  else
    if [[ "${version_elems[1]}" =~ ^g[0-9a-e]+ ]]; then
      export BUILDER_RPM_RELEASE="${prerel}$(join_by . ${version_elems[@]}).${BUILDER_RELEASE}"
    else
      export BUILDER_RPM_RELEASE="${prerel}${version_elems[1]}.${version_elems[0]}.$(join_by . ${version_elems[@]:2}).${BUILDER_RELEASE}"
    fi
  fi
  export BUILDER_RPM_VERSION
}

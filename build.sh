#!/bin/bash
# Main package builder

function get_ts() {
  if $(which date > /dev/null 2>&1); then
    date +%s
  else
    printf '%(%s)T'
  fi
}

function get_date() {
  if $(which date > /dev/null 2>&1); then
    date +%Y%m%d-%H%M%S
  else
    printf '%(%Y%m%d-%H%M%S)T'
  fi
}

t_start="$(get_ts)"

# Use colors if stdout is a tty
if [ -t 1 ]; then
    color_reset='\x1B[0m'
    color_red='\x1B[1;31m'
    color_green='\x1B[1;32m'
    color_white='\x1B[1;37m'
    color_white_e=`echo -e "$color_white"`
    color_reset_e=`echo -e "$color_reset"`
fi

#######################################################################
# Check the environment we are running in
#

export BUILDER_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ "`basename "$BUILDER_ROOT"`" != "builder" ]; then
    # Maybe we can relax this, but would make the dockerfiles less consistent
    echo "ERROR: The builder must live in builder/"
    exit 1
fi

# Must run from repo root
export BUILDER_REPO_ROOT=`dirname "$BUILDER_ROOT"`
cd "$BUILDER_REPO_ROOT" || exit 1

export BUILDER_SUPPORT_ROOT="$BUILDER_REPO_ROOT/builder-support"
if [ ! -d "$BUILDER_SUPPORT_ROOT" ]; then
    # Maybe we can relax this, but would make the dockerfiles less consistent
    echo "ERROR: Could not find support files: $BUILDER_SUPPORT_ROOT"
    exit 1
fi

# Safe name for docker image tagging (replace unsafe chars by '-')
repo_safe_name=`basename "$BUILDER_REPO_ROOT" | sed 's/[^a-zA-Z0-9-]/-/g'`

# Some path sanity checks
if [ -z "$BUILDER_ROOT" ] || [ -z "$BUILDER_REPO_ROOT" ] || [ -z "$BUILDER_SUPPORT_ROOT" ] || [ -z "$repo_safe_name" ]; then
    echo "ERROR: Path sanity checks failed"
    exit 1
fi

export BUILDER_TMP="$BUILDER_ROOT/tmp"

# sed: turn off buffering or enable line buffering
if sed --version > /dev/null 2>&1; then
    # GNU sed
    sed_nobuf="-u"
else
    # assume BSD sed (only tested on macOS)
    sed_nobuf="-l"
fi

#######################################################################
# Parse arguments and load optional .env file
#

usage() {
    echo "Builds packages in Docker or Kaniko for a target distribution, or sdist for generic source packages."
    echo "By default, docker is used. This program calls 'docker', aliasing 'podman' to 'docker' will use podman"
    echo
    echo "USAGE:    $0 [OPTIONS] <target>"
    echo
    echo "Depending on the mode (docker or kaniko) several options are available."
    echo
    echo "Mode options:"
    echo "  -K              - Use kaniko instead of docker (expects '/kaniko/executor' to exist)."
    echo
    echo "Options shared between modes:"
    echo "  -B ARG=VAL      - Add extra build arguments, can be passed more than once"
    echo "  -V VERSION      - Override version (default: run gen-version)"
    echo "  -R RELEASE      - Override release tag (default: '1pdns', do not include %{dist} here)"
    echo "  -m MODULES      - Build only specific components (comma separated; warning: this disables install tests)"
    echo "  -e EPOCH        - Set a specific version Epoch for RPM/DEB packages"
    echo "  -b VALUE        - Docker cache buster, set to 'always', 'daily', 'weekly' or a literal value."
    echo "  -p PACKAGENAME  - Build only spec files that have this string in their name (warning: this disables install tests)"
    echo "  -q              - Be more quiet. Build error details are still printed on build error."
    echo "  -v              - Always show full build output (default: only steps and build error details)"
    echo "  -c              - Enable builder package cache"
    echo "  -s              - Skip install tests"
    echo "  -S              - Force running of install tests, even if this is not a full build"
    echo
    echo "Docker mode options, ignored in kaniko mode:"
    echo "  -C              - Run docker build with --no-cache"
    echo "  -L <limit>=<softlimit>:<hardlimit> - Overrides the default docker daemon ulimits, can be passed more than once"
    echo "  -P              - Run docker build with --pull"
    echo
    echo "Kaniko mode options, ignored in docker mode:"
    echo "  -k URL          - Use URL as the cache for kaniko layers."
    echo "  -r URL          - Use URL as registry mirror"
    echo
    echo "Targets:"
    ls -1 $BUILDER_SUPPORT_ROOT/dockerfiles/Dockerfile.target.* | sed 's/.*Dockerfile.target.//' | sed 's/^/  /' | sort -V

    echo
    [ -f "$BUILDER_SUPPORT_ROOT/usage.include.txt" ] && cat "$BUILDER_SUPPORT_ROOT/usage.include.txt"
    exit 1
}

if [ -f .env ]; then
    # Cannot be directly sourced, because values with spaces are not quoted
    # The sed expression removed comments and blank lines, and quotes values
    eval $(cat .env | sed  '/^$/d; /^#/d; s/=\(.*\)$/="\1"/')
fi

_version=""
declare -a dockeropts
declare -a ulimitargs
declare -a buildargs
verbose=""
quiet=""
dockeroutdev=/dev/stdout
forcetests=
buildmode=docker
declare -a kanikoargs

# RPM release tag (%{dist} will always be appended)
export BUILDER_RELEASE=1pdns

# Modules to build
export M_all=1

# Modules to expose to a custom gen-version
BUILDER_MODULES=''

package_match=""
cache_buster=""

while getopts ":CcKk:V:R:svqm:Pp:b:e:B:L:r:" opt; do
    case $opt in
    C)  dockeropts+=('--no-cache')
        ;;
    c)  export BUILDER_CACHE=1
        ;;
    V)  _version="$OPTARG"
        ;;
    R)  export BUILDER_RELEASE="$OPTARG"
        ;;
    e)  export BUILDER_EPOCH="$OPTARG"
        ;;
    s)  export skiptests=1
        echo "NOTE: Skipping install tests, as requested with -s"
        ;;
    S)  export forcetests=1
        ;;
    v)  verbose=1
        ;;
    q)  quiet=1
        dockeroutdev=/dev/null
        ;;
    m)  export M_all=
        export skiptests=1
        echo -e "${color_red}WARNING: Skipping install tests, because not all components are being built${color_reset}"
        BUILDER_MODULES="${OPTARG}"
        IFS=',' read -r -a modules <<< "$OPTARG"
        for m in "${modules[@]}"; do
            export M_$m=1
            echo "enabled module: $m"
        done
        ;;
    P)  dockeropts+=('--pull')
        ;;
    p)  package_match="$OPTARG"
        export skiptests=1
        echo -e "${color_red}WARNING: Skipping install tests, because not all packages are being built${color_reset}"
        ;;
    b)  cache_buster="$OPTARG"
        ;;
    B)  buildargs+=("--build-arg" "${OPTARG}")
        ;;
    K)  buildmode=kaniko
        ;;
    k)  if [[ "${kanikoargs[@]}" =~ "--cache=true" ]]; then
          echo "-k can only be set once" >&2
          exit 1
        fi
        kanikoargs+=("--cache=true")
        kanikoargs+=("--cache-repo=${OPTARG}")
        ;;
    r)  kanikoargs+=("--registry-mirror=${OPTARG}")
        ;;
    L)  ulimitargs+=("--ulimit" "${OPTARG}")
        ;;
    \?) echo "Invalid option: -$OPTARG" >&2
        usage
        ;;
    :)  echo "Missing required argument for -$OPTARG" >&2
        usage
        ;;
    esac
done
shift $((OPTIND-1))

if [ "$skiptests" = "1" ] && [ "$forcetests" = "1" ]; then
    export skiptests=""
    echo -e "${color_red}WARNING: Force running of install tests without a full build${color_reset}"
fi

cache_buster_value=""
case ${cache_buster} in
always) cache_buster_value=$(date +%s)     ;;
daily)  cache_buster_value=$(date +%F)     ;;
weekly) cache_buster_value=$(date +%Y-%W)  ;;
*)      cache_buster_value=${cache_buster} ;;
esac

# Build target distribution
target="$1"
[ "$target" = "" ] && usage
template="Dockerfile.target.$target"
templatepath="$BUILDER_SUPPORT_ROOT/dockerfiles/$template"
if [ ! -f "$templatepath" ]; then
    echo -e "${color_red}ERROR: invalid target${color_reset}"
    echo
    usage
fi

# Exit on error
set -e

# Set version
if [ "$_version" == "" ]; then
    if [ -x "$BUILDER_SUPPORT_ROOT/gen-version" ]; then
        # Allows a repo to provide a custom gen-version script
        BUILDER_VERSION=$(BUILDER_MODULES="${BUILDER_MODULES}" "$BUILDER_SUPPORT_ROOT/gen-version")
    else
        BUILDER_VERSION=`"$BUILDER_ROOT/gen-version"`
    fi 
else
    BUILDER_VERSION="$_version"
fi
export BUILDER_VERSION

# Set other version formats that need to be available as build args
source "$BUILDER_ROOT/helpers/functions.sh"
set_python_src_versions  # sets BUILDER_PYTHON_SRC_VERSION

# Set SOURCE_DATE_EPOCH to last commit timestamp, if unset
# See https://reproducible-builds.org/docs/source-date-epoch/
# It is still up to the Dockerfile to actually set this
if [ -z "$SOURCE_DATE_EPOCH" ]; then
    SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct)
    export SOURCE_DATE_EPOCH
    echo "Setting SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH build arg"
fi

# Create cache directory for caching assets between builds
if [ "$BUILDER_CACHE" = "1" ]; then
    cache="$BUILDER_ROOT/cache/$target"
    mkdir -p "$cache/new"
fi

#######################################################################
# Some initialization
#

[ -d "$BUILDER_TMP" ] || mkdir "$BUILDER_TMP"

#######################################################################
# Generate dockerfile from templates
#

# This one fails for some reason (maybe '+' char?)
#dockerfile="Dockerfile_${target}_${BUILDER_VERSION}" 
dockerfile="Dockerfile_${target}.tmp"
dockerfilepath="$BUILDER_TMP/$dockerfile"
cd "$BUILDER_SUPPORT_ROOT/dockerfiles"
BUILDER_TARGET="$target" tmpl_debug=1 tmpl_comment='###' "$BUILDER_ROOT/templating/templating.sh" "$template" > "$dockerfilepath"
cd - > /dev/null
[ -z "$quiet" ] && echo "Generated $dockerfilepath"

#######################################################################
# Build docker images with artifacts inside
#
buildargs+=("--build-arg" "BUILDER_VERSION=$BUILDER_VERSION")
buildargs+=("--build-arg" "BUILDER_RELEASE=$BUILDER_RELEASE")
buildargs+=("--build-arg" "BUILDER_PACKAGE_MATCH=$package_match")
buildargs+=("--build-arg" "BUILDER_EPOCH=$BUILDER_EPOCH")
buildargs+=("--build-arg" "BUILDER_PYTHON_SRC_VERSION=$BUILDER_PYTHON_SRC_VERSION")
buildargs+=("--build-arg" "APT_URL=$APT_URL")
buildargs+=("--build-arg" "PIP_INDEX_URL=$PIP_INDEX_URL")
buildargs+=("--build-arg" "PIP_TRUSTED_HOST=$PIP_TRUSTED_HOST")
buildargs+=("--build-arg" "npm_config_registry=$npm_config_registry")
buildargs+=("--build-arg" "BUILDER_CACHE_BUSTER=$cache_buster_value")
buildargs+=("--build-arg" "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH")

declare -a buildcmd

if [ "${buildmode}" = "docker" ]; then
  iprefix="builder-${repo_safe_name}-${target}"
  image="$iprefix:latest" # TODO: maybe use version instead of latest?
  echo -e "${color_white}Building docker image: ${image}${color_reset}"

  buildcmd=(docker build
    ${buildargs[@]}
    ${ulimitargs[@]}
    -t "$image" "${dockeropts[@]}" -f "$dockerfilepath" .)
elif [ "${buildmode}" = "kaniko" ]; then
  buildcmd=(/kaniko/executor --context ${PWD}
    --dockerfile $dockerfilepath
    --no-push
    --verbosity debug
    ${kanikoargs[@]}
    ${buildargs[@]})
fi
[ -z "$quiet" ] && echo "+ ${buildcmd[*]}"

# All of this basically just runs the docker build command prepared above, but 
# with all kinds of complexity for friendly console output and logging.
#
if [ "$verbose" = "1" ]; then
    # Verbose means normal docker output, no log file
    if ! "${buildcmd[@]}" ; then
        echo -e "${color_red}ERROR: Build failed${color_reset}"
        exit 1
    fi
else
    # Default output: only show build steps, but log everything to file.
    # Quiet: don't even show build steps, but still log to file.
    timestamp() {
        # Based on https://unix.stackexchange.com/questions/26728/
        start="$(get_ts)"
        while IFS= read -r line; do
            now="$(get_ts)"
            t=$(($now - $start))
            s=$(($t % 60))
            m=$(($t / 60))
            printf '[%2d:%02d] %s\n' "$m" "$s" "$line"
        done
    }

    docker_steps_output() {
      # Only display steps, with FROM commands in bold
      grep --line-buffered -E '^(Step [0-9]|::: |^#[0-9]+ (\[|[0-9.]+ :::))' | sed "$sed_nobuf" -E "s/^(Step [0-9].* )(FROM .*)$/\\1${color_white_e}\\2${color_reset_e}/; s/^#[0-9]+ //" | timestamp > "$dockeroutdev"
    }

    kaniko_steps_output() {
      # Only show the commands (or cached versions of)
      grep --line-buffered -E '^([A-Z]{4}\[....\]( Using caching version of cmd:)? [A-Z][A-Z]+ |::: )' | sed "$sed_nobuf" -E "s/^....\\[....\\] (.*)$/\\1/" | timestamp > "$dockeroutdev"
    }

    timestamp="$(get_date)"
    dockerlogfile="build_${target}_${BUILDER_VERSION}_${timestamp}.log"
    dockerlog="$BUILDER_TMP/${dockerlogfile}"
    touch "$dockerlog"
    ln -sf "$dockerlogfile" "$BUILDER_TMP/build_latest.log"
    echo -e "Build logs can be found in ${color_white} $dockerlog ${color_reset} (use -v to output to stdout instead)"
    retval=
    if [ "${buildmode}" = "docker" ]; then
      "${buildcmd[@]}" 2>&1 | tee "$dockerlog" | docker_steps_output
      retval="${PIPESTATUS[0]}"
    else
      # Run command, remove colors, send to log
      "${buildcmd[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$dockerlog" | kaniko_steps_output
      retval="${PIPESTATUS[0]}"
    fi

    if [ "${retval}" != "0" ]; then
        echo -e "${color_red}ERROR: Build failed. Last step log output:${color_reset}"
        # https://stackoverflow.com/questions/7724778/sed-return-last-occurrence-match-until-end-of-file
        if [ "${buildmode}" = "docker" ]; then
          sed '/^Step [0-9]/h;//!H;$!d;x' "$dockerlog"
        elif [ "${buildmode}" = "kaniko" ]; then
          sed '/^INFO\[....\] [A-Z][A-Z]+ /h;//!H;$!d;x' "$dockerlog"
        fi
        echo -e "Full build logs can be found in ${color_white} $dockerlog ${color_reset}"
        echo -e "${color_red}ERROR: Build failed${color_reset}"
        exit 1
    fi
fi

#######################################################################
# Copy artifacts out of the image through a container
#
function cleanup_container {
  docker rm "$container" > /dev/null
}

# In kaniko, these results just sit on the local fs
dest=''

if [ "${buildmode}" = "docker" ]; then
  dest="$BUILDER_TMP/$BUILDER_VERSION"
  [ -d "$dest" ] || mkdir "$dest"
  # Create (but do not start) a container with the image
  container=`docker create "$image"`
  # Remove container on exit
  trap cleanup_container EXIT
  # Actual copy
  docker cp "$container:/sdist" "$dest"
  if [ "$target" != "sdist" ]; then 
    # docker cp has no way to just copy everything inside one dir into another dir
    [ -d "$dest/$target" ] || mkdir "$dest/$target"
    docker cp "$container:/dist" "$dest/$target/"
  fi

  # Copy new cache assets to speedup the next build
  if [ "$BUILDER_CACHE" = "1" ]; then
    if docker cp "$container:/cache/new" "$cache/" ; then
      if [ -d "$cache/new" ]; then
        mv "$cache"/new/* "$cache/" || true
      fi
    fi
  fi

  # Update 'latest' symlink
  rm -f "$BUILDER_TMP/latest" || true
  ln -sf "$BUILDER_VERSION" "$BUILDER_TMP/latest"
fi

#######################################################################
# Build success output and post-build hooks
#
# List the files we created
if [ -z "$quiet" ]; then
    echo
    tree "$dest/sdist" 2>/dev/null || find "$dest/sdist"
    if [ "$target" != "sdist" ]; then
      if [ "${buildmode}" = "docker" ]; then
        tree "$dest/$target" 2>/dev/null || find "$dest/$target"
      elif [ "${buildmode}" = "kaniko" ]; then
        tree "$dest/dist" 2>/dev/null || find "$dest/dist"
      fi
    fi
fi

if [ "${buildmode}" = "docker" ]; then
  # Print this hint before hooks, in case they fail and you need to investigate
  echo
  echo "You can test manually with:  docker run -it --rm $image"

  # Run post-build-test hook
  if [ "$skiptests" != "1" ] && [ -x "$BUILDER_SUPPORT_ROOT/post-build-test" ]; then
    if [ -z "$quiet" ]; then
      echo
      echo -e "Running post-build-test script"
    fi
    BUILDER_IMAGE="${image}" BUILDER_TARGET="${target}" "$BUILDER_SUPPORT_ROOT/post-build-test"
  fi

  # Run post-build hook
  if [ -x "$BUILDER_SUPPORT_ROOT/post-build" ]; then
    if [ -z "$quiet" ]; then
      echo
      echo -e "Running post-build script"
    fi
    BUILDER_TARGET="${target}" "$BUILDER_SUPPORT_ROOT/post-build"
  fi
fi

# Report success
echo
echo -e "${color_green}SUCCESS, files can be found in ${dest}${color_reset}"
t_end="$(get_ts)"
runtime=$((t_end - t_start))
echo "Build took $runtime seconds"

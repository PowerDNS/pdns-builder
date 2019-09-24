#!/bin/bash
# Main package builder

t_start=`date +%s`

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
    targets=$(ls $BUILDER_SUPPORT_ROOT/dockerfiles/Dockerfile.target.* | sed 's/.*Dockerfile.target.//' | tr '\n' ' ')
    echo "Builds packages in Docker for a target distribution, or sdist for generic source packages."
    echo
    echo "USAGE:    $0 [options] <target>"
    echo
    echo "Options:"
    echo "  -q              - Be more quiet. Build error details are still printed on build error."
    echo "  -v              - Always show full docker build output (default: only steps and build error details)"
    echo "  -S              - Force running of install tests, even if this is not a full build"
    echo "  -s              - Skip install tests"
    echo ""
    echo " docker build options:"
    echo "  -B ARG=VAL      - Add extra build arguments, can be passed more than once"
    echo "  -b VALUE        - Docker cache buster, set to 'always', 'daily', 'weekly' or a literal value."
    echo "  -C              - Run docker build with --no-cache"
    echo "  -P              - Run docker build with --pull"
    echo ""
    echo " Package options:"
    echo "  -c              - Enable builder package cache"
    echo "  -e EPOCH        - Set a specific Epoch for packages"
    echo "  -m MODULES      - Build only specific components (comma separated; warning: this disables install tests)"
    echo "  -p PACKAGENAME  - Build only spec files that have this string in their name (warning: this disables install tests)"
    echo "  -R RELEASE      - Override release tag (default: '1pdns', do not include %{dist} here)"
    echo "  -V VERSION      - Override version (default: run gen-version)"
    echo
    echo "Targets:  $targets"
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
declare -a buildargs
verbose=""
quiet=""
dockeroutdev=/dev/stdout
forcetests=

# RPM release tag (%{dist} will always be appended)
export BUILDER_RELEASE=1pdns

# Modules to build
export M_all=1

# Modules to expose to a custom gen-version
BUILDER_MODULES=''

package_match=""
cache_buster=""

while getopts ":CcV:R:svqm:Pp:b:e:B:" opt; do
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
    B)  buildargs+=("--build-arg ${OPTARG}")
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

# Create cache directory for caching assets between builds
if [ "$BUILDER_CACHE" = "1" ]; then
    cache="$BUILDER_ROOT/cache/$target"
    mkdir -p "$cache/new"
fi

#######################################################################
# Some initialization
#

# Exit on error
set -e

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

iprefix="builder-${repo_safe_name}-${target}"
image="$iprefix:${BUILDER_VERSION}"
echo -e "${color_white}Building docker image: ${image}${color_reset}"

buildcmd=(docker build --build-arg BUILDER_VERSION="$BUILDER_VERSION"
                       --build-arg BUILDER_RELEASE="$BUILDER_RELEASE"
                       --build-arg BUILDER_PACKAGE_MATCH="$package_match"
                       --build-arg BUILDER_EPOCH="$BUILDER_EPOCH"
                       --build-arg APT_URL="$APT_URL"
                       --build-arg PIP_INDEX_URL="$PIP_INDEX_URL"
                       --build-arg PIP_TRUSTED_HOST="$PIP_TRUSTED_HOST"
                       --build-arg npm_config_registry="$npm_config_registry"
                       --build-arg BUILDER_CACHE_BUSTER="$cache_buster_value"
                       ${buildargs[@]}
                       -t "$image" "${dockeropts[@]}" -f "$dockerfilepath" .)
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
        start=`date '+%s'`
        while IFS= read -r line; do
            now=`date '+%s'`
            t=$(($now - $start))
            s=$(($t % 60))
            m=$(($t / 60))
            printf '[%2d:%02d] %s\n' "$m" "$s" "$line"
        done
    }
    docker_steps_output() {
        # Only display steps, with FROM commands in bold
        grep --line-buffered -E '^(Step [0-9]|::: )' | sed "$sed_nobuf" -E "s/^(Step [0-9].* )(FROM .*)$/\\1${color_white_e}\\2${color_reset_e}/" | timestamp > "$dockeroutdev"
    }
    timestamp=$(date '+%Y%m%d-%H%M%S')
    dockerlogfile="build_${target}_${BUILDER_VERSION}_${timestamp}.log"
    dockerlog="$BUILDER_TMP/${dockerlogfile}"
    touch "$dockerlog"
    ln -sf "$dockerlogfile" "$BUILDER_TMP/build_latest.log"
    echo -e "Docker build logs can be found in ${color_white} $dockerlog ${color_reset} (use -v to output to stdout instead)"
    "${buildcmd[@]}" | tee "$dockerlog" | docker_steps_output
    if [ "${PIPESTATUS[0]}" != "0" ]; then
        echo -e "${color_red}ERROR: Build failed. Last step log output:${color_reset}"
        # https://stackoverflow.com/questions/7724778/sed-return-last-occurrence-match-until-end-of-file
	sed '/^Step [0-9]/h;//!H;$!d;x' "$dockerlog"
    	echo -e "Full build logs can be found in ${color_white} $dockerlog ${color_reset}"
        echo -e "${color_red}ERROR: Build failed${color_reset}"
        exit 1
    fi
fi

#######################################################################
# Copy artifacts out of the image through a container
#

dest="$BUILDER_TMP/$BUILDER_VERSION"
[ -d "$dest" ] || mkdir "$dest"
# Create (but do not start) a container with the image
container=`docker create "$image"`
# Remove container on exit
function cleanup_container {
    docker rm "$container" > /dev/null
}
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

#######################################################################
# Build success output and post-build hooks
#
            
# List the files we created
if [ -z "$quiet" ]; then
    echo
    tree "$dest/sdist" 2>/dev/null || find "$dest/sdist"
    if [ "$target" != "sdist" ]; then 
        tree "$dest/$target" 2>/dev/null || find "$dest/$target"
    fi
fi

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

# Report success
echo
echo -e "${color_green}SUCCESS, files can be found in ${dest}${color_reset}"
t_end=`date +%s`
runtime=$((t_end - t_start))
echo "Build took $runtime seconds"


# PowerDNS Builder 

[![Build Status](https://travis-ci.org/PowerDNS/pdns-builder.svg?branch=master)](https://travis-ci.org/PowerDNS/pdns-builder)

A reusable Docker based distribution package builder.

## Quickstart

To only build generic source packages:

    ./builder/build.sh sdist
    
To build for CentOS 7:

    ./builder/build.sh centos-7

Packages will end up in `builder/tmp/<version>/`.

The build script supports various commandline options. See:

    ./builder/build.sh -h


## Build requirements

* Docker >= 17.05
* git
* bash
* tree (optional)


## How does this work?

The build process for distribution packages consists of three steps:

1. Create generic source distributions for all components. This step also
   performs any more complicated generic steps, like building plain dist assets
   using webpack.

2. Create rpms or debs from these source packages (and build specs) only, with
   no other access to the source, in a container with all build dependencies
   installed.

3. Install the distribution packages and test them in a clean container without
   the build dependencies.

The `sdist` target only performs the first step. The install test is skippable
with `-s`, but using this option is not recommended.

The builder expects to be put in `builder/` in the repository to build and to
find a `builder-support/` directory next to it with all repository specific
build configurations.

The implementation uses [Docker 17.05+ multi-stage builds][multistage] to 
implement these steps. `builder-support/dockerfiles/` is expecte to contain
[simple templates][templ] for Dockerfiles that will be combined into a 
temporary Dockerfile for the build.
This allows us to split different build steps and substeps into separate
stages, while only having to trigger a single Docker build. 

The build script does not know or care how the actual build is performed, it just 
expects the build artifacts to end up in `/sdist` and `/dist` inside 
the final image after the build.

[multistage]: https://docs.docker.com/engine/userguide/eng-image/multistage-build/
[templ]: ./templating/templating.sh


## Autobuild deployment notes

If you want to run these builds on a frequent basis, such as in a buildbot that
automatically builds on new commits, keep the following in mind:

### Disk usage

Every build will create a fair amount of new Docker layers that will take up 
disk space. Make sure you have something like 20 GB or more disk space 
available for builds, and run the included [docker-cleanup.sh](docker-cleanup.sh)
once a day in a cron job to remove containers and images that are no longer
referenced by a tag.

Do keep in mind that after a cleanup, a new build will have to start from
scratch, so you do not want to run it too often. Once a day is probably a
fair compromise between build time and disk usage, assuming you will not be
building hundreds of times per day.

### Base image freshness

Docker will never pull newer versions of the base images by itself. After a 
while the base images might become outdated. You could add an 
`apt update && apt upgrade` or equivalent to the start of each base image, but 
this will take longer and longer to execute.

Instead, you could `docker pull <image>` in a cron job every night for every
base image used in the builds. It's best to do this before the docker cleanup
script, so that it can cleanup all the old layers from the previous image.

Script to find all official images and pull them:

    images=`docker images --format '{{.Repository}}:{{.Tag}}' --filter dangling=false | grep -v '[_/-]'`
    for image in $images; do docker pull "$image"; done

You probably do not want to add `set -e` here.

NOTE: This will also try to pull any images you tagged locally without any 
`-`, `_` or `/` in the name, and skip any non-official Docker images. Please
adapt to your use case.

### Concurrent builds

With the current build script it is unsafe run several builds for the same
target at the same time, because the temporary Dockerfile name and image tag
will clash. We considered adding the version number to the tag, but this would
make cleanup harder. Maybe we need to add an option to the build script to
override the tag, if we need concurrent builds.

Concurrent builds for different targets (like oraclelinux-6.8 and centos-7
in parallel) should be safe, though.


## Implementation details

### Dockerfiles

The Dockerfile templates are expected in `builder-support/dockerfiles/`.
Note that these Dockerfiles are repository specific and not included with
the builder distribution.

The files that start with `Dockerfile.target.` are used as build targets.
For example, `Dockerfile.target.centos-7` would be used for the `centos-7` target.
`Dockerfile.target.sdist` is used for the `sdist` target, but also included by
all the other targets to performs the source builds.

To allow for reusability of include files, the following stage naming conventions
should be observed:

* `sdist` is the final source dist stage that contains all source dists in `/sdist`,
  which will be copied by the binary package builder.
* `dist-base` is the stage used as base image for both the package builder and
  the installation test.
* `package-builder` is the final binary package build stage that contains binary
  packages in `/dist`, which will be installed in the installation test.

The last stage to appear in the Dockerfile will be the resulting image of the
docker build. This one must have source dists in `/sdist` and binaries in
`/dist`, as this is where the build scripts copies the result artifacts from.
Please keep in mind that the test stage could be skipped, so these also have to
exist at the end of the package builder stage.

#### Docker caching

If editing Dockerfiles, try to maximize the efficiency of docker layer caches.
For example:

* Only COPY/ADD files that are really needed at that point in the build process.
  For example, the installation tests live in a different folder than the 
  build helpers, so that updating installation tests does not invalidate the
  layers that build the RPMs.
* Vendor specs should be built before you COPY your source artifacts, so that 
  they are only rebuilt if their spec files change and not every time your code
  changes.
* For the same reason, build ARGs should be set as late as possible.
* If you have a slow build step, like building an Angular project using Webpack,
  you should consider doing this in a separate stage and only apply any
  versioning after the actual build, so that the expensive steps can be cached.

If you have a build step that relies on external, changing state (such as
`apt-get update`), you may want to avoid caching this step forever. To do so,
put `ARG BUILDER_CACHE_BUSTER=` before the step, and pass `-b daily` or `-b
weekly` to build.sh.

#### Templating

Templating is done using a simple template engine written in bash. 

Example text template:

    Lines can start with @INCLUDE, @EVAL or @EXEC for special processing:
    @INCLUDE foo.txt
    @EVAL My home dir is $HOME
    @EXEC uname -a
    @EXEC [ "$foo" = "bar" ] && include bar.txt
    @IF [ "$foo" = "bar" ]
    This line is only printed if $foo = "bar" (cannot be nested)
    @INCLUDE bar.txt
    @ENDIF
    Other lines are printed unchanged.   

The commands behind `@EXEC` and `@IF` can be any bash commands. `include` is
an internal bash function used to implement `@INCLUDE`. Note that `@IF`
currently cannot be nested.

The templating implementation can be found in `templating/templating.sh`.

#### Post Build steps

When certain steps or commands are needed after building, add an executable
file called `post-build` to `builder-support`. After a build, this file will
be run.


### Reproducible builds

The builder has a few features to help with creating reproducible builds.

The builder sets a `SOURCE_DATE_EPOCH` build argument with the timestamp of the last
commit as the value. This is not automatically propagated to the build environment.
If you want to use this, add this to your Dockerfile at the place where you want to
start using it:

```
ARG SOURCE_DATE_EPOCH
```

This will probably be the same place that you inject the `BUILDER_VERSION`.

For vendor dependency builds, you probably do not want to use it, as it could make their
artifacts change with every version change. Instead, you may want to set the
`BUILDER_SOURCE_DATE_FROM_SPEC_MTIME` env var when building RPMs. If this is set, the
build script will use the modification time of the spec file as the `SOURCE_DATE_EPOCH`.
Example usage:

```
RUN BUILDER_SOURCE_DATE_FROM_SPEC_MTIME=1 builder/helpers/build-specs.sh builder-support/vendor-specs/*.spec
```

The RPM build script always defines the following variables for reproducible RPM builds:

```
--define "_buildhost reproducible"
--define "source_date_epoch_from_changelog Y"
--define "clamp_mtime_to_source_date_epoch Y"
--define "use_source_date_epoch_as_buildtime Y"
```

The `source_date_epoch_from_changelog` variable only has effect when no `SOURCE_DATE_EPOCH` is set.
These variables are only supported in RHEL 8+ and derived distributions. RHEL 7 does not appear
to support reproducible RPM builds.

Keep in mind that the builder an only do so much, as any part of your build pipeline
that creates non-reproducible artifacts will result in non-reproducible build output.
For example, if the base image you use upgrades the compiler, the compiled output
will likely change.



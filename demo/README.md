# Builder demo

This simple demo serves both as a demonstration of how to use the builder
and as a test case for builder development.

To run the build, run this from the current folder:

    ./prepare.sh
    ./builder/build.sh -B MYCOOLARG=iLikeTests

The prepare script copies the builder files into builder/. Generally
you would use git submodules instead, but this does not work for here
as we keep the demo inside the same repository.

#!/bin/sh

# this script is to build mujs with coverage option

clone_repo() {
  git clone https://github.com/ccxvii/mujs
  git config --global --add safe.directory $PWD/mujs
}

pre_build() {
  local builddir=$1
  git restore .
  sed -i -e 's/^CFLAGS =/CFLAGS +=/' -e 's/^CFLAGS :=/CFLAGS +=/' Makefile
  sed -i "s|build/|$builddir/|g" Makefile
}

build_target() {
  local commit=$(git rev-parse --short=7 HEAD)
  local builddir=${1:-build_$commit}
  
  export CFLAGS_GCOV="-fprofile-arcs -ftest-coverage -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
  export LDFLAGS_GCOV="--coverage"
  export CFLAGS="$CFLAGS_GCOV"
  export LDFLAGS="$LDFLAGS_GCOV"
  export XCFLAGS="$CFLAGS"
  
  make sanitize -j4 OUT=$builddir/sanitize
  unset CFLAGS LDFLAGS XCFLAGS
}

clone_repo
cd mujs
pre_build build
build_target build

# executable: mujs/build/sanitize/mujs
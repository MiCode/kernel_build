#!/bin/sh

BASE=$(readlink -f $(dirname $0)/..)

BRANCH=$1

pushd $BASE > /dev/null

  if [ ! -d common-${BRANCH} ]; then
    echo "usage: $0 <branch>\n"
    echo "Branches available: "
    ls -d common-* | sed 's/common-/\t/g'
    exit 1
  fi

  echo "Switching to $BRANCH"

  for dir in common cuttlefish-modules goldfish-modules; do
      if [ -L ${dir} ]; then
          rm ${dir}
      fi
      if [ -d ${dir}-${BRANCH} ]; then
          ln -vs ${dir}-${BRANCH} ${dir}
      fi
  done

popd > /dev/null

#!/bin/bash

set -e

BASE_DIR=$(readlink -f $(dirname $0)/../../)

# Build the hermetic container
docker build -t hermetic $BASE_DIR/build/hermetic

# Run the hermetic container
docker run -ti --mount type=bind,source=${BASE_DIR},target=/b/ hermetic

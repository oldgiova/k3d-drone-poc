#!/bin/bash
set -euxo pipefail

#cleanup old builds
rm -rf ./.build || echo "INFO - .build dir not found. Ignoring"

timestamp=$(date +%Y%m%d-%H%M%S)
echo "BUILDDIR=.build/${timestamp}" > .build_info

mkdir -p .build/${timestamp}

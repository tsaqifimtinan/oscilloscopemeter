#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
open build/Build/Products/Debug/Scope.app

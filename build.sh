#!/usr/bin/env bash
set -e

mkdir -p build

if [ -f "./builder.sh" ]; then
  ./builder.sh "$@"
else
  exit 1
fi

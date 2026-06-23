#!/bin/sh
# Use the ash shell for these steps

set -e

thispath="$(realpath "$0")"
thisdir="$(dirname "$thispath")"

set -a
. "$thisdir"/vars-arm64.sh
set +a

sh arm64/01-make.sh
sh arm64/02-shadow.sh
sh arm64/04-bash.sh

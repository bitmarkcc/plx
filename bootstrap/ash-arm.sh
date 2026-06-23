#!/bin/sh
# Use the ash shell for these steps

set -e

thispath="$(realpath "$0")"
thisdir="$(dirname "$thispath")"

set -a
. "$thisdir"/vars-arm.sh
set +a

sh arm/01-make.sh
sh arm/02-shadow.sh
sh arm/03-busybox.sh
sh arm/04-bash.sh

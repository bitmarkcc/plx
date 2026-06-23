#!/bin/bash
# Use the bash shell for these steps

set -e

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

set -a
. "$thisdir"/vars-arm64.sh
set +a

export -f asuser

bash 2021/01-portage-conf.sh
bash 2021/02-system-2021.sh
bash 2021/03-libtool.sh

#!/bin/bash
# Use the bash shell for these steps

set -e

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

set -a
. "$thisdir"/vars-arm64.sh
set +a

export -f asuser

bash arm64/05-zlib.sh
bash arm64/06-xz.sh
bash arm64/07-perl.sh
bash arm64/08-patch.sh
bash arm64/10-python.sh
bash arm64/11-portage.sh
bash arm64/11b-musl.sh
bash arm64/12-pax-utils.sh
bash arm64/16-libtool.sh
bash arm64/16b-ncurses.sh
bash arm64/17-linux-headers.sh
bash arm64/18-queue.sh
bash arm64/18b-tirpc.sh
bash arm64/19-system.sh

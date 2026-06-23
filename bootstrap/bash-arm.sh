#!/bin/bash
# Use the bash shell for these steps

set -e

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

set -a
. "$thisdir"/vars-arm.sh
set +a

export -f asuser

bash arm/05-zlib.sh
bash arm/06-xz.sh
bash arm/07-perl.sh
bash arm/08-patch.sh
bash arm/09-libiconv.sh
bash arm/10-python.sh
bash arm/11-portage.sh
bash arm/12-pax-utils.sh
bash arm/13-binutils.sh
bash arm/14-gmp.sh
bash arm/15-gcc.sh
bash arm/16-libtool.sh
bash arm/17-iproute2-deps.sh
bash arm/18-iproute2.sh
bash arm/19-system.sh
bash arm/19b-system-2019.sh
bash arm/20-crossdev.sh
bash arm/21-aarch64-basics.sh

date +"%F %T" > /usr/aarch64-unknown-linux-musl/root/tmp/lastdate

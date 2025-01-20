#!/bin/bash

set -e

. /etc/profile
tar xpf /root/tmp/gentoo-"$snapshotver".tar.xz -C /var/db/repos/
mv "/var/db/repos/gentoo-$snapshotver" /var/db/repos/gentoo
eselect profile list
if [[ "$libc" == "musl" ]]
then
    emerge -q sys-libs/timezone-data
    echo 'TZ="/usr/share/zoneinfo/UTC"' >> /etc/env.d/00local
else
    emerge --config sys-libs/timezone-data
    sed -i 's/#en_US/en_US/' /etc/locale.gen
    locale-gen
    eselect locale set "en_US.utf8"
fi
env-update
. /etc/profile
#passwd -d root

emerge -q1 app-eselect/eselect-repository
set +e
eselect repository add plx git https://github.com/bitmarkcc/plx-overlay
set -e

tar xpf "/root/tmp/plx-overlay-$plxolver.tar.gz" -C /var/db/repos/
cd /var/db/repos
if [ -e plx ]
then
    rmdir plx
fi
mv "plx-overlay-$plxolver" plx

emerge -fqe --update --deep --newuse --autounmask-continue @world @installed dev-build/libtool

#!/bin/bash

set -e

. /etc/profile

echo "Unpacking gentoo snapshot ..."
tar xpf "/root/tmp/gentoo-$snapshotver.tar.xz" -C /var/db/repos/
mv "/var/db/repos/gentoo-$snapshotver" /var/db/repos/gentoo
eselect profile list
emerge --config sys-libs/timezone-data
sed -i 's/#en_US/en_US/' /etc/locale.gen
locale-gen
eselect locale set "en_US.utf8"

env-update
. /etc/profile
hostname plx # why doesn't it pick up the hostname from etc/hostname?

emerge -q1 app-eselect/eselect-repository
set +e
eselect repository add plx git https://github.com/bitmarkcc/plx-overlay
#eselect repository enable pf4public # for ungoogled-chromium
#emaint sync -r pf4public
set -e
tar xpf "/root/tmp/plx-overlay-$plxolver.tar.gz" -C /var/db/repos/
cd /var/db/repos
if [ -e plx ]
then
    rmdir plx
fi
mv "plx-overlay-$plxolver" plx

emerge -q --update --deep --newuse --autounmask-continue @world
env-update
. /etc/profile
emerge -q1 dev-build/libtool
env-update
. /etc/profile
emerge --with-bdeps=n --depclean
env-update
. /etc/profile
rm -r /root/tmp/*.xz /root/tmp/*.gz
rm -r /var/cache/distfiles/*

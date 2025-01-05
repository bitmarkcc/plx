#!/bin/bash

set -e

. /etc/profile
tar xpf /root/tmp/gentoo-"$snapshotver".tar.xz -C /var/db/repos/
mv "/var/db/repos/gentoo-$snapshotver" /var/db/repos/gentoo
eselect profile list
emerge --config sys-libs/timezone-data
sed -i 's/#en_US/en_US/' /etc/locale.gen
locale-gen
eselect locale set "en_US.utf8"
env-update
. /etc/profile
#passwd -d root

gpg --import /root/tmp/plx-pgp.asc
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
mv plx-overlay-$plxolver plx

cd /var/db/repos/plx/app-misc/cwallet
gpg --verify Manifest

emerge -fq --update --deep --newuse --autounmask-continue @world

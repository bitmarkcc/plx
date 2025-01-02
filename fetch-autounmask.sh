#!/bin/bash

set -e

snapshotver="$1"

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
eselect repository add plx git https://github.com/bitmarkcc/plx-overlay
emaint sync -r plx
cd /var/db/repos/plx/app-misc/cwallet
gpg --verify Manifest

emerge -fq --update --deep --newuse --autounmask-continue @world

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
emerge -fq --update --deep --newuse --autounmask-continue @world

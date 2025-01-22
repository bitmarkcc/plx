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
#rc-update add NetworkManager default
#rc-update add alsasound boot
#rc-update add consolekit default
#rc-update add cupsd default
#rc-update add lvm boot
#rc-update add ntpd default
#rc-update add udev sysinit
#rc-update add udev-mount sysinit #check
#rc-update add kmod-static-nodes sysinit #check
#rc-update add net.lo boot #check
#rc-update add dbus default #maybe unnecessary
#rc-update delete hwclock boot #check
rm -r /root/tmp/*.xz /root/tmp/*.xz
#sed 's|/root/tmp/install.sh||' /root/.bash_profile
rm -r /var/cache/distfiles/*

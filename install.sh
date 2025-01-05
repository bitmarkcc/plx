#!/bin/bash

set -e

chroot=0

if [[ "$chroot" == "1" ]]
then
    . /etc/profile
fi
date -s "$date"
rc-update add swclock-helper default
set +e
rc-service swclock-helper start
set -e
rc-update add swclock default
rc-update add local default
set +e
rc-service local start
set -e
rc-update add sshd default
set +e
rc-service sshd start
set -e
echo "Unpacking gentoo snapshot ..."
tar xpf "/root/tmp/gentoo-$snapshotver.tar.xz" -C /var/db/repos/
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
cat /root/tmp/pw | chpasswd
rm /root/tmp/pw
emerge -q1 app-admin/syslog-ng
rc-update add syslog-ng default
useradd -m -G users,audio -s /bin/bash guest
sed -i 's/-a root/-a guest/' /etc/inittab

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

if [[ "$chroot" == "0" ]]
then
    emerge -q1 sys-block/parted
    echo "Partitioning ..."
    mmc="/dev/mmcblk0"
    parted -fsa optimal "$mmc" mkpart swap linux-swap 8GiB 16GiB
    parted -sa optimal "$mmc" mkpart portage ext4 16GiB 48GiB
    parted -sa optimal "$mmc" mkpart distfiles ext4 48GiB 64GiB
    parted -sa optimal "$mmc" mkpart home ext4 64GiB 100%
    mkswap "$mmc"p3
    mkfs.ext4 -F "$mmc"p4
    mkfs.ext4 -F "$mmc"p5
    mkfs.ext4 -F "$mmc"p6
    swapon "$mmc"p3
    mkdir /mnt/portage
    mount "$mmc"p4 /mnt/portage
    echo "Copying /var/tmp/portage files to new partition ..."
    cp -aT /var/tmp/portage /mnt/portage
    umount /mnt/portage
    rm -r /var/tmp/portage
    mkdir /var/tmp/portage
    mount "$mmc"p4 /var/tmp/portage
    mkdir /mnt/distfiles
    mount "$mmc"p5 /mnt/distfiles
    echo "Copying /var/cache/distfiles files to new partition ..."
    cp -aT /var/cache/distfiles /mnt/distfiles
    umount /mnt/distfiles
    rm -r /var/cache/distfiles
    mkdir /var/cache/distfiles
    mount "$mmc"p5 /var/cache/distfiles
    mount "$mmc"p6 /home
    sed -i 's|^#/dev/mmcblk0p3|/dev/mmcblk0p3|' /etc/fstab
    sed -i 's|^#/dev/mmcblk0p4|/dev/mmcblk0p4|' /etc/fstab
    sed -i 's|^#/dev/mmcblk0p5|/dev/mmcblk0p5|' /etc/fstab
    sed -i 's|^#/dev/mmcblk0p6|/dev/mmcblk0p6|' /etc/fstab
    echo "Done partitioning"
fi

emerge -q --update --deep --newuse @world
env-update
. /etc/profile
emerge -q1 libtool
env-update
. /etc/profile
emerge --with-bdeps=n --depclean
revdep-rebuild
env-update
. /etc/profile
#rc-update add NetworkManager default
rc-update add alsasound boot
#rc-update add consolekit default
rc-update add cupsd default
#rc-update add lvm boot
rc-update add ntpd default
#rc-update add udev sysinit
#rc-update add udev-mount sysinit #check
#rc-update add kmod-static-nodes sysinit #check
#rc-update add net.lo boot #check
#rc-update add dbus default #maybe unnecessary
rc-update delete hwclock boot #check
echo "server 127.127.1.0" >> /etc/ntp.conf
echo "fudge  127.127.1.0 stratum 10" >> /etc/ntp.conf
echo "disable monitor" >> /etc/ntp.conf
cp /root/tmp/cupsd.conf /etc/cups/
for x in lp cdrom video cdrw usb lpadmin
do
    gpasswd -a guest $x
done

cd /home/guest
echo 'export XSESSION=openbox' >> .bashrc
cat /root/tmp/home/.Xresources >> .Xresources
mkdir -p .config/openbox
cp /root/tmp/home/.config/openbox/* .config/openbox/
echo 'if [[ "`tty`" == "/dev/tty1" ]]' >> .bash_profile
echo 'then' >> .bash_profile
echo -e '\tstartx' >> .bash_profile
echo 'fi' >> .bash_profile

cd
chown -R guest:guest /home/guest
chmod o-rwx /home/guest
rm -r /root/tmp/*.xz
#sed 's|/root/tmp/install.sh||' /root/.bash_profile
rm /root/.bash_profile # todo be general in case it is modified
touch /var/lib/misc/openrc-shutdowntime
if [[ "$chroot" == "0" ]]
then
    reboot
fi

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
rc-update add local default
set +e
rc-service local start
set -e
rc-update add sshd default
set +e
rc-service sshd start
set -e
tar xpf "/root/tmp/gentoo-$snapshotver.tar.xz" -C /var/db/repos/
mv "/var/db/repos/gentoo-$snapshotver" /var/db/repos/gentoo
eselect profile list
emerge --config sys-libs/timezone-data
sed -i 's/#en_US/en_US/' /etc/locale.gen
locale-gen
eselect locale set "en_US.utf8"
env-update
. /etc/profile
cat /root/tmp/pw | chpasswd
rm /root/tmp/pw
sed -i 's/terminus-font X/terminus-font/' /etc/portage/package.use/plx
emerge -q1 media-fonts/terminus-font
sed -i 's/^consolefont=.*$/consolefont="ter-u32n"/' /etc/conf.d/consolefont
rc-update add consolefont boot
if [[ "$chroot" == "0" ]]
then
    set +e
    rc-service consolefont restart
    set -e
fi
emerge -q1 app-admin/syslog-ng
rc-update add syslog-ng default
useradd -m -G users,audio -s /bin/bash guest
sed -i 's/-a root/-a guest/' /etc/inittab
sed -i 's/terminus-font/terminus-font X/' /etc/portage/package.use/plx

gpg --import /root/tmp/plx-pgp.asc
emerge -q1 app-eselect/eselect-repository
set +e
eselect repository add plx git https://github.com/bitmarkcc/plx-overlay
set -e
emaint sync -r plx
cd /var/db/repos/plx/app-misc/cwallet
gpg --verify Manifest

if [[ "$chroot" == "0" ]]
then
    echo "Partitioning ..."
    mmc="/dev/mmcblk0"
    parted -sa optimal "$mmc" mkpart swap swapfs 8GiB 16GiB
    parted -sa optimal "$mmc" mkpart portage ext4 16GiB 48GiB
    parted -sa optimal "$mmc" mkpart distfiles ext4 48GiB 64GiB
    parted -sa optimal "$mmc" mkpart home ext4 64GiB 100%
    mkswap "$mmc"p3
    mkfs.ext4 "$mmc"p4
    mkfs.ext4 "$mmc"p5
    mkfs.ext4 "$mmc"p6
    swapon "$mmc"p3
    mkdir /mnt/portage
    mount "$mmc"p4 /mnt/portage
    cp -aT /var/tmp/portage /mnt/portage
    umount /mnt/portage
    rm -r /var/tmp/portage
    mkdir /var/tmp/portage
    mount "$mmc"p4 /var/tmp/portage
    mkdir /mnt/distfiles
    mount "$mmc"p5 /mnt/distfiles
    cp -aT /var/cache/distfiles /mnt/distfiles
    umount /mnt/distfiles
    rm -r /var/cache/distfiles
    mkdir /var/cache/distfiles
    mount "$mmc"p5 /var/cache/distfiles
    mount "$mmc"p6 /home
    sed -i 's|^#/dev/mmcblk0p3|/dev/mmcblk0p3|'
    sed -i 's|^#/dev/mmcblk0p4|/dev/mmcblk0p4|'
    sed -i 's|^#/dev/mmcblk0p5|/dev/mmcblk0p5|'
    sed -i 's|^#/dev/mmcblk0p6|/dev/mmcblk0p6|'
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
rc-update add NetworkManager default
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
for x in lp cdrom video cdrw usb lpadmin plugdev
do
    gpasswd -a guest $x
done

cd /home/guest
echo 'export XSESSION=openbox' >> .bashrc
cp /root/tmp/home/.Xresources > .
mkdir -p .config/openbox
cp /root/tmp/home/.config/openbox/* .config/openbox/
echo 'if [ "$(tty)" == "/dev/tty1" ]' >> .bash_profile
echo 'then' >> .bash_profile
echo -e '\tstartx' >> .bash_profile
echo 'fi' >> .bash_profile

cd
chown -R guest:guest /home/guest
chmod o-rwx /home/guest
rm -r /root/tmp
sed 's|/root/tmp/install.sh||' /root/.bash_profile
if [[ "$chroot" == "0" ]]
then
    reboot
fi

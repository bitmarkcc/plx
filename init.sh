#!/bin/busybox sh

rescue_shell() {
	       echo "Something went wrong. Dropping you to a shell."
	       exec sh
}

/bin/busybox --install -s

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo "Checking root filesystem ..."
rootdev="/dev/mmcblk0p2"
haverootdev=0
while [[ "$haverootdev" == "0" ]]
do
    sleep 1
    if [ -e "$rootdev" ]
    then
	/usr/bin/e2fsck -fp "$rootdev"
	haverootdev=1
    fi
done
echo "Successfully checked root filesystem"

mkdir /mnt/root
mount /dev/mmcblk0p2 /mnt/root || rescue_shell
cp /bin/busybox /mnt/root/bin/

umount /dev
umount /sys
umount /proc

target=aarch64-unknown-linux-musl
rootdir=/mnt/root

if [ -e /mnt/root/usr/$target ]
then
    rootdir=/mnt/root/usr/$target
    mount --bind $rootdir $rootdir
fi

echo "Switching to $rootdir ..."

exec /bin/busybox switch_root $rootdir /sbin/init

rescue_shell

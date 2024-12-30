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

umount /dev
umount /sys
umount /proc

exec /bin/busybox switch_root /mnt/root /sbin/init

rescue_shell

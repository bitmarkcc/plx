#!/bin/busybox sh

set -e

rescue_shell() {
	       echo "Something went wrong. Dropping you to a shell."
	       exec sh
}

/bin/busybox --install -s

chroot=0
stage=1

date="`cat /root/tmp/lastdate`"
date -s "$date"

if [[ "$chroot" == 0 ]]
then
    mount -t proc none /proc
    mount -t sysfs none /sys
    mount -t devtmpfs none /dev
    mkdir -p /dev/shm
    mount -n -t tmpfs -o noexec,nosuid,nodev shm /dev/shm
    mkdir -p /run
    ln -s /dev/initctl /run/initctl
fi

cd /root/tmp/bootstrap
if [[ "$stage" == 1 ]]
then
    ./ash-arm.sh || rescue_shell
    ./bash-arm.sh || rescue_shell
elif [[ "$stage" == 2 ]]
then
    ./ash-arm64.sh || rescue_shell
    ./bash-arm64.sh || rescue_shell
fi

if [[ "$chroot" == 0 ]] # reboot
then
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
fi

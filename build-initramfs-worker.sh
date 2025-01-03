#!/bin/bash

set -e

add_deps_to_initramfs() { # the argument is the path to the binary for which you want to add the ldd dependencies
    ldd "$1" | awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs dirname | xargs -t -I '{}' mkdir -p initramfs'{}'
    ldd "$1" | awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs -t -I '{}' cp '{}' initramfs'{}'
}

mkdir initramfs
mkdir initramfs/root
mkdir initramfs/etc
mkdir initramfs/lib
mkdir initramfs/bin
mkdir initramfs/sbin
mkdir -p initramfs/usr/bin
mkdir -p initramfs/usr/sbin
mkdir initramfs/proc
mkdir initramfs/sys
mkdir initramfs/dev
mkdir initramfs/mnt
tar -xf "tmp/busybox-$busyboxver.tar.gz"
cd "busybox-$busyboxver"
make defconfig
sed -i 's/^CONFIG_TC=.*$/CONFIG_TC=n/' .config # tmp for recent kernels
make -j"$njobs"
cd ../
add_deps_to_initramfs "$busybox-$busyboxver/busybox"
cp "busybox-$busyboxver/busybox" initramfs/bin/

fsckpath="`which e2fsck`"
add_deps_to_initramfs "$fsckpath"
cp -L "$fsckpath" initramfs/usr/bin/e2fsck

rm -r "busybox-$busyboxver"
cp tmp/init.sh initramfs/init
chmod +x initramfs/init

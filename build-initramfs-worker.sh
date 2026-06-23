#!/bin/bash

set -e

add_deps_to_initramfs() { # the argument is the path to the binary for which you want to add the ldd dependencies
    ldd "$1" | awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs dirname | xargs -t -I '{}' mkdir -p initramfs'{}'
    ldd "$1" | awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs -t -I '{}' cp '{}' initramfs'{}'
}

mkdir initramfs
cd initramfs
mkdir proc
mkdir sys
mkdir dev
mkdir mnt
mkdir tmp
mkdir etc
mkdir -p var/tmp
mkdir -p root/bld
mkdir -p usr/bin
mkdir usr/lib
mkdir usr/libexec
mkdir usr/sbin
mkdir bin
ln -s usr/lib lib # This may need to be split into two for the bootstrap snapshot
mkdir sbin
cd

busyboxver=1.29.0
tar -xf "tmp/busybox-$busyboxver.tar.bz2"
cd "busybox-$busyboxver"
make defconfig
make -j"$njobs"
cd ../
busyboxpath="busybox-$busyboxver/busybox"
add_deps_to_initramfs "$busyboxpath"
cp -L "$busyboxpath" initramfs/bin/busybox

echo "fsckpath = $fsckpath"
add_deps_to_initramfs "$fsckpath"
cp -L "$fsckpath" initramfs/usr/bin/e2fsck

cp tmp/init.sh initramfs/init
chmod +x initramfs/init

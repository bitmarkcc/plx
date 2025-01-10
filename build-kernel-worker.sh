#!/bin/bash

set -e

tar -xf "tmp/linux-stable_$kernelver.tar.gz"

cd "linux-stable_$kernelver"
if [[ "$KERNEL" == kernel8 ]]
then
    make bcm2711_defconfig
elif [[ "$KERNEL" == kernel_2712 ]]
then
    make bcm2712_defconfig
fi
./scripts/config --set-val CONFIG_FONTS y
make olddefconfig
sed 's/^# CONFIG_FONT_TER16x32 is not set/CONFIG_FONT_TER16x32=y/' .config | tee .config.tmp >> /dev/null
sed 's/^CONFIG_FONT_8x8=y/# CONFIG_FONT_8x8 is not set/' .config.tmp | tee .config >> /dev/null
rm .config.tmp
rm .config.old
make -j"$njobs" Image.gz modules dtbs

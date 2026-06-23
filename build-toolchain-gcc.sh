#!/bin/bash

v="4.9.4"

set -e

cd /var/tmp/portage/sys-devel/gcc-$v/work/build
rm -r *
CFLAGS=-fPIC CXXFLAGS=-fPIC /var/tmp/portage/sys-devel/gcc-$v/work/gcc-$v/configure --host=armv7a-unknown-linux-uclibceabihf --build=armv7a-unknown-linux-uclibceabihf --prefix=/opt/gcc --enable-languages=c,c++ --enable-obsolete --enable-secureplt --disable-werror --with-system-zlib --disable-nls --enable-checking=release --with-bugurl=https://bugs.gentoo.org/ --with-pkgversion="PLX" --enable-libstdcxx-time --disable-shared --disable-host-shared --with-boot-ldflags=-static --with-stage1-ldflags=-static --enable-threads=posix --disable-__cxa_atexit --enable-tls --disable-multilib --disable-altivec --disable-fixed-point --with-float=hard --with-arch=armv7-a --with-float=hard --with-fpu=vfpv3-d16 --disable-libgcj --enable-libgomp --disable-libmudflap --disable-libssp --disable-libcilkrts --disable-vtable-verify --disable-libvtv --disable-libquadmath --enable-lto --without-cloog --disable-libsanitizer

make -j"$njobs" &> /home/worker/tmp/gcc-$v-make.log

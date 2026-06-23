#!/bin/bash

set -e

v="2.25.1"

mkdir binutils
cd binutils
tar -xf /usr/portage/distfiles/binutils-"$v".tar.bz2
cd binutils-"$v"
CFLAGS=-fPIC CXXFLAGS=-fPIC ./configure --disable-nls --with-system-zlib --build=armv7a-unknown-linux-uclibceabihf --enable-default-hash-style=gnu --prefix="`pwd`"/build --host=armv7a-unknown-linux-uclibceabihf --target=armv7a-unknown-linux-uclibceabihf --enable-obsolete --enable-threads --enable-relro --enable-install-libiberty --disable-werror --with-bugurl=https://bugs.gentoo.org/ --with-pkgversion="PLX 2.25.1" --disable-shared --enable-static --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --without-stage1-ldflags
make -j"$njobs" configure-host &> /home/worker/tmp/binutils-"$v".make.log
make -j"$njobs" LDFLAGS="-all-static" &>> /home/worker/tmp/binutils-"$v".make.log
make -j"$njobs" install
strip -d build/bin/*

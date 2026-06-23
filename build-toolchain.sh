#!/bin/bash

set -e

. /etc/profile

echo 'MAKEOPTS="-j'"$njobs"'"' >> /etc/portage/make.conf
tar xpf /root/tmp/gentoo-"$tcsnapshotver".tar.xz -C /usr/
mv "/usr/gentoo-$tcsnapshotver" /usr/portage
eselect profile list
mkdir /usr/portage/distfiles
mv /root/tmp/distfiles/* /usr/portage/distfiles/

emerge -q1 libiconv mpc gmp zlib mpfr uclibc-ng # rebuild these

useradd -m -G users -s /bin/bash worker
chmod +x /root/tmp/build-toolchain-*.sh
mkdir /home/worker/tmp
cp /root/tmp/build-toolchain-*.sh /home/worker/tmp/
chown -R worker:worker /home/worker/tmp

echo "Building binutils ..."
su -c '/home/worker/tmp/build-toolchain-binutils.sh' - worker
echo "Built binutils"

cd /usr/portage/eclass
patch -p0 < /root/tmp/toolchain.eclass.patch

if ! emerge -q1 sys-devel/gcc:4.9.4
then
    echo "Building gcc manually ..."
    cd /var/tmp/portage/sys-devel
    chown -R worker:worker gcc-4.9.4
    su -c '/home/worker/tmp/build-toolchain-gcc.sh' - worker
    cd gcc-4.9.4/work/build
    make -j"$njobs" install
    strip -d /opt/gcc/bin/*
    cd /opt/gcc/libexec/gcc/armv7a-unknown-linux-uclibceabihf/4.9.4
    strip -d ./cc1*
    strip -d ./collect*
    strip -d ./lto*
    strip -d ./install-tools/fixincl
    cd /opt/gcc/lib/gcc/armv7a-unknown-linux-uclibceabihf/4.9.4
    strip -d ./*.o ./*.a
    echo "Built gcc manually"
fi

emerge -q1 app-portage/gentoolkit

while read -r file
do
    if [ -d "$file" ]
    then
	continue
    fi
    echo "$file" >> /root/tmp/include-list.txt
done < <(equery -C files uclibc-ng | grep '/usr/include/')

while read -r file
do
    if [ -d "$file" ]
    then
	continue
    fi
    echo "$file" >> /root/tmp/include-list.txt
done < <(equery -C files linux-headers | grep '/usr/include/')

while read -r file
do
    if [ -d "$file" ]
    then
	continue
    fi
    echo "$file" >> /root/tmp/lib-list.txt
done < <(equery -C files uclibc-ng | grep '/lib/')

while read -r file
do
    if [ -d "$file" ]
    then
	continue
    fi
    echo "$file" >> /root/tmp/bin-list.txt
done < <(equery -C files uclibc-ng | grep -e '/bin/')

while read -r file
do
    if [ -d "$file" ]
    then
	continue
    fi
    echo "$file" >> /root/tmp/sbin-list.txt
done < <(equery -C files uclibc-ng | grep -e '/sbin/')

emerge -fqe --update --deep --newuse --autounmask-continue @world @installed sys-devel/libtool

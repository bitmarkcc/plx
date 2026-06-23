set -e

target=armv7a-unknown-linux-uclibceabihf
targetbindir=/usr/armv7a-unknown-linux-uclibceabihf/bin

link_binutils() {
    cd /usr/bin

    if [ ! -e $target-ar ]
    then
	ln -s $targetbindir/ar $target-ar
    fi
    if [ ! -e $target-nm ]
    then
        ln -s $targetbindir/nm $target-nm
    fi
    if [ ! -e $target-ranlib ]
    then
        ln -s $targetbindir/ranlib $target-ranlib
    fi

    if [ ! -e ar ]
    then
	ln -s $target-ar ar
    fi
    if [ ! -e nm ]
    then
	ln -s $target-nm nm
    fi
    if [ ! -e ranlib ]
    then
	ln -s $target-ranlib ranlib
    fi
}

cd
tar -xpf /root/tmp/bootstrap/gentoo-2019.tar.xz -C /usr/
cd /usr
mkdir gentoo-2019/distfiles
mv portage/distfiles/* gentoo-2019/distfiles/
mv portage gentoo-2018
mv gentoo-2019 portage
cd
link_binutils
set +e
emerge -quDN --exclude "gcc busybox libseccomp openssl" @system
set -e
link_binutils
emerge -quDN --exclude "gcc busybox libseccomp openssl" @system

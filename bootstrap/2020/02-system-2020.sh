set -e

target=aarch64-unknown-linux-musl
targetbindir=/usr/$target/bin

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
tar -xpf /root/tmp/bootstrap/gentoo-2020.tar.xz -C /usr/
cd /usr
mkdir gentoo-2020/distfiles
mv portage/distfiles/* gentoo-2020/distfiles/
mv portage gentoo-2019
mv gentoo-2020 portage
cd
set +e
emerge -quDN --exclude "busybox gcc" @system
set -e
link_binutils
emerge -quDN --exclude "busybox gcc" @system

eselect python set python3.8

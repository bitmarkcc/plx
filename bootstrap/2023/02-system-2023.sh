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
tar -xpf /root/tmp/bootstrap/gentoo-2023.tar.xz -C /usr/
cd /usr
mkdir gentoo-2023/distfiles
mv portage/distfiles/* gentoo-2023/distfiles/
mv portage gentoo-2022
mv gentoo-2023 portage

cd /etc/portage
rm make.profile
ln -s ../../usr/portage/profiles/default/linux/arm64/23.0/musl make.profile

cd
#set +e
#emerge -auDN @system
#set -e
#link_binutils
#emerge -auDN @system

#eselect python set python3.11

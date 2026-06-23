set -e

build=armv7a-unknown-linux-uclibceabihf
buildbindir=/usr/$build/bin
target=aarch64-unknown-linux-musl
binutilsdir=/usr/$build/$target/binutils-bin/2.32

link_binutils() {
    cd /usr/bin

    if [ ! -e $build-ar ]
    then
	ln -s $buildbindir/ar $build-ar
    fi
    if [ ! -e $build-ranlib ]
    then
	ln -s $buildbindir/ranlib $build-ranlib
    fi
    if [ ! -e $build-nm ]
    then
	ln -s $buildbindir/nm $build-nm
    fi

    if [ ! -e ar ]
    then
	ln -s $build-ar ar
    fi
    if [ ! -e ranlib ]
    then
	ln -s $build-ranlib ranlib
    fi
    if [ ! -e nm ]
    then
	ln -s $build-nm nm
    fi
    
    if [ ! -e $target-ar ]
    then
        ln -s $binutilsdir/ar $target-ar
    fi
    if [ ! -e $target-ranlib ]
    then
        ln -s $binutilsdir/ranlib $target-ranlib
    fi
    if [ ! -e $target-nm ]
    then
        ln -s $binutilsdir/nm $target-nm
    fi

    cd
}

cd

link_binutils

crossdev --target $target
link_binutils

set -e

asuser() {
	su -c "cd $(pwd) && $*" - worker
}

cd "/home/worker/bld"
asuser tar -xf /usr/portage/distfiles/bash-4.4.tar.gz
cd bash-4.4
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
cd /bin
ln -s ../usr/bin/bash bash
rm sh
ln -s bash sh

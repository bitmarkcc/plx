set -e

mkdir -p /root/bld
cd /root/bld
tar -xf /usr/portage/distfiles/make-4.2.1.tar.bz2
cd make-4.2.1
./configure $obuild $oprefix
./build.sh
cp make /usr/bin/
./configure $obuild $oprefix
make clean
make -j$j
make install

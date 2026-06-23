set -e

cd /root/bld/make-4.2.1
./configure $obuild $oprefix
./build.sh
cp make /usr/bin/
./configure $obuild $oprefix
make clean
make -j$j
make install

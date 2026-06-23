set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/zlib-1.2.11.tar.gz
cd zlib-1.2.11
asuser ./configure $oprefix
asuser make -j$j
make install

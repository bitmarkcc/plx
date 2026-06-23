set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/libiconv-1.15.tar.gz
cd libiconv-1.15
asuser ./configure $obuild $oprefix
asuser make -j$j
make install

set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/patch-2.7.6.tar.xz
cd patch-2.7.6
asuser ./configure $obuild $oprefix
asuser make -j$j
make install

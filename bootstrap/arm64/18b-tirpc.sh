set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/libtirpc-1.2.5.tar.bz2
cd libtirpc-1.2.5
asuser ./configure $obuild $oprefix --disable-gssapi
asuser make -j$j
make install
echo "net-libs/libtirpc-1.2.5" >> /etc/portage/profile/package.provided

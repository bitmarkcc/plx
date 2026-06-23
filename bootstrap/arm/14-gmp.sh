set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/gmp-6.1.2.tar.xz
cd gmp-6.1.2
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
echo "dev-libs/gmp-6.1.2" >> /etc/portage/profile/package.provided

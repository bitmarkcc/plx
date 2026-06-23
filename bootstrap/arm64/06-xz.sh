set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/xz-5.2.3.tar.gz
cd xz-5.2.3
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
echo "app-arch/xz-utils-5.2.3" >> /etc/portage/profile/package.provided

set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/iproute2-4.20.0.tar.xz
cd iproute2-4.20.0
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
echo "sys-apps/iproute2-4.20.0" >> /etc/portage/profile/package.provided

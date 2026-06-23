set -e

cd /root/bld
tar -xf /usr/portage/distfiles/shadow-4.6.tar.gz
cd shadow-4.6
./configure $obuild $oprefix
make -j$j
make install
mkdir /home
groupadd worker
useradd -m -G worker -s /bin/sh worker
mkdir /home/worker/bld
chown -R worker:worker /home/worker/bld

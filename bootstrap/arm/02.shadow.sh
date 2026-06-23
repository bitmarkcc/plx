set -e

cd /root/bld/shadow-4.6
./configure $obuild $oprefix
make -j$j
make install
mkdir /home
groupadd worker
useradd -m -G worker -s /bin/sh worker
mkdir /home/worker/bld
mv /root/bld/busybox-1.29.0 /home/worker/bld/
chown -R worker:worker /home/worker/bld

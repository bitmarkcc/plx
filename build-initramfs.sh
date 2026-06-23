#!/bin/bash

set -e

. /etc/profile

echo 'MAKEOPTS="-j'"$njobs"'"' >> /etc/portage/make.conf
tar xpf /root/tmp/gentoo-"$tcsnapshotver".tar.xz -C /usr/
mv "/usr/gentoo-$tcsnapshotver" /usr/portage
eselect profile list

emerge -q sys-fs/e2fsprogs # rebuild

useradd -m -G users -s /bin/bash worker
chmod +x /root/tmp/build-initramfs-worker.sh
mv /root/tmp /home/worker/
chown -R worker:worker /home/worker/tmp

sed -i 's|$fsckpath|'"`which e2fsck`"'|' /home/worker/tmp/build-initramfs-worker.sh

su -c '/home/worker/tmp/build-initramfs-worker.sh' - worker

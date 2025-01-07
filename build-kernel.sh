#!/bin/bash

set -e

. /etc/profile

tar xpf /root/tmp/gentoo-"$snapshotver".tar.xz -C /var/db/repos/
mv "/var/db/repos/gentoo-$snapshotver" /var/db/repos/gentoo
eselect profile list

emerge -q sys-devel/bc

useradd -m -G users -s /bin/bash worker
chmod +x /root/tmp/build-kernel-worker.sh
mv /root/tmp /home/worker/

su -c '/home/worker/tmp/build-kernel-worker.sh' - worker

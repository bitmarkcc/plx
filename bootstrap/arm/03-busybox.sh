set -e

asuser() {
	su -c "cd $(pwd) && $*" - worker
}

cd "/home/worker/bld/busybox-1.29.0"
asuser make defconfig
sed -i 's/^#.*CONFIG_STATIC .*$/CONFIG_STATIC=y/' .config
asuser make -j$j
cp busybox /bin/

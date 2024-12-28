#!/bin/bash

set -e

firmwarever="1.20241126"
kernelver="20241008"
busyboxver="1_36_1"
stage3ver="20241215T231830Z"
snapshotver="20241222"
KERNEL="kernel8" # kernel_2712 for raspi5
installinchroot=0 # 1 if you will run install.sh in a chroot

njobs="`nproc`"
if [ ! -z "$1" ]
then
    njobs="$1"
fi

user="`logname`"

asuser() {
    sudo -u "$user" $@
}

download_files() {
    echo "Downloading files ..."
    firmwarefile="raspi-firmware_$firmwarever.orig.tar.xz"
    if [ ! -f "$firmwarefile" ]
    then
	echo "Downloading firmware ..."
	asuser curl -L "https://github.com/raspberrypi/firmware/releases/download/$firmwarever/$firmwarefile" -o "$firmwarefile"
    fi
    if ! sha512sum -c "$firmwarefile.SHA512"
    then
       echo "Invalid hash for firmware ($firmwarefile)"
       exit 1
    fi
    kernelfile="linux-stable_$kernelver.tar.gz"
    if [ ! -f "$kernelfile" ]
    then
	echo "Downloading kernel source ..."
	asuser curl -L "https://github.com/raspberrypi/linux/archive/refs/tags/stable_$kernelver.tar.gz" -o "$kernelfile"
    fi
    if ! sha512sum -c "$kernelfile.SHA512"
    then
	echo "Invalid hash for kernel source ($kernelfile)"
	exit 1
    fi
    busyboxfile="busybox-$busyboxver.tar.gz"
    if [ ! -f "$busyboxfile" ]
    then
	echo "Downloading busybox source ..."
	asuser curl -L "https://github.com/mirror/busybox/archive/refs/tags/$busyboxver.tar.gz" -o "$busyboxfile"
    fi
    if ! sha512sum -c "$busyboxfile.SHA512"
    then
	echo "Invalid hash for busybox source ($busyboxfile)"
	exit 1
    fi
    stage3file="stage3-arm64-openrc-$stage3ver.tar.xz"
    if [ ! -f "$stage3file" ]
    then
	echo "Downloading stage3 tarball ..."
	asuser curl -L "https://distfiles.gentoo.org/releases/arm64/autobuilds/$stage3ver/$stage3file" -o "$stage3file"
    fi
    if ! sha512sum -c "$stage3file.SHA512"
    then
	echo "Invalid hash for stage3 tarball ($stage3file)"
	exit 1
    fi
    snapshotfile="gentoo-$snapshotver.tar.xz"
    if [ ! -f "$snapshotfile" ]
    then
	echo "Downloading gentoo snapshot ..."
	asuser curl -L "https://distfiles.gentoo.org/snapshots/$snapshotfile" -o "$snapshotfile"
    fi
    if ! sha512sum -c "$snapshotfile.SHA512"
    then
	echo "Invalid hash for gentoo snapshot ($snapshotfile)"
	exit 1
    fi
    echo "Downloaded files"
}

prepare_disk_image() {
    echo "Preparing disk image ..."
    diskid="`head -c 8 /dev/random | base64 | head -c 8 | sed 's/=/_/g' | sed 's#/#-#g'`"
    diskfile="plx$diskid.img"
    ddcount="8192"
    if [[ "$installinchroot" == "1" ]]
    then
	ddcount="16384"
    fi
    asuser dd if=/dev/zero of="$diskfile" bs=1048576B "count=$ddcount" status=progress
    asuser parted -sa optimal "$diskfile" mklabel gpt
    asuser parted -sa optimal "$diskfile" mkpart boot fat32 1MiB 257MiB
    asuser parted -sa optimal "$diskfile" mkpart root ext4 257MiB 100%
    loopdev="`losetup --partscan --show --find "$diskfile"`"
    mkfs.vfat "$loopdev"p1
    mkfs.ext4 "$loopdev"p2
    echo "$diskfile" | asuser tee diskfile
    echo "$loopdev" | asuser tee loopdev
    echo "Prepared disk image"
}

install_firmware() {
    echo "Installing firmware ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mkdir -p "/mnt/$diskfile"p1
    mount "$loopdev"p1 "/mnt/$diskfile"p1
    if [ -e "raspi-firmware-$firwarever" ]
    then
	asuser rm -r "raspi-firmware-$firmwarever"
    fi
    asuser tar -xf "raspi-firmware_$firmwarever.orig.tar.xz"
    cp -r "raspi-firmware-$firmwarever/boot/"* "/mnt/$diskfile"p1
    umount "/mnt/$diskfile"p1
    echo "Installed firmware"
}

install_kernel() {
    echo "Building and installing kernel ..."
    if [ -e "linux-stable_$kernelver" ]
    then
	asuser rm -r "linux-stable_$kernelver"
    fi
    asuser tar -xf "linux-stable_$kernelver.tar.gz"
    cd "linux-stable_$kernelver"
    if [[ "$KERNEL" == kernel8 ]]
    then
	asuser make bcm2711_defconfig
    elif [[ "$KERNEL" == kernel_2712 ]]
    then
	asuser make bcm2712_defconfig
    fi
    asuser make -j"$njobs" Image.gz dtbs # modules only needed for wifi, I think
    diskfile="`cat ../diskfile | tr -d '\n'`"
    loopdev="`cat ../loopdev | tr -d '\n'`"
    mkdir -p "/mnt/$diskfile"p1
    mount "$loopdev"p1 "/mnt/$diskfile"p1
    cp arch/arm64/boot/Image.gz /mnt/"$diskfile"p1/"$KERNEL".img
    cp arch/arm64/boot/dts/broadcom/*.dtb /mnt/"$diskfile"p1/
    mkdir -p /mnt/"$diskfile"p1/overlays
    cp arch/arm64/boot/dts/overlays/*.dtb* /mnt/"$diskfile"p1/overlays/
    cp arch/arm64/boot/dts/overlays/README /mnt/"$diskfile"p1/overlays/
    umount "/mnt/$diskfile"p1
    cd ..
    ususer rm -r "linux-stable_$kernelver"
    echo "Installed kernel"
}

install_stage3() {
    echo "Installing stage3 tarball (with some modifications)..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    mkdir -p "$mountpoint"
    if ! df | grep "$mountpoint"
    then
	mount "$loopdev"p2 "$mountpoint"
    fi
    tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    mkdir "$mountpoint/root/tmp"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    if [ -e portage/env ]
    then
	cp -r portage/env "$mountpoint/etc/portage/"
    fi
    cp portage/make.conf "$mountpoint/etc/portage/"
    if [ -e portage/package.accept_keywords ]
    then
	cp portage/package.accept_keywords/* "$mountpoint/etc/portage/package.accept_keywords/"
    fi
    if [ -e portage/package.env ]
    then
	cp portage/package.env "$mountpoint/etc/portage/"
    fi
    if [ -e portage/package.license ]
    then
	cp portage/package.license "$mountpoint/etc/portage/"
    fi
    if [ -e portage/package.mask ]
    then
	cp portage/package.mask/* "$mountpoint/etc/portage/package.mask/"
    fi
    if [ -e portage/package.use ]
    then
	cp portage/package.use/* "$mountpoint/etc/portage/package.use/"
    fi
    echo "UTC" > "$mountpoint/etc/timezone"
    cp world "$mountpoint/var/lib/portage/"
    umount "$mountpoint"
    echo "Installed stage3 tarball"
}

get_distfiles_and_autounmasking() {
    echo "Get distfiles and autounmasking ..."
    prepare_for_chroot
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    cp fetch-autounmask.sh "$mountpoint/root/tmp"
    chmod +x "$mountpoint/root/tmp/fetch-autounmask.sh"
    chroot "$mountpoint" "/root/tmp/fetch-autounmask.sh" "$snapshotver"
    if [ -e distfiles ]
    then
	rm -r distfiles
    fi
    asuser mkdir distfiles
    asuser cp "--preserve=mode,timestamps" "$mountpoint/var/cache/distfiles/"* distfiles
    if [ -e portage.auto ]
    then
	rm -r portage.auto
    fi
    asuser cp -r "--preserve=mode,timestamps" "$mountpoint/etc/portage" portage.auto
    echo "Got distfiles and autounmasking"
}

finalize_root_fs() {
    echo "Finalizing root filesystem ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    mkdir -p "$mountpoint"
    if ! df | grep "$mountpoint"
    then
	mount "$loopdev"p2 "$mountpoint"
    fi
    tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    mkdir "$mountpoint/root/tmp"
    cp cupsd.conf "$mountpoint/root/tmp/"
    cp -r "--preserve=mode,timestamps" distfiles/* "$mountpoint/var/cache/distfiles/"
    cp fstab "$mountpoint/etc/"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp -r home "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    cp install.sh "$mountpoint/root/tmp/"
    chmod +x "$mountpoint/root/tmp/install.sh"
    sed -i 's/$snapshotver/'"$snapshotver"'/g' "$mountpoint/root/tmp/install.sh"
    if [[ "$installinchroot" == "1" ]]
    then
	sed -i 's/chroot=0/chroot=1/' "$mountpoint/root/tmp/install.sh"
    fi
    cp inittab "$mountpoint/etc/"
    if [ -e portage.auto/env ]
    then
	cp -r portage.auto/env "$mountpoint/etc/portage/"
    fi
    cp portage.auto/make.conf "$mountpoint/etc/portage/"
    if [ -e portage.auto/package.accept_keywords ]
    then
	cp portage.auto/package.accept_keywords/* "$mountpoint/etc/portage/package.accept_keywords/"
    fi
    if [ -e portage.auto/package.env ]
    then
	cp portage.auto/package.env "$mountpoint/etc/portage/"
    fi
    if [ -e portage.auto/package.license ]
    then
	cp portage.auto/package.license "$mountpoint/etc/portage/"
    fi
    if [ -e portage.auto/package.mask ]
    then
	cp portage.auto/package.mask/* "$mountpoint/etc/portage/package.mask/"
    fi
    if [ -e portage.auto/package.use ]
    then
	cp portage.auto/package.use/* "$mountpoint/etc/portage/package.use/"
    fi
    echo "UTC" > "$mountpoint/etc/timezone"
    cp world "$mountpoint/var/lib/portage/"
    umount "$mountpoint"
    echo "Finalized root filesystem"
}

clear_root_fs() {
    echo "Clearing root filesystem ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    mkdir -p "$mountpoint"
    if df -a | grep "$mountpoint/proc"
    then
	unprepare_for_chroot
    fi
    if df | grep "$mountpoint"
    then
	umount "$mountpoint"
    fi
    mkfs.ext4 -F "$loopdev"p2
    echo "Cleared root filesystem"
}

prepare_for_chroot() {
    echo "Preparing for chroot ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    mkdir -p "$mountpoint"
    if ! df | grep "$mountpoint"
    then
	mount "$loopdev"p2 "$mountpoint"
    fi
    if ! df | grep "$mountpoint/proc"
    then
	mount -t proc proc "$mountpoint/proc"
    fi
    if ! df | grep "$mountpoint/sys"
    then
	mount --rbind /sys "$mountpoint/sys"
    fi
    if ! df | grep "$mountpoint/dev"
    then
	mount --rbind /dev "$mountpoint/dev"
    fi
    if ! df | grep "$mountpoint/run"
    then
	mount --rbind /run "$mountpoint/run"
    fi
    cp -L /etc/resolv.conf "$mountpoint/etc/"
    echo "Prepared for chroot"
}

unprepare_for_chroot() {
    echo "Undoing chroot preparations ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    if mount | grep "$mountpoint/run"
    then
	umount -l "$mountpoint/run"
    fi
    if mount | grep "$mountpoint/dev/pts"
    then
	umount -l "$mountpoint/dev/pts"
    fi
    if mount | grep "$mountpoint/dev"
    then
	umount -l "$mountpoint/dev"
    fi
    if mount | grep "$mountpoint/sys"
    then
	umount -l "$mountpoint/sys"
    fi
    if mount | grep "$mountpoint/proc"
    then
	umount -l "$mountpoint/proc"
    fi
    if mount | grep "$mountpoint"
    then
	umount -l "$mountpoint"
    fi
    sleep 1 # todo: fix this hack
    if ! df -a | grep "/dev/pts"
    then
	mount none -t devpts /dev/pts
    fi
    echo "Chroot preparations undone"
}

finalize_disk_image() {
    #todo
}

clean() {
    echo "Cleaning PLX build files ..."
    asuser rm -rf "initramfs.cpio.gz"
    asuser rm -rf "initramfs"
    asuser rm -rf "linux-stable_$kernelver"
    asuser rm -rf "raspi-firmware-$firmwarever"
    if [ -e diskfile ]
    then
	unprepare_for_chroot
	diskfile="`cat diskfile | tr -d '\n'`"
	if [ -e "/mnt/$diskfile"p1 ]
	then
	    rmdir "/mnt/$diskfile"p1
	fi
	if [ -e "/mnt/$diskfile"p2 ]
	then
	    rmdir "/mnt/$diskfile"p2
	fi
	if [ -e loopdev ]
	then
	    loopdev="`cat loopdev | tr -d '\n'`"
	    losetup -d "$loopdev"
	    asuser rm loopdev
	fi
	asuser rm "$diskfile"
	asuser rm diskfile
    fi
    if [ -e portage.auto ]
    then
	rm -r portage.auto
    fi
    if [ -e distfiles ]
    then
	rm -r distfiles
    fi
    echo "Cleaned PLX build files"
}

rebuild_toolchain() { #not tested
    echo "Rebuilding toolchain ..."
    cp toolchain.sh source/root/tmp/
    chroot source/ /root/tmp/toolchain.sh
    rm source/root/tmp/toolchain.sh
}

install_initramfs() {

    echo "Install initramfs ..."

    if [ -e initramfs.cpio.gz ]
    then
	asuser rm -r initramfs.cpio.gz
    fi
    if [ -e initramfs ]
    then
	asuser rm -r initramfs
    fi
    if [ -e "busybox-$busyboxver" ]
    then
	asuser rm -r "busybox-$busyboxver"
    fi
    
    asuser mkdir initramfs
    asuser mkdir initramfs/root
    asuser mkdir initramfs/etc
    asuser mkdir initramfs/lib
    asuser mkdir initramfs/bin
    asuser mkdir initramfs/sbin
    asuser mkdir -p initramfs/usr/bin
    asuser mkdir -p initramfs/usr/sbin
    asuser mkdir initramfs/proc
    asuser mkdir initramfs/sys
    asuser mkdir initramfs/dev
    asuser mkdir initramfs/mnt

    asuser tar -xf "busybox-$busyboxver.tar.gz"
    cd "busybox-$busyboxver"
    asuser make defconfig
    asuser sed -i 's/^CONFIG_TC=.*$/CONFIG_TC=n/' .config
    #sed -e 's/.*STATIC.*/CONFIG_STATIC=y/' -i .config
    #sed -e 's/.*FEATURE_PREFER_APPLETS.*/CONFIG_FEATURE_PREFER_APPLETS=y/' -i .config
    #sed -e 's/.*FEATURE_SH_STANDALONE.*/CONFIG_FEATURE_SH_STANDALONE=y/' -i .config
    asuser make -j"$njobs"
    #make install
    cd ../
    asuser ldd "busybox-$busyboxver/busybox" | sudo -u "$user" awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs sudo -u "$user" dirname | xargs -t -I '{}' sudo -u "$user" mkdir -p initramfs'{}'
    asuser ldd "busybox-$busyboxver/busybox" | sudo -u "$user" awk '{ for(i = 1; i <= NF; i++) { if($i~/[/].*[.]so/)print $i; } }' | xargs -t -I '{}' sudo -u "$user" cp '{}' initramfs'{}'
    asuser cp "busybox-$busyboxver/busybox initramfs/bin/"
    asuser rm -r "busybox-$busyboxver"
    asuser cp init.sh initramfs/init
    asuser chmod +x initramfs/init

    cd initramfs
    asuser find . -print0 | asuser cpio --null -ov --format=newc | asuser gzip -9 | asuser tee ../initramfs.cpio.gz >> /dev/null
    cd ..
    #asuser rm -r initramfs #tmp don't delete
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p1
    mkdir -p "$mountpoint"
    mount "$loopdev"p1 "$mountpoint"
    cp initramfs.cpio.gz "$mountpoint/"
    cp cmdline.txt "$mountpoint/"
    cp config.txt "$mountpoint/"
    umount "$mountpoint"
    echo "Installed initramfs"
}

main() {
    download_files
    prepare_disk_image
    install_firmware
    install_kernel
    install_initramfs
    clear_root_fs
    install_stage3
    prepare_for_chroot
    get_distfiles_and_autounmasking
    clear_root_fs
    finalize_root_fs
}

main

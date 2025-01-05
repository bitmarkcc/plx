#!/bin/bash

set -e

firmwarever="1.20241126"
kernelver="20241008"
busyboxver="1_36_1"
muslver="20241230T163322Z"
stage3ver="20241230T163322Z"
snapshotver="20250101"
plxolver="1.0.0" # PLX overlay version
KERNEL="kernel8" # kernel_2712 for raspi5
installinchroot=0 # 1 if you will run install.sh in a chroot
libc="musl" # musl or glibc

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
    muslfile="stage3-arm64-musl-$muslver.tar.xz"
    if [ ! -f "$muslfile" ]
    then
	echo "Downloading musl stage3 source ..."
	asuser curl -L "https://plx.im/gentoo/$muslfile" -o "$muslfile"
    fi
    if ! sha512sum -c "$muslfile.SHA512"
    then
	echo "Invalid hash for musl (stage3) source ($musfile)"
	exit 1
    fi
    if [[ "$libc" == "glibc" ]]
    then
	stage3file="stage3-arm64-openrc-$stage3ver.tar.xz"
	if [ ! -f "$stage3file" ]
	then
	    echo "Downloading stage3 tarball ..."
	    asuser curl -L "https://plx.im/gentoo/$stage3file" -o "$stage3file"
	fi
	if ! sha512sum -c "$stage3file.SHA512"
	then
	    echo "Invalid hash for stage3 tarball ($stage3file)"
	    exit 1
	fi
    fi
    snapshotfile="gentoo-$snapshotver.tar.xz"
    if [ ! -f "$snapshotfile" ]
    then
	echo "Downloading gentoo snapshot ..."
	asuser curl -L "https://plx.im/gentoo/$snapshotfile" -o "$snapshotfile"
    fi
    if ! sha512sum -c "$snapshotfile.SHA512"
    then
	echo "Invalid hash for gentoo snapshot ($snapshotfile)"
	exit 1
    fi
    plxolfile="plx-overlay-$plxolver.tar.gz"
    if [ ! -f "$plxolfile" ]
    then
	echo "Downloading plx overlay ..."
	asuser curl -L "https://github.com/bitmarkcc/plx-overlay/archive/refs/tags/v$plxolver.tar.gz" -o "$plxolfile"
    fi
    if ! sha512sum -c "$plxolfile.SHA512"
    then
	echo "Invalid hash for PLX overlay file ($plxolfile)"
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
    sleep 3
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
    ./scripts/config --set-val CONFIG_FONTS y
    asuser make olddefconfig
    sed 's/^# CONFIG_FONT_TER16x32 is not set/CONFIG_FONT_TER16x32=y/' .config | asuser tee .config.tmp >> /dev/null
    sed 's/^CONFIG_FONT_8x8=y/# CONFIG_FONT_8x8 is not set/' .config.tmp | asuser tee .config >> /dev/null
    rm .config.tmp
    rm .config.old
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
    asuser rm -r "linux-stable_$kernelver"
    echo "Installed kernel"
}

install_stage3() {
    echo "Installing stage3 tarball (with some modifications)..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    stage3file="stage3-arm64-openrc-$stage3ver.tar.xz"
    mkdir -p "$mountpoint"
    if ! df | grep "$mountpoint"
    then
	mount "$loopdev"p2 "$mountpoint"
    fi
    if [[ "$libc" == "musl" ]]
    then
	tar xpf "stage3-arm64-musl-$muslver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    else
	tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    fi
    mkdir "$mountpoint/root/tmp"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    cp "plx-overlay-$plxolver.tar.gz" "$mountpoint/root/tmp/"
    cp plx-pgp.asc "$mountpoint/root/tmp/"
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
	cp -rT portage/package.env "$mountpoint/etc/portage/package.env"
    fi
    if [ -e portage/package.license ]
    then
	cp -rT portage/package.license "$mountpoint/etc/portage/package.license"
    fi
    if [ -e portage/package.mask ]
    then
	cp portage/package.mask/* "$mountpoint/etc/portage/package.mask/"
    fi
    if [ -e portage/package.use ]
    then
	cp portage/package.use/* "$mountpoint/etc/portage/package.use/"
    fi
    if [ -e portage/repos.conf ]
    then
	cp -rT portage/repos.conf "$mountpoint/etc/portage/repos.conf"
    fi
    if [[ "$libc" == "glibc" ]]
    then
	echo "UTC" > "$mountpoint/etc/timezone"
    fi
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
    sed -i 's/$snapshotver/'"$snapshotver"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    sed -i 's/$plxolver/'"$plxolver"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    sed -i 's/$libc/'"$libc"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    chmod +x "$mountpoint/root/tmp/fetch-autounmask.sh"
    chroot "$mountpoint" "/root/tmp/fetch-autounmask.sh" "$snapshotver"
    if [ -e distfiles ]
    then
	rm -r distfiles
    fi
    asuser mkdir distfiles
    asuser cp "--preserve=mode,timestamps" "$mountpoint/var/cache/distfiles/"* distfiles/
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
    if [[ "$libc" == "musl" ]]
    then
	tar xpf "stage3-arm64-musl-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    else
	tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    fi
    mkdir "$mountpoint/root/tmp"
    echo 'if [[ "`tty`" == "/dev/tty1" ]]' > "$mountpoint/root/.bash_profile"
    echo 'then' >> "$mountpoint/root/.bash_profile"
    echo -e "\t/root/tmp/install.sh" >> "$mountpoint/root/.bash_profile"
    echo 'fi' >> "$mountpoint/root/.bash_profile"
    cp cupsd.conf "$mountpoint/root/tmp/"
    cp "--preserve=mode,timestamps" distfiles/* "$mountpoint/var/cache/distfiles/"
    cp fstab "$mountpoint/etc/"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp -r home "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    chmod +x init.d/*
    cp -r "--preserve=mode" init.d/* "$mountpoint/etc/init.d/"
    cp install.sh "$mountpoint/root/tmp/"
    chmod +x "$mountpoint/root/tmp/install.sh"
    sed -i 's/$snapshotver/'"$snapshotver"'/g' "$mountpoint/root/tmp/install.sh"
    sed -i 's/$plxolver/'"$plxolver"'/g' "$mountpoint/root/tmp/install.sh"
    sed -i 's/$libc/'"$libc"'/' "$mountpoint/root/tmp/install.sh"
    if [[ "$installinchroot" == "1" ]]
    then
	sed -i 's/chroot=0/chroot=1/' "$mountpoint/root/tmp/install.sh"
    fi
    cp inittab "$mountpoint/etc/"
    chmod +x *.start
    cp "--preserve=mode" staticip.start "$mountpoint/etc/local.d/"
    cp "plx-overlay-$plxolver.tar.gz" "$mountpoint/root/tmp/"
    cp plx-pgp.asc "$mountpoint/root/tmp/"
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
	cp -rT portage.auto/package.env "$mountpoint/etc/portage/package.env"
    fi
    if [ -e portage.auto/package.license ]
    then
	cp -rT portage.auto/package.license "$mountpoint/etc/portage/package.license"
    fi
    if [ -e portage.auto/package.mask ]
    then
	cp portage.auto/package.mask/* "$mountpoint/etc/portage/package.mask/"
    fi
    if [ -e portage.auto/package.use ]
    then
	cp portage.auto/package.use/* "$mountpoint/etc/portage/package.use/"
    fi
    pw="$diskfile"
    echo "root:$pw" > "$mountpoint/root/tmp/pw"
    sed -i 's/^#PasswordAuthentication .*$/PasswordAuthentication no/' "$mountpoint/etc/ssh/sshd_config"
    if [ -e id_rsa.pub ]
    then
	mkdir -p "$mountpoint/root/.ssh"
	cat id_rsa.pub >> "$mountpoint/root/.ssh/authorized_keys"
    fi
    cp swclock-helper.sh "$mountpoint/usr/local/bin/"
    chmod +x "$mountpoint/usr/local/bin/swclock-helper.sh"
    if [[ "$libc" == "glibc" ]]
    then
	echo "UTC" > "$mountpoint/etc/timezone"
    fi
    cp world "$mountpoint/var/lib/portage/"
    sed -i 's/$date/'"`date`"'/g' "$mountpoint/root/tmp/install.sh"
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
    sleep 3
    if ! mkfs.ext4 -F "$loopdev"p2
    then
	fuser -km "$loopdev"p2
	sleep 3
	mkfs.ext4 -F "$loopdev"p2
    fi
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

prepare_for_musl_chroot() {
    echo "Preparing for musl chroot ..."
    mountpoint="muslroot"
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
    echo "Prepared for musl chroot"
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
	mount -t devpts none /dev/pts
    fi
    if ! df -a | grep "/dev/shm"
    then
	mount -t tmpfs none /dev/shm
    fi
    echo "Chroot preparations undone"
}

unprepare_for_musl_chroot() {
    echo "Undoing musl chroot preparations ..."
    mountpoint="muslroot"
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
	mount -t devpts none /dev/pts
    fi
    if ! df -a | grep "/dev/shm"
    then
	mount -t tmpfs none /dev/shm
    fi
    echo "Musl chroot preparations undone"
}

finalize_disk_image() {
    echo "Finalizing disk image ..."
    unprepare_for_chroot
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    losetup -d "$loopdev"
    #asuser xz -k "$diskfile"
    echo "Finalized disk image"
}

clean() {
    echo "Cleaning PLX build files ..."
    asuser rm -rf "initramfs.cpio.gz"
    rm -rf "muslroot"
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
	    set +e
	    losetup -d "$loopdev"
	    set -e
	    asuser rm loopdev
	fi
	asuser rm "$diskfile"
	if [ -e "$diskfile.xz" ]
	then
	    asuser rm "$diskfile.xz"
	fi
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

build_initramfs() { # inside a musl chroot

    echo "Building initramfs ..."

    if [ -e initramfs.cpio.gz ]
    then
	asuser rm -r initramfs.cpio.gz
    fi
    if [ -e initramfs ] # not needed anymore
    then
	asuser rm -r initramfs
    fi
    if [ -e "busybox-$busyboxver" ] # not needed anymore
    then
	asuser rm -r "busybox-$busyboxver"
    fi

    if [ -e muslroot ]
    then
	unprepare_for_musl_chroot
	rm -r muslroot
    fi
    
    mkdir muslroot
    tar xpf "stage3-arm64-musl-$muslver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "muslroot"
    mkdir muslroot/root/tmp
    cp build-initramfs.sh muslroot/root/tmp/
    chmod +x muslroot/root/tmp/build-initramfs.sh
    cp init.sh muslroot/root/tmp/
    cp build-initramfs-worker.sh muslroot/root/tmp
    cp "busybox-$busyboxver.tar.gz" muslroot/root/tmp/
    sed -i 's/$busyboxver/'"$busyboxver"'/' muslroot/root/tmp/build-initramfs-worker.sh
    sed -i 's/$njobs/'"$njobs"'/' muslroot/root/tmp/build-initramfs-worker.sh
    prepare_for_musl_chroot
    chroot muslroot /root/tmp/build-initramfs.sh
    unprepare_for_musl_chroot

    cd muslroot/home/worker/initramfs
    asuser find . -print0 | asuser cpio --null -ov --format=newc | asuser gzip -9 | asuser tee "$workdir/initramfs.cpio.gz" >> /dev/null
    cd "$workdir"

    echo "Built initramfs"
}

install_initramfs() {

    echo "Installing initramfs ..."
    
    build_initramfs

    if [ -e muslroot ]
    then
	rm -r muslroot
    fi
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
    if [[ "$installinchroot" == 1 ]]
    then
	prepare_for_chroot
	diskfile="`cat diskfile | tr -d '\n'`"
	mountpoint="/mnt/$diskfile"p2
	chroot "$mountpoint" /root/tmp/install.sh
    fi
    finalize_disk_image
}

workdir="`pwd`"
njobs="`nproc`"
user="`logname`"
if [ ! -z "$1" ]
then
    if [[ "$1" == "clean" ]]
    then
	clean
	exit 0
    else
	njobs="$1"
    fi
fi

main

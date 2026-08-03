#!/bin/bash

set -e

arch="amd64"
firmwarever="1.20241126"
kernelver="20260527"
muslver="20260607T234631Z" # musl stage3 tarball
uclibcver="20181008" # uclibc stage3 tarball
stage3ver="20260607T234631Z"
snapshotver="20260703"
tcsnapshotver="2018"
plxolver="1.1.1" # PLX overlay version
KERNEL="kernel8" # kernel_2712 for raspi5
installinchroot=0 # 1 if you will run install.sh in a chroot
libc="musl" # musl or glibc
ddcount="8192" # number of MiB for the capacity of the disk image, 8 GiB by default
livebootstraprepo="https://github.com/bitmarkcc/live-bootstrap"
livebootstrapcommit="742f856906af4b8c0cf3e8b2d58f82e0f6280709"
livebootstrapdistfiles="https://plx.im/live-bootstrap/"

asuser() {

    if ! command -v sudo
    then
	"$@"
    elif [[ "`type -t "$1"`" == "function" ]]
    then
	FUNC="`declare -f "$1"`"
	sudo -u "$user" bash -c "$FUNC; $*"
    else
	sudo -u "$user" "$@"
    fi
}

cpP() {
    cp -rP --preserve=mode,timestamps "$@"
}

download_files_dir() {
    cd "$1"
    while read -r file
    do
	content="${file::-7}"
	if [ ! -f "$content" ]
	then
	    echo "Downloading $content ..."
	    if [ -z "$2" ]
	    then
		asuser curl -o "$content" -L "https://plx.im/distfiles/$content"
	    else
		asuser curl -o "$content" -L "$2$content"
	    fi
	    echo "Downloaded $content"
	fi
	if ! sha512sum -c "$file"
	then
	    echo "Invalid hash for file $1/$file"
	    exit 1
	fi
    done < <(find -maxdepth 1 -name '*.SHA512')
    cd "$workdir"
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
    muslfile="stage3-arm64-musl-openrc-$muslver.tar.xz"
    if [ ! -f "$muslfile" ]
    then
	echo "Downloading musl stage3 tarball ..."
	asuser curl -L "https://plx.im/gentoo/$muslfile" -o "$muslfile"
    fi
    if ! sha512sum -c "$muslfile.SHA512"
    then
	echo "Invalid hash for musl (stage3) tarball ($musfile)"
	exit 1
    fi
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
    uclibcfile="stage3-armv7a_hardfp-uclibc-vanilla-$uclibcver.tar.bz2"
    if [ ! -f "$uclibcfile" ]
    then
	echo "Downloads uclibc stage3 tarball ..."
	asuser curl -o "$uclibcfile" -L "https://plx.im/gentoo/$uclibcfile"
    fi
    if ! sha512sum -c "$uclibcfile.SHA512"
    then
	echo "Invalid hash for uclibc stage3 tarball ($uclibcfile)"
	exit 1
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

    download_toolchain_files
    download_bootstrap_files
    
    echo "Downloaded files"
}

download_toolchain_files() {

    echo "Downloading toolchain files ..."

    download_files_dir toolchain/distfiles

    echo "Downloaded toolchain files"
}

download_bootstrap_files() {

    echo "Downloading bootstrap files ..."

    download_files_dir bootstrap
    download_files_dir bootstrap/distfiles

    echo "Downloaded bootstrap files ..."
    
}

download_bootstrap_amd64_files() {

    echo "Downloading bootstrap amd64 files ..."

    if [ ! -e live-bootstrap ]
    then
	git clone --recursive "$livebootstraprepo"
    fi
    cd live-bootstrap
    commit="`git rev-parse HEAD`"
    if [[ "$commit" != "$livebootstrapcommit" ]]
    then
	echo "Invalid commit for live-bootstrap repo"
	exit 1
    fi
    cd ..

    download_files_dir live-bootstrap/distfiles "$livebootstrapdistfiles"
    
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

    download_files_dir bootstrap-amd64/distfiles

    echo "Downloaded bootstrap amd64 files ..."
    
}

prepare_disk_image() {
    echo "Preparing disk image ..."
    diskid="`head -c 8 /dev/random | base64 | head -c 8 | sed 's/=/_/g' | sed 's#/#-#g'`"
    diskfile="plx$diskid.img"
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

prepare_disk_image_amd64() {
    echo "Preparing AMD64 disk image ..."
    diskid="`head -c 8 /dev/random | base64 | head -c 8 | sed 's/=/_/g' | sed 's#/#-#g'`"
    diskfile="plx$diskid.img"
    DISK=56G ./make-bare-metal.sh --update-checksums
    mv live-bootstrap/target/init.img "$diskfile"
    echo "Prepared AMD64 disk image"
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

build_kernel() {
    echo "Building kernel ..."
    
    if [ -e "linux-stable_$kernelver" ] # not needed anymore
    then
	asuser rm -r "linux-stable_$kernelver"
    fi
    if [ -e muslroot ]
    then
	unprepare_for_chroot muslroot
	rm -r muslroot
    fi
    if [ -e modules ]
    then
	rm -r modules
    fi

    mkdir muslroot
    tar xpf "stage3-arm64-musl-openrc-$muslver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "muslroot"
    mkdir muslroot/root/tmp
    cp build-kernel.sh muslroot/root/tmp/
    chmod +x muslroot/root/tmp/build-kernel.sh
    cp build-kernel-worker.sh muslroot/root/tmp/
    cp "linux-stable_$kernelver.tar.gz" muslroot/root/tmp/
    cp "gentoo-$snapshotver.tar.xz" muslroot/root/tmp/
    sed -i 's/$snapshotver/'"$snapshotver"'/' muslroot/root/tmp/build-kernel.sh
    sed -i 's/$kernelver/'"$kernelver"'/' muslroot/root/tmp/build-kernel.sh
    sed -i 's/$njobs/'"$njobs"'/' muslroot/root/tmp/build-kernel.sh
    sed -i 's/$kernelver/'"$kernelver"'/' muslroot/root/tmp/build-kernel-worker.sh
    sed -i 's/$njobs/'"$njobs"'/' muslroot/root/tmp/build-kernel-worker.sh
    sed -i 's/$KERNEL/'"$KERNEL"'/' muslroot/root/tmp/build-kernel-worker.sh
    prepare_for_chroot muslroot
    chroot muslroot /root/tmp/build-kernel.sh
    unprepare_for_chroot muslroot

    echo "Built kernel"
}

install_kernel() { # in a musl chroot
    echo "Installing kernel ..."

    build_kernel

    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mkdir -p "/mnt/$diskfile"p1
    mount "$loopdev"p1 "/mnt/$diskfile"p1
    kernelbuildpath="muslroot/home/worker/linux-stable_$kernelver/arch/arm64/boot"
    cp "$kernelbuildpath/Image.gz" /mnt/"$diskfile"p1/"$KERNEL".img
    cp "$kernelbuildpath/dts/broadcom/"*.dtb /mnt/"$diskfile"p1/
    mkdir -p /mnt/"$diskfile"p1/overlays
    cp "$kernelbuildpath/dts/overlays/"*.dtb* /mnt/"$diskfile"p1/overlays/
    cp "$kernelbuildpath/dts/overlays/README" /mnt/"$diskfile"p1/overlays/
    cp -a "muslroot/lib/modules" modules
    umount "/mnt/$diskfile"p1
    rm -r "muslroot"
    
    echo "Installed kernel"
}

install_stage3() {
    echo "Installing stage3 tarball (with some modifications)..."
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="mainroot"
    if [ -e "$mountpoint" ]
    then
	unprepare_for_chroot "$mountpoint"
	rm -r "$mountpoint"
    fi
    mkdir -p "$mountpoint"
    if [[ "$libc" == "musl" ]]
    then
	tar xpf "stage3-arm64-musl-openrc-$muslver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    else
	tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"
    fi
    mkdir "$mountpoint/root/tmp"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    cp "plx-overlay-$plxolver.tar.gz" "$mountpoint/root/tmp/"
    #cp plx-pgp.asc "$mountpoint/root/tmp/"
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
    echo "Installed stage3 tarball to mainroot/"
}

get_distfiles_and_autounmasking() {
    echo "Get distfiles and autounmasking ..."
    if [ ! -e mainroot ]
    then
	echo "Install stage3 tarball before getting distfiles/autounmasking"
	exit 1
    fi
    mountpoint="mainroot"
    prepare_for_chroot "$mountpoint"
    cp fetch-autounmask.sh "$mountpoint/root/tmp/"
    sed -i 's/$snapshotver/'"$snapshotver"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    sed -i 's/$plxolver/'"$plxolver"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    sed -i 's/$libc/'"$libc"'/' "$mountpoint/root/tmp/fetch-autounmask.sh"
    exclude="`cat exclude | sed 's/#.*$//' | tr '\n' ' ' | xargs | tr -d '\n'`"
    sed -i 's|$exclude|'"$exclude"'|' "$mountpoint/root/tmp/fetch-autounmask.sh"
    chmod +x "$mountpoint/root/tmp/fetch-autounmask.sh"
    chroot "$mountpoint" "/root/tmp/fetch-autounmask.sh"
    if [ -e distfiles ]
    then
	asuser rm -r distfiles
    fi
    asuser mkdir distfiles
    asuser cpP "$mountpoint/var/cache/distfiles/"* distfiles/
    if [ -e portage.auto ]
    then
	asuser rm -r portage.auto
    fi
    asuser cpP "$mountpoint/etc/portage" portage.auto
    unprepare_for_chroot "$mountpoint"
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

    cd "$mountpoint"
    asuser zcat "$workdir"/initramfs.cpio.gz | cpio -idm --no-absolute-filenames
    rm init
    mkdir root/tmp
    cpP "$workdir/bootstrap/init.sh" root/tmp/
    sed -i 's/chroot=0/'"chroot=$installinchroot"'/' root/tmp/init.sh
    cpP root/tmp/init.sh sbin/init
    
    cpP "$workdir/toolchain/build/binutils/bin/"* usr/bin/
    cpP "$workdir/toolchain/build/gcc/bin/"* usr/bin/
    cd usr/bin
    ln -s gcc cc
    cd "$mountpoint"
    cpP "$workdir/toolchain/build/gcc/libexec/gcc" usr/libexec/
    cpP "$workdir/toolchain/build/gcc/lib/"* usr/lib/
    mkdir usr/include
    cpP "$workdir/toolchain/build/include/"* usr/include/
    cpP "$workdir/toolchain/build/gcc/include/c++/4.9.4/"* usr/lib/gcc/armv7a-unknown-linux-uclibceabihf/4.9.4/include/
    cd usr/lib/gcc/armv7a-unknown-linux-uclibceabihf/4.9.4/include
    mv armv7a-unknown-linux-uclibceabihf/bits/* bits/
    mv armv7a-unknown-linux-uclibceabihf/ext/* ext/
    cd "$mountpoint"
    cpP "$workdir/toolchain/build/lib/"* usr/lib/
    cpP "$workdir/toolchain/build/bin/"* usr/bin/ # for now only uclibc-ng has bins here which go in usr/bin. todo: make more general
    cpP "$workdir/toolchain/build/sbin/"* sbin/
    cpP "$workdir/toolchain/build/bld/"* root/bld/
    
    cpP "$workdir/modules" lib/
    echo 'if [[ "`tty`" == "/dev/tty1" ]]' > "$mountpoint/root/.bash_profile"
    echo 'then' >> "$mountpoint/root/.bash_profile"
    echo -e "\t/root/tmp/install.sh" >> "$mountpoint/root/.bash_profile"
    echo 'fi' >> "$mountpoint/root/.bash_profile"
    cpP "$workdir/cupsd.conf" root/tmp/
    mkdir -p usr/portage/distfiles
    mkdir -p var/cache/distfiles
    cpP "$workdir/bootstrap/distfiles/"* usr/portage/distfiles/
    mkdir root/tmp/bootstrap
    cpP "$workdir/bootstrap/"*ash-*.sh root/tmp/bootstrap/
    cpP "$workdir/bootstrap/vars-arm"*.sh root/tmp/bootstrap/
    cpP "$workdir/bootstrap/arm" root/tmp/bootstrap/
    cpP "$workdir/bootstrap/arm64" root/tmp/bootstrap/
    cpP "$workdir/bootstrap/202"* root/tmp/bootstrap/
    cpP "$workdir/bootstrap/gentoo-"*.tar.xz root/tmp/bootstrap/
    cpP "$workdir/distfiles/"* var/cache/distfiles/
    cpP "$workdir/fstab" etc/
    cpP "$workdir/gentoo-$tcsnapshotver.tar.xz" root/tmp/
    cpP "$workdir/gentoo-$snapshotver.tar.xz" root/tmp/
    cpP "$workdir/home" root/tmp/
    cpP "$workdir/hostname" etc/
    chmod +x "$workdir/init.d/"*
    mkdir etc/init.d
    cpP "$workdir/init.d/"* etc/init.d/
    cpP "$workdir/install.sh" root/tmp/
    chmod +x root/tmp/install.sh
    sed -i 's/$snapshotver/'"$snapshotver"'/g' root/tmp/install.sh
    sed -i 's/$plxolver/'"$plxolver"'/g' root/tmp/install.sh
    sed -i 's/$libc/'"$libc"'/' root/tmp/install.sh
    exclude="`cat "$workdir/exclude" | sed 's/#.*$//' | tr '\n' ' ' | xargs | tr -d '\n'`"
    sed -i 's|$exclude|'"$exclude"'|' root/tmp/install.sh
    if [[ "$installinchroot" == "1" ]]
    then
	sed -i 's/chroot=0/'"chroot=$installinchroot"'/' root/tmp/install.sh
    fi
    cpP "$workdir/inittab" etc/
    chmod +x "$workdir/"*.start
    mkdir etc/local.d
    cpP "$workdir/staticip.start" etc/local.d/
    cpP "$workdir/hostname.start" etc/local.d/
    cpP "$workdir/setterm.start" etc/local.d/
    cpP "$workdir/plx-overlay-$plxolver.tar.gz" root/tmp/
    cpP "$workdir/plx-pgp.asc" root/tmp/

    cpP "$workdir/toolchain/portage" etc/
    echo 'PYTHON_TARGETS="python3_6"' >> etc/portage/make.conf
    echo "sys-libs/uclibc-ng-1.0.30" >> etc/portage/profile/package.provided
    echo "sys-apps/baselayout-2.4.1" >> etc/portage/profile/package.provided

    if [[ "$installinchroot" == "1" ]]
    then
	sed -i 's/-march=native //' etc/portage/make.conf
	sed -i 's/ target-cpu=native//' etc/portage/make.conf
    fi

    cpP "$workdir"/toolchain/build/passwd etc/
    cpP "$workdir"/toolchain/build/group etc/
    
    pw="$diskfile"
    echo "root:$pw" > root/tmp/pw

    # sed -i 's/^#PasswordAuthentication .*$/PasswordAuthentication no/' "$mountpoint/etc/ssh/sshd_config" # add this later
    
    if [ -e "$workdir/id_rsa.pub" ]
    then
	mkdir -p root/.ssh
	cat "$workdir/id_rsa.pub" >> root/.ssh/authorized_keys
    fi
    mkdir -p usr/local/bin
    cp "$workdir/swclock-helper.sh" usr/local/bin/
    chmod +x usr/local/bin/swclock-helper.sh
    if [[ "$libc" == "glibc" ]]
    then
	echo "UTC" > etc/timezone
    fi
    if [ ! -e "$workdir/unsaferoot.tar.xz" ]
    then
	echo "You must build_unsafe_packages before finalizing"
	exit 1
    fi
    cp "$workdir/unsaferoot.tar.xz" root/tmp/
    mkdir root/tmp/unsafe
    cp "$workdir/unsafe/firefox" root/tmp/unsafe/
    mkdir -p var/lib/portage
    cp "$workdir/world" var/lib/portage/
    date +"%F %T" > root/tmp/lastdate
    umount -l "$mountpoint"
    sleep 2
    cd "$workdir"
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
	unprepare_for_chroot "$mountpoint"
    fi
    if df | grep "$mountpoint"
    then
	umount "$mountpoint"
    fi
    sleep 3
    count=0
    set +e
    while ! mkfs.ext4 -F "$loopdev"p2
    do
	fuser -km "$loopdev"p2
	set -e
	sleep 3
	let count=count+1
	if [ "$count" -gt 9 ]
	then
	    echo "Cannot clear filesystem"
	    exit 1
	fi
	set +e
    done
    set -e
    echo "Cleared root filesystem"
}

prepare_for_chroot() {
    echo "Preparing for chroot $1 ..."
    mountpoint=""
    if [ -z "$1" ]
    then
	diskfile="`cat diskfile | tr -d '\n'`"
	loopdev="`cat loopdev | tr -d '\n'`"
	mountpoint="/mnt/$diskfile"p2
	mkdir -p "$mountpoint"
	if ! df | grep "$mountpoint"
	then
	    mount "$loopdev"p2 "$mountpoint"
	fi
    else
	mountpoint="$1"
    fi
    if ! df | grep "$mountpoint/proc"
    then
	mount --types proc /proc "$mountpoint/proc"
    fi
    if ! df | grep "$mountpoint/sys"
    then
	mount --rbind /sys "$mountpoint/sys"
	mount --make-rslave "$mountpoint/sys"
    fi
    if ! df | grep "$mountpoint/dev"
    then
	mount --rbind /dev "$mountpoint/dev"
	mount --make-rslave "$mountpoint/dev"
    fi
    if ! df | grep "$mountpoint/run"
    then
	if [ -e "$mountpoint/run" ]
	then
	    mount --bind /run "$mountpoint/run"
	    mount --make-slave "$mountpoint/run"
	fi
    fi
    cp -L /etc/resolv.conf "$mountpoint/etc/"
    echo "Prepared for chroot"
}

unprepare_for_chroot() {
    echo "Undoing chroot preparations $1 ..."
    mountpoint=""
    if [ -z "$1" ]
    then
	diskfile="`cat diskfile | tr -d '\n'`"
	loopdev="`cat loopdev | tr -d '\n'`"
	mountpoint="/mnt/$diskfile"p2
    else
	mountpoint="$1"
    fi
    if mount | grep "$mountpoint/dev"
    then
	set +e
	umount -l "$mountpoint"/dev{/shm,/pts,}
	set -e
    fi
    if mount | grep "$mountpoint/run"
    then
	umount -Rl "$mountpoint/run"
    fi
    if mount | grep "$mountpoint/sys"
    then
	umount -Rl "$mountpoint/sys"
    fi
    if mount | grep "$mountpoint/proc"
    then
	umount -Rl "$mountpoint/proc"
    fi
    sleep 1
    if mount | grep "$mountpoint"
    then
	umount -Rl "$mountpoint"
    fi
    sleep 1 # todo: fix this hack
    if ! df -a | grep "/dev/pts"
    then
	mount -t devpts none /dev/pts
    fi
    if ! df -a | grep "/dev/shm"
    then
	mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
    fi
    if df -a | grep "$mountpoint"
    then
	echo "Please wait until $mountpoint mountings are fully unmounted"
	exit 1
    else
	echo "Chroot preparations undone"
    fi
}

finalize_disk_image() {
    echo "Finalizing disk image ..."
    diskfile="`cat diskfile | tr -d '\n'`"
    loopdev="`cat loopdev | tr -d '\n'`"
    mountpoint="/mnt/$diskfile"p2
    unprepare_for_chroot "$mountpoint"
    losetup -d "$loopdev"
    asuser xz -vk5T0 "$diskfile"
    echo "Finalized disk image"
}

clean() {
    echo "Cleaning PLX build files ..."
    #rm -rf "unsaferoot.tar.xz" # tmp don't delete
    rm -rf "modules"
    asuser rm -rf "initramfs.cpio.gz"
    asuser rm -rf "linux-stable_$kernelver"
    asuser rm -rf "raspi-firmware-$firmwarever"
    if [ -e diskfile ]
    then
	diskfile="`cat diskfile | tr -d '\n'`"
	mountpoint="/mnt/$diskfile"p2
	unprepare_for_chroot "$mountpoint"
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
	asuser rm -f "$diskfile"
	if [ -e "$diskfile.xz" ]
	then
	    asuser rm "$diskfile.xz"
	fi
	asuser rm diskfile
    fi
    if [ -e portage.auto ]
    then
	asuser rm -r portage.auto
    fi
    if [ -e distfiles ]
    then
	asuser rm -r distfiles
    fi
    if [ -e muslroot ]
    then
	unprepare_for_chroot muslroot
	rm -r muslroot
    fi
    if [ -e unsaferoot ]
    then
	unprepare_for_chroot unsaferoot
	rm -r unsaferoot
    fi
    if [ -e mainroot ]
    then
	unprepare_for_chroot mainroot
	rm -r mainroot
    fi
    echo "Cleaned PLX build files"
}

build_initramfs() { # inside a uclibc chroot

    echo "Building initramfs ..."

    if [ ! -e toolchain/build ]
    then
	build_toolchain
    fi
    
    if [ -e initramfs.cpio.gz ]
    then
	asuser rm -r initramfs.cpio.gz
    fi

    if [ -e uclibcroot ]
    then
	unprepare_for_chroot uclibcroot
	rm -r uclibcroot
    fi
    
    mkdir uclibcroot
    tar xpf "stage3-armv7a_hardfp-uclibc-vanilla-$uclibcver.tar.bz2" --xattrs-include='*.*' --numeric-owner -C "uclibcroot"
    mv uclibcroot/etc/portage uclibcroot/etc/portage.bak
    cpP toolchain/portage uclibcroot/etc/
    mkdir uclibcroot/root/tmp
    cp "gentoo-$tcsnapshotver.tar.xz" uclibcroot/root/tmp/
    cp "bootstrap/distfiles/busybox-1.29.0.tar.bz2" uclibcroot/root/tmp/
    cp build-initramfs.sh uclibcroot/root/tmp/
    chmod +x uclibcroot/root/tmp/build-initramfs.sh
    cp init.sh uclibcroot/root/tmp/
    cp build-initramfs-worker.sh uclibcroot/root/tmp
    sed -i 's/$njobs/'"$njobs"'/' uclibcroot/root/tmp/build-initramfs.sh
    sed -i 's/$tcsnapshotver/'"$tcsnapshotver"'/' uclibcroot/root/tmp/build-initramfs.sh
    sed -i 's/$njobs/'"$njobs"'/' uclibcroot/root/tmp/build-initramfs-worker.sh
    prepare_for_chroot uclibcroot
    chroot uclibcroot /root/tmp/build-initramfs.sh
    unprepare_for_chroot uclibcroot

    cd uclibcroot/home/worker/initramfs
    asuser find . -print0 | asuser cpio --null -ov --format=newc | asuser gzip -9 | asuser tee "$workdir/initramfs.cpio.gz" >> /dev/null
    cd "$workdir"

    echo "Built initramfs"
}

build_toolchain() { # inside a uclibc chroot

    echo "Building toolchain ..."

    if [ -e uclibcroot ]
    then
	unprepare_for_chroot uclibcroot
	rm -r uclibcroot
    fi

    mkdir uclibcroot
    tar xpf "stage3-armv7a_hardfp-uclibc-vanilla-$uclibcver.tar.bz2" --xattrs-include='*.*' --numeric-owner -C "uclibcroot"
    mkdir uclibcroot/root/tmp
    cp build-toolchain.sh uclibcroot/root/tmp/
    cp build-toolchain-binutils.sh uclibcroot/root/tmp/
    cp build-toolchain-gcc.sh uclibcroot/root/tmp/
    cp toolchain/toolchain.eclass.patch uclibcroot/root/tmp/
    chmod +x uclibcroot/root/tmp/build-toolchain.sh
    cp -r toolchain/distfiles uclibcroot/root/tmp/
    rm -r uclibcroot/root/tmp/distfiles/*.SHA512
    mv uclibcroot/etc/portage uclibcroot/etc/portage.bak
    cpP toolchain/portage uclibcroot/etc/
    cp "gentoo-$tcsnapshotver.tar.xz" uclibcroot/root/tmp/
    sed -i 's/$tcsnapshotver/'"$tcsnapshotver"'/' uclibcroot/root/tmp/build-toolchain.sh
    sed -i 's/$njobs/'"$njobs"'/' uclibcroot/root/tmp/build-toolchain.sh
    sed -i 's/$njobs/'"$njobs"'/' uclibcroot/root/tmp/build-toolchain-binutils.sh
    sed -i 's/$njobs/'"$njobs"'/' uclibcroot/root/tmp/build-toolchain-gcc.sh
    prepare_for_chroot uclibcroot
    chroot uclibcroot /root/tmp/build-toolchain.sh
    unprepare_for_chroot uclibcroot

    # todo: parametrize versions of gcc and binutils
    if [ -e toolchain/build ]
    then
	asuser rm -rf toolchain/build
    fi
    asuser mkdir toolchain/build
    asuser cpP uclibcroot/home/worker/binutils/binutils-2.25.1/build toolchain/build/binutils
    asuser cpP uclibcroot/opt/gcc toolchain/build/
    asuser mkdir toolchain/build/include
    #asuser cp -rP --preserve=mode,timestamps toolchain/build/gcc/lib/armv7a-unknown-linux-uclibceabihf/4.9.4/include/* toolchain/build/include/
    while read -r file
    do
	filetail="`echo "$file" | sed 's|^/usr/include/||'`"
	dirfiletail="`dirname "$filetail"`"
	asuser mkdir -p toolchain/build/include/"$dirfiletail"
	asuser cpP "uclibcroot$file" "toolchain/build/include/$dirfiletail"/
    done < <(cat uclibcroot/root/tmp/include-list.txt) # assume no dirs in the list
    asuser mkdir toolchain/build/lib
    while read -r file
    do
	filetail="`echo "$file" | sed 's|^/usr/lib/||' | sed 's|^/lib/||'`"
	dirfiletail="`dirname "$filetail"`"
	asuser mkdir -p toolchain/build/lib/"$dirfiletail"
	asuser cpP "uclibcroot$file" "toolchain/build/lib/$dirfiletail"/
    done < <(cat uclibcroot/root/tmp/lib-list.txt) # assume no dirs in the list
    while read -r file
    do
	filetail="`echo "$file" | sed 's|^/usr/bin/||' | sed 's|^/bin/||'`"
	dirfiletail="`dirname "$filetail"`"
	asuser mkdir -p toolchain/build/bin/"$dirfiletail"
	asuser cpP "uclibcroot$file" "toolchain/build/bin/$dirfiletail"/
    done < <(cat uclibcroot/root/tmp/bin-list.txt) # assume no dirs in the list
    while read -r file
    do
	filetail="`echo "$file" | sed 's|^/sbin/||'`"
	dirfiletail="`dirname "$filetail"`"
	asuser mkdir -p toolchain/build/sbin/"$dirfiletail"
	asuser cpP "uclibcroot$file" "toolchain/build/sbin/$dirfiletail"/
    done < <(cat uclibcroot/root/tmp/sbin-list.txt) # assume no dirs in the list
    cd toolchain/build/lib
    rm libthread_db.so # todo make this general
    ln -s libthread_db.so.1 libthread_db.so
    cd "$workdir"
    grep -e '^root:' -e '^portage:' uclibcroot/etc/passwd | asuser tee toolchain/build/passwd
    grep -e '^root:' -e '^portage:' uclibcroot/etc/group | asuser tee toolchain/build/group
    asuser cpP uclibcroot/usr/portage/distfiles/* bootstrap/distfiles/
    asuser mkdir toolchain/build/bld
    cd toolchain/build/bld
    asuser tar -xf "$workdir/bootstrap/distfiles/make-4.2.1.tar.bz2"
    asuser tar -xf "$workdir/bootstrap/distfiles/shadow-4.6.tar.gz"
    asuser tar -xf "$workdir/bootstrap/distfiles/busybox-1.29.0.tar.bz2"
    cd "$workdir"

    echo "Built toolchain"
}

install_initramfs() {

    echo "Installing initramfs ..."
    
    build_initramfs

    if [ -e uclibcroot ]
    then
	rm -r uclibcroot
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

build_unsafe_packages() { # Packages that depend on glibc or Rust. Will run with Bubblewrap.
    echo "Building unsafe packages ..."
    if [ -e unsaferoot ]
    then
	unprepare_for_chroot unsaferoot
	rm -r unsaferoot
    fi
    mountpoint="unsaferoot"
    mkdir "$mountpoint"
    tar xpf "stage3-arm64-openrc-$stage3ver.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$mountpoint"/
    mkdir "$mountpoint/root/tmp"
    cp "gentoo-$snapshotver.tar.xz" "$mountpoint/root/tmp/"
    cp hostname "$mountpoint/etc/"
    cp "plx-overlay-$plxolver.tar.gz" "$mountpoint/root/tmp/"
    #cp plx-pgp.asc "$mountpoint/root/tmp/"
    if [ -e unsafe/portage/env ]
    then
        cp -r unsafe/portage/env "$mountpoint/etc/portage/"
    fi
    cp unsafe/portage/make.conf "$mountpoint/etc/portage/"
    sed -i 's/-march=native //' "$mountpoint/etc/portage/make.conf"
    sed -i 's/^RUSTFLAGS=.*$//' "$mountpoint/etc/portage/make.conf"
    if [ -e unsafe/portage/package.accept_keywords ]
    then
        cp unsafe/portage/package.accept_keywords/* "$mountpoint/etc/portage/package.accept_keywords/"
    fi
    if [ -e unsafe/portage/package.env ]
    then
        cp -rT unsafe/portage/package.env "$mountpoint/etc/portage/package.env"
    fi
    if [ -e unsafe/portage/package.license ]
    then
        cp -rT unsafe/portage/package.license "$mountpoint/etc/portage/package.license"
    fi
    if [ -e unsafe/portage/package.mask ]
    then
        cp unsafe/portage/package.mask/* "$mountpoint/etc/portage/package.mask/"
    fi
    if [ -e unsafe/portage/package.use ]
    then
        cp unsafe/portage/package.use/* "$mountpoint/etc/portage/package.use/"
    fi
    if [ -e unsafe/portage/repos.conf ]
    then
        cp -rT unsafe/portage/repos.conf "$mountpoint/etc/portage/repos.conf"
    fi
    echo "UTC" > "$mountpoint/etc/timezone"
    cp unsafe/world "$mountpoint/var/lib/portage/"
    cp unsafe/install.sh "$mountpoint/root/tmp/"
    chmod +x "$mountpoint/root/tmp/install.sh"
    sed -i 's/$snapshotver/'"$snapshotver"'/' "$mountpoint/root/tmp/install.sh"
    sed -i 's/$plxolver/'"$plxolver"'/' "$mountpoint/root/tmp/install.sh"
    prepare_for_chroot "$mountpoint"
    chroot "$mountpoint" "/root/tmp/install.sh"
    unprepare_for_chroot "$mountpoint"
    tar -cJf unsaferoot.tar.xz --xattrs-include='*.*' --numeric-owner unsaferoot
    rm -r unsaferoot
    echo "Built unsafe packages"
}

main() {
    download_files
 #   prepare_disk_image
 #   install_firmware
 #   install_kernel
#    install_initramfs
 #   build_unsafe_packages
#    install_stage3
#    get_distfiles_and_autounmasking
    clear_root_fs
    finalize_root_fs
    if [[ "$installinchroot" == 1 ]]
    then
	prepare_for_chroot
	diskfile="`cat diskfile | tr -d '\n'`"
	mountpoint="/mnt/$diskfile"p2
	echo "Installing in chroot ..."
	chroot "$mountpoint" /root/tmp/install.sh
	echo "Installed in chroot"
    fi
    finalize_disk_image
}

bootstrap_amd64() {
    download_bootstrap_amd64_files
    prepare_disk_image_amd64
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

#unprepare_for_chroot
#unprepare_for_chroot /mnt/plxIBcVh0RH.imgp2/usr/aarch64-unknown-linux-musl
#unprepare_for_chroot unsaferoot
#build_toolchain
#build_initramfs
#main
#finalize_disk_image
#download_files
#build_unsafe_packages
bootstrap_amd64

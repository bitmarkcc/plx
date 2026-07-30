#!/bin/bash
# Use the bash shell for these steps.
#
# Driver for the amd64 CROSS stage of the PLX bootstrap. Run INSIDE the /mnt/gentoo chroot
# (enter it with chroot-enter.sh FIRST) -- NOT in the plain i686 guest: 09 needs the crossdev
# ${target}-emerge, which only exists inside the finished i686 @system. Sources vars-x86.sh for
# ${target}/${j}, then runs 09-12 in order: build the x86_64-unknown-linux-musl cross toolchain +
# merged-usr amd64 sysroot on sda2, cross-emerge the amd64 base, cross-build the kernel into
# sda2:/boot, and make sda2 self-booting (sysvinit+openrc + GRUB).
#
# Run:  bash chroot-enter.sh    # enter the /mnt/gentoo chroot, then INSIDE it:
#       bash x86-gentoo.sh      # 09 -> 12
#       exit                    # leave the chroot, then from the i686 guest:
#       bash 13-reboot.sh       # SysRq reboot -> SeaBIOS -> GRUB -> amd64 (VGA)

set -e

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

set -a
. "$thisdir"/vars-x86.sh
set +a

export -f asuser

# plx-ramdisk (plx_mount_portage_tmpfs): source + export so the numbered step subprocesses inherit it
# (like asuser). 09 calls it to put its two build dirs on tmpfs. Running 09/10/11 by hand withOUT this
# driver? source plx-ramdisk.sh first, else 09's guarded calls skip and its builds go to disk.
. "$thisdir"/plx-ramdisk.sh
export -f plx_mount_portage_tmpfs

# Fixed top-line status bar (see plx-status.sh) for the cross stage; released on exit even on abort.
. "$thisdir"/plx-status.sh
plx_status_init
trap plx_status_end EXIT

# 09-12 run INSIDE the /mnt/gentoo chroot -- enter it (chroot-enter.sh) BEFORE this driver.
plx_stage "09/12 crossdev -- x86_64-musl cross toolchain + merged-usr sysroot"
bash x86-gentoo/09-crossdev.sh        # crossdev x86_64-...-musl toolchain + merged-usr sysroot (--stable)
plx_stage "10/12 amd64-portage -- cross-emerge the amd64 base into the sysroot"
bash x86-gentoo/10-amd64-portage.sh   # cross-emerge the amd64 base into the sysroot (stable keywords)
plx_stage "11/12 amd64-kernel -- cross-build gentoo-kernel into sda2:/boot"
bash x86-gentoo/11-amd64-kernel.sh    # cross-build gentoo-kernel into sda2:/boot (no initramfs/kexec)
plx_stage "12/12 amd64-init -- sysvinit+openrc, fstab, root pw, GRUB"
bash x86-gentoo/12-amd64-init.sh      # sysvinit+openrc, fstab, root pw, first-boot @system, GRUB

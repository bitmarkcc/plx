#!/bin/bash
# Use the bash shell for these steps.
#
# Driver for the x86 (i686-musl) Gentoo bootstrap, run INSIDE the live-bootstrap
# guest as root. Analogous to bootstrap/bash-arm.sh: sources vars-x86.sh with
# `set -a` so the numbered step scripts inherit the vars, exports asuser, then
# runs the steps in order.
#
# arm's 01-16 (hand-built toolchain from a minimal uclibc seed) are skipped:
# live-bootstrap already provides gcc-15, binutils-2.41, python-3.11, bash, make,
# perl, ... So we start at portage bring-up.
#
# Run from this directory:  cd bootstrap-amd64 && bash x86.sh

set -e

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

set -a
. "$thisdir"/vars-x86.sh
set +a

export -f asuser

# Fixed top-line status bar (see plx-status.sh): shows which numbered step is running and clears
# the kernel boot penguins on init. `trap ... EXIT` releases the reserved line even if a step aborts.
. "$thisdir"/plx-status.sh
plx_status_init
trap plx_status_end EXIT

# plx_mount_portage_tmpfs: compile @system in RAM when RAM-nproc*2 >= 32G (see plx-ramdisk.sh).
. "$thisdir"/plx-ramdisk.sh

plx_stage "01/12 dev -- /dev/{fd,stdin,stdout,stderr} nodes"
bash x86/01-dev.sh               # create /dev/{fd,stdin,stdout,stderr} (LB's /dev lacks them)
plx_stage "02/12 gcc -- fix live-bootstrap multiarch tuple (musl)"
bash x86/02-gcc.sh               # fix live-bootstrap gcc's wrong multiarch tuple (musl)
plx_stage "03/12 findutils -- modern find for portage (>= 4.9.0)"
bash x86/03-find.sh              # build modern findutils (portage needs >= 4.9.0)
plx_stage "04/12 linux-headers -- complete the uapi headers"
bash x86/04-linux-headers.sh     # complete the kernel headers (LB dropped ~7 uapi ones)
plx_stage "05/12 scanelf -- SONAME reader for portage"
bash x86/05-scanelf.sh           # build scanelf (portage install phases read SONAMEs)
plx_stage "06/12 getent -- musl getent for egetent"
bash x86/06-getent.sh            # build getent (egetent needs it; musl lacks glibc getent)
plx_stage "07/12 portage -- bring-up"
bash x86/07-portage.sh           # portage bring-up
# 07 set PORTAGE_TMPDIR=/var/tmp, so portage builds in /var/tmp/portage -- put that in RAM if spare.
plx_mount_portage_tmpfs /var/tmp/portage
plx_stage "08/12 @system -- emerge native i686-musl base (long)"
bash x86/08-system.sh            # emerge @system  (native i686-musl base)
# The amd64 CROSS stage (09-12) lives in x86-gentoo/ and runs INSIDE the /mnt/gentoo chroot,
# driven separately by x86-gentoo.sh (see its header):
#     bash chroot-enter.sh -> bash x86-gentoo.sh -> exit -> bash 13-reboot.sh
# 13-reboot.sh (from this i686 guest) reboots the disk into GRUB -> amd64 (VGA).

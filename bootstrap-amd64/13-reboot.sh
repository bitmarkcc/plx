# 13-reboot.sh -- reboot the QEMU guest so it re-boots from the DISK (SeaBIOS re-reads sector 0).
#
# Run from the live-bootstrap i686 shell (exit the /mnt/gentoo chroot first) AFTER 12-amd64-init.sh
# installed GRUB. The QEMU is disk-booted (no -kernel), and sector 0 is now GRUB's boot.img, so
# this reset lands in GRUB -> the amd64 kernel (VGA) -> openrc -> first-boot @system -> login,
# NOT live-bootstrap. Any guest reset sends SeaBIOS back to sector 0. live-bootstrap has no
# `reboot` command, so we use the kernel's SysRq 'b' (immediate reboot) directly.
#
# NB: GRUB overwrote builder-hex0 at sector 0, so this REPLACES the live-bootstrap boot path. Back
# up the disk on the HOST first if you want a fallback:
#   cp --sparse=always ~/git/live-bootstrap/target/init.img ~/git/live-bootstrap/target/init.img.bak

sync                                    # flush pending writes (esp. sda2) before the hard reset
echo 1 > /proc/sys/kernel/sysrq         # enable SysRq
echo b > /proc/sysrq-trigger            # SysRq 'b': immediate reboot -> SeaBIOS -> GRUB -> amd64

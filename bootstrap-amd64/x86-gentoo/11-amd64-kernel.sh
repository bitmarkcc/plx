set -e

# Cross-build a modern amd64 kernel (sys-kernel/gentoo-kernel) and leave its vmlinuz in the amd64
# root's /boot for GRUB to load on a real DISK boot. NO initramfs and NO kexec: the gentoo-kernel
# dist config builds the storage drivers IN (=y) -- SATA_AHCI, ATA_PIIX, BLK_DEV_SD, VIRTIO_BLK,
# EXT4_FS -- so the kernel mounts sda2 directly (root=/dev/sda2 init=/sbin/init); the initramfs +
# switch_root dance is unnecessary. For booting the amd64 root from a USB stick (KGPE-D16 SB700 =
# USB 2.0), a 02-plx-usb.config fragment additionally forces USB HCD + usb-storage IN (=y) -- see
# [2/3] -- paired with `rootwait` in 12's grub.cfg. 12-amd64-init.sh installs GRUB for this kernel.
#
# WHY DISK-BOOT, NOT KEXEC: kexec is an in-guest handoff that never re-initializes the video
# hardware, so the amd64 kernel's vgacon couldn't drive VGA and we were stuck on the serial
# console (a poor terminal in QEMU's graphical serial view). A real boot through firmware
# (SeaBIOS in QEMU / coreboot on the KGPE-D16) re-inits VGA, so console=tty0 works and QEMU's
# VGA text console gives proper line editing -- matching how the real board boots.
#
# CONTEXT: runs INSIDE the /mnt/gentoo chroot, AFTER 09-crossdev.sh (needs the cross toolchain +
# the populated sysroot at /usr/${target}). Not driven by x86-bash.sh.

target="${target:-x86_64-unknown-linux-musl}"
j="${j:-$(nproc)}"
sysroot="/usr/${target}"

command -v "${target}-emerge" >/dev/null 2>&1 || { echo "no ${target}-emerge -- run 09-crossdev.sh first"; exit 1; }

echo "== [1/3] target package.use + env to tame the cross kernel build =="
# Written into the TARGET config root -- ${target}-emerge reads $sysroot/etc/portage.
# -initramfs: don't have gentoo-kernel run dracut at cross time (can't introspect a cross ROOT
#   reliably) -- and we don't need one anyway (disk boot, storage drivers built in). installkernel
#   backends off: its pkg_postinst should just drop vmlinuz in $sysroot/boot, not run
#   dracut/grub/bootctl. Unknown USE here is harmless -- portage ignores flags not in a pkg's IUSE.
mkdir -p "$sysroot/etc/portage/package.use"
cat > "$sysroot/etc/portage/package.use/kernel" <<'EOF'
sys-kernel/gentoo-kernel -initramfs
sys-kernel/installkernel -dracut -grub -systemd -uki -ukify -efistub
EOF
# objtool's disassembler (tools/objtool/disas.o) FAILS to build on a 32-bit HOST: disas.c
# prints a bfd_vma with %lx, correct only on an LP64 host where bfd_vma is 'unsigned long'.
# On this ILP32 host bfd_vma is 'unsigned int' -> the format warning fires, and objtool's
# Makefile line 50 (`WARNINGS := -Werror -Wall -Wextra -Wmissing-prototypes`) makes ALL
# warnings fatal. The -Werror is bare/unconditional -- no env var (WERROR=0, EXTRA_CFLAGS)
# reliably disables it -- so a post_src_prepare hook strips it from ONLY that one host-tool
# Makefile (NOT the kernel's own -Werror). The disassembler is an optional debug aid the
# kernel doesn't need, and on ILP32 the two types are the same width, so this is safe.
# Bug only surfaces when cross-building a 64-bit kernel FROM a 32-bit machine (us).
#
# The hook MUST live in /etc/portage/bashrc, NOT /etc/portage/env: env files are parsed as
# make.conf-style KEY=value (a shell function there errors "Invalid token '('"). bashrc is
# sourced as bash and portage calls its post_<phase> functions. Guard by ${CATEGORY}/${PN}
# so only gentoo-kernel is touched. Idempotent via a marker-string grep.
brc="$sysroot/etc/portage/bashrc"
if ! grep -q 'PLX objtool -Werror strip' "$brc" 2>/dev/null; then
    cat >> "$brc" <<'EOF'
# PLX objtool -Werror strip: objtool's disas.c won't compile -Werror-clean on a 32-bit host
post_src_prepare() {
    if [[ ${CATEGORY}/${PN} == sys-kernel/gentoo-kernel ]]; then
        [[ -f ${S}/tools/objtool/Makefile ]] && sed -i 's/-Werror//g' "${S}/tools/objtool/Makefile"
    fi
}
EOF
fi

echo "== [2/3] slim the dist config + cross-emerge sys-kernel/gentoo-kernel =="
# kernel-build.eclass merges user fragments from ${ESYSROOT}/etc/kernel/config.d/*.config --
# for a CROSS build that's the SYSROOT path ($sysroot/etc/kernel/config.d/), NOT the host
# /etc (which the eclass ignores here). Two fragments:
#   - CONFIG_DEBUG_INFO_NONE=y: the dist config's full debug info blows the build tree up to
#     15-20GB (vmlinux + .ko symbols) -- turning it off is the biggest size cut (3-5x), which
#     matters on the 29GB disk. Also frees us from needing pahole to succeed.
#   - CONFIG_DEBUG_INFO_BTF off: its pahole step can otherwise choke cross-building.
mkdir -p "$sysroot/etc/kernel/config.d"
cat > "$sysroot/etc/kernel/config.d/01-plx-slim.config" <<'EOF'
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_DEBUG_INFO_BTF is not set
# CONFIG_X86_DECODER_SELFTEST is not set
EOF
# X86_DECODER_SELFTEST builds host tools arch/x86/tools/insn_sanity + insn_decoder_test with
# HOSTCC=i686-...-gcc; on gcc-15 the kernel's swab.h trips -Wimplicit-function-declaration,
# now a hard ERROR (__fswahw32). It's an optional self-test the image doesn't need -- off it
# goes. Same class as the objtool -Werror snag: an x86 host tool unhappy on a 32-bit musl
# gcc-15 build host. (If MORE host tools hit swab.h/implicit-decl, the broad lever is
# HOSTCFLAGS+=-Wno-error=implicit-function-declaration, but prefer disabling optional bits.)
#
# USB root support: the dist config ships the USB host controllers + usb-storage as MODULES (=m),
# which a NO-initramfs kernel can't load before it mounts root -- so booting the amd64 root from a
# USB stick would panic ("unable to mount root"). Force them IN (=y). KGPE-D16's SB700 southbridge
# is USB 2.0 only -- EHCI (hi-speed) + OHCI (full/low-speed) cover every ONBOARD port. xHCI is added
# as cheap insurance in case root ends up on a PCIe USB 3.0 add-in card (the only route to USB3 on
# this board); harmless when no xHCI hardware is present. usb-storage rides the SCSI sd layer, so
# pull that in too. All unused/harmless on a SATA boot. Pairs with `rootwait` in 12's grub.cfg (USB
# enumerates ASYNCHRONOUSLY -- the root block device isn't ready the instant the kernel checks).
cat > "$sysroot/etc/kernel/config.d/02-plx-usb.config" <<'EOF'
CONFIG_USB=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PCI=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
EOF
"${target}-emerge" -quDN sys-kernel/gentoo-kernel

echo "== [3/3] confirm the built kernel in $sysroot/boot =="
kimg="$(ls "$sysroot"/boot/vmlinuz-* "$sysroot"/boot/kernel-* "$sysroot"/boot/bzImage-* 2>/dev/null | sort -V | tail -1)"
[ -n "$kimg" ] || { echo "no kernel image in $sysroot/boot"; exit 1; }
kver="$(basename "$kimg" | sed -E 's/^(vmlinuz|kernel|bzImage)-//')"
echo "  kernel image: $kimg  (version $kver)"
echo "  modules:      $(ls -d "$sysroot/lib/modules/$kver" 2>/dev/null || echo '(none installed)')"
echo
echo ">> amd64 kernel $kver built + installed in $sysroot/boot."
echo ">> Next: 12-amd64-init.sh makes sda2 self-booting (sysvinit+openrc, fstab, root pw) AND"
echo ">>       installs GRUB pointing at this kernel (root=/dev/sda2 init=/sbin/init console=tty0),"
echo ">>       then de-cross-ifies the sysroot make.conf. Boot QEMU from the DISK (VGA), no kexec."

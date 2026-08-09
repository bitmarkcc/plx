set -e

# 12-amd64-init.sh -- make sda2 a SELF-BOOTING amd64 system, run FROM THE i686 CHROOT (cross), so
# no amd64 boot is needed to configure it. Puts sysvinit+openrc in the sysroot, writes fstab + a
# preseeded root password + a first-boot @system script, and installs GRUB on the disk pointing at
# the kernel (root=/dev/sda2 init=/sbin/init console=tty0). Then de-cross-ifies the sysroot
# make.conf. After it: boot QEMU from the DISK (boot-amd64-disk.sh, VGA) -> GRUB -> kernel ->
# openrc -> the first-boot `emerge -uDNq @system` (progress on the VGA console) -> login (root/plx).
#
# CONTEXT: runs INSIDE the /mnt/gentoo chroot, AFTER 11-amd64-kernel.sh (needs the kernel in
# $sysroot/boot). Not driven by x86-bash.sh. VGA (not serial): a real firmware boot re-inits the
# display, so console=tty0 works and QEMU's VGA text console has proper line editing (unlike the
# kexec/serial path). The default sysvinit inittab's tty1 getty IS the VGA login -- no getty edit.

target="${target:-x86_64-unknown-linux-musl}"
sysroot="/usr/${target}"
disk="${disk:-/dev/sda}"                 # whole disk to receive the i386-pc (BIOS) bootloader
# Preseeded root password hash ($6$ SHA-512, what musl's crypt wants). Default = 'plx' -- CHANGE
# IT. Regenerate with:  openssl passwd -6 <newpw>
ROOTHASH="${ROOTHASH:-\$6\$ioNxzjr8V5EDsu1V\$XV8qYqijw85Apr3dc3SNCzbzFXOny2IKlhf2L8hxADXKDKv6UiAgiQf1lD4y1Zr/khcB4jJREzKozSIrjkAMQ.}"

command -v "${target}-emerge" >/dev/null 2>&1 || { echo "no ${target}-emerge -- run 09-crossdev.sh first"; exit 1; }
kimg="$(ls "$sysroot"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)"
[ -n "$kimg" ] || { echo "no kernel in $sysroot/boot -- run 11-amd64-kernel.sh first"; exit 1; }
kname="$(basename "$kimg")"

echo "== [1/6] init (sysvinit + openrc) into the sysroot; GRUB for both target + host =="
# sysvinit (/sbin/init) + openrc go INTO the amd64 sysroot -- the booted system runs them (both are
# usually already in @system; --noreplace just ensures). GRUB is needed TWICE: an amd64 one in the
# sysroot (so the running system can re-run grub-install after kernel updates) AND an i686 one in
# THIS chroot to actually WRITE the bootloader now -- grub-install runs host binaries, and i386-pc
# boot code is 32-bit regardless of OS arch, so an i686 grub installs a loader that boots the
# 64-bit kernel. GRUB_PLATFORMS=pc => BIOS only (no EFI bloat), for both.
for m in /etc/portage/make.conf "$sysroot/etc/portage/make.conf"; do
    mkdir -p "$(dirname "$m")"
    grep -q '^GRUB_PLATFORMS=' "$m" 2>/dev/null || echo 'GRUB_PLATFORMS="pc"' >> "$m"
done
"${target}-emerge" --noreplace -q sys-apps/sysvinit sys-apps/openrc sys-boot/grub
emerge --oneshot --noreplace -q sys-boot/grub          # i686 grub in the chroot, for grub-install
[ -x "$sysroot/sbin/init" ] || echo ">> WARN: $sysroot/sbin/init missing -- sysvinit not installed"

echo "== [2/6] /etc/fstab =="
# sda2 is the root (pass 0 -- GRUB/kernel already mount it). sda1 = i686 bootstrap disk; openrc's
# localmount fscks + mounts it, then bind its arch-independent ebuild repo + /root/tmp into place.
cat > "$sysroot/etc/fstab" <<'EOF'
/dev/sda2                /              ext4   defaults,noatime   0 0
/dev/sda1                /mnt/sda1      ext4   defaults,noatime   0 2
/mnt/sda1/var/db/repos   /var/db/repos  none   bind               0 0
/mnt/sda1/root/tmp       /root/tmp      none   bind               0 0
EOF
mkdir -p "$sysroot/mnt/sda1" "$sysroot/var/db/repos"
echo "  wrote $sysroot/etc/fstab"

echo "== [3/6] preseed root password in /etc/shadow =="
# Write the hash directly (no chpasswd -- we're cross, not on the running system).
if [ -f "$sysroot/etc/shadow" ] && grep -q '^root:' "$sysroot/etc/shadow"; then
    sed -i "s|^root:[^:]*:|root:${ROOTHASH}:|" "$sysroot/etc/shadow"
else
    printf 'root:%s:19000:0:99999:7:::\n' "$ROOTHASH" >> "$sysroot/etc/shadow"
    chmod 600 "$sysroot/etc/shadow"
fi
echo "  root password preseeded (default 'plx' -- CHANGE IT)"

echo "== [4/6] first-boot: emerge -uDNq @system via /etc/local.d =="
# openrc runs /etc/local.d/*.start in the `local` service (default runlevel) -- a `wait` inittab
# entry that completes BEFORE the gettys spawn -- so the emerge progress shows on the VGA console
# and login: only appears once @system is done. -q = quiet (still lists what it's emerging). Runs
# ONCE (flag guard); on failure it retries next boot. localmount (boot runlevel) has already bound
# sda1's repo by the time this runs, and the baked distfiles on sda2 make it offline-capable.
mkdir -p "$sysroot/etc/local.d"
cat > "$sysroot/etc/local.d/00-plx-firstboot.start" <<'LOCALEOF'
#!/bin/sh
flag=/var/lib/plx/firstboot-done
[ -e "$flag" ] && exit 0
# openrc's `local` service pipes our stdout (into rc.log), so emerge's output would be block-
# buffered and HIDDEN -- the boot just sits at "Starting local ...". Redirect straight to the
# console (a tty => line-buffered + shown on VGA) so the @system progress scrolls as it goes.
exec > /dev/console 2>&1
echo; echo ">> PLX first boot: emerge -uDNq @system (completing the native base) ..."; echo
# Compile @system in RAM when there's spare -- this first-boot NATIVE build is the biggest single
# compile in the whole bootstrap. Same rule as the build host's plx-ramdisk.sh: reserve ~2 GB/core,
# need >= 32 GB left for the tmpfs (128 GB KGPE-D16 => ~64 GB tmpfs; a small-RAM box stays disk-
# backed). PORTAGE_TMPDIR is /var/tmp here (${ROOT}var/tmp with ROOT now /), so mount over
# /var/tmp/portage. Own it portage:portage (portage's default build-dir ownership): required if
# userpriv builds as the portage user, harmless if root builds.
ram_gb=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1024 / 1024 ))
cores=$(nproc 2>/dev/null || echo 1)
avail=$(( ram_gb - cores * 2 ))
if [ "$avail" -ge 32 ] && ! grep -q ' /var/tmp/portage tmpfs ' /proc/mounts; then
    mkdir -p /var/tmp/portage
    if mount -t tmpfs -o "size=${avail}G,mode=0775" plx-portage-ram /var/tmp/portage; then
        chown portage:portage /var/tmp/portage 2>/dev/null || true
        echo ">> PLX: /var/tmp/portage on ${avail}G tmpfs  (RAM ${ram_gb}G - ${cores}*2 = ${avail}G)"
    fi
fi
# Generate /etc/ld-musl-x86_64.path before the emerge. It's created by env-update (from the gcc
# profile's LDPATH in env.d), but env-update has never run on this freshly-booted system -- so
# without this musl uses its built-in default path and can't find libgcc_s.so.1 in the gcc lib dir,
# and FEATURES=sandbox's libsandbox.so fails to load, killing every ebuild phase. (gcc is already
# profile-selected by the cross install, so env-update alone puts the gcc dir on musl's path.)
env-update
if emerge -uDNq @system; then
    # base built -> normalize: drop the cross FEATURES line so the profile defaults apply (restores
    # collision-protect, ends buildpkg + the userpriv/sandbox getcwd noise). This runs on the
    # BOOTED system, so the path is the native /etc/portage/make.conf (not the chroot's $sysroot).
    sed -i '/^FEATURES=/d' /etc/portage/make.conf
    mkdir -p "${flag%/*}"; : > "$flag"; echo ">> @system complete -- login below."
else
    rc=$?; echo ">> @system FAILED (rc=$rc) -- will retry next boot; \`touch $flag\` to stop."
fi
LOCALEOF
chmod +x "$sysroot/etc/local.d/00-plx-firstboot.start"
echo "  wrote $sysroot/etc/local.d/00-plx-firstboot.start"

echo "== [5/6] install GRUB (i386-pc/BIOS) on $disk + grub.cfg =="
# i686 grub-install writes boot.img/core.img to $disk's MBR + gap and the modules to
# $sysroot/boot/grub (= sda2:/boot/grub). --boot-directory's device (sda2) is auto-detected; on a
# bind-mounted sysroot that detection is the most fragile part -- if it fails, mount /dev/sda2 at a
# plain mountpoint and re-run grub-install with --boot-directory=<that>/boot. grub-mkconfig needs
# the target running, so the grub.cfg is hand-written (msdos part table => (hd0,msdos2) = sda2).
grub-install --target=i386-pc --boot-directory="$sysroot/boot" --recheck "$disk" \
    || echo ">> WARN: grub-install failed -- likely boot-dir device detection on the bind mount (see comment)"
mkdir -p "$sysroot/boot/grub"
# rootwait: wait for the root block device to appear before mounting it -- essential when root is on
# a USB stick (KGPE-D16), which enumerates ASYNCHRONOUSLY, so /dev/sda2 isn't ready the instant the
# kernel checks; without it the kernel races the USB probe and panics. Harmless on SATA (the device
# is already there, so it returns immediately). Requires the USB drivers built in -- see 11's
# 02-plx-usb.config.
cat > "$sysroot/boot/grub/grub.cfg" <<EOF
set timeout=3
set default=0
insmod part_msdos
insmod ext2
menuentry "PLX amd64 (${kname#vmlinuz-})" {
    set root=(hd0,msdos2)
    linux /boot/${kname} root=/dev/sda2 rootwait init=/sbin/init console=tty0 rw
}
EOF
echo "  grub.cfg -> $sysroot/boot/grub/grub.cfg  (root=(hd0,msdos2), linux /boot/${kname})"

mkdir -p "$sysroot/dev" "$sysroot/proc" "$sysroot/sys"

echo "== [6/6] de-cross-ify the sysroot make.conf (native booted system) =="
# Moved here from 11: must run AFTER all the cross-emerges above (dropping ROOT breaks
# ${target}-emerge). Strip CBUILD + ROOT so the booted system emerges natively; keep FEATURES
# (until the first-boot @system finishes) and CHOST (=x86_64-unknown-linux-musl).
mc="$sysroot/etc/portage/make.conf"
[ -f "$mc" ] && { sed -i '/^CBUILD=/d; /^ROOT=/d' "$mc"; echo "  dropped CBUILD, ROOT (FEATURES + CHOST kept)"; }

echo
echo ">> sda2 is self-booting: GRUB -> kernel -> openrc -> first-boot @system -> login (root/plx)."
echo ">> Boot it on the HOST: boot-amd64-disk.sh (QEMU from the disk, VGA window) -- no kexec."

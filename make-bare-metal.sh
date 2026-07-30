#!/bin/bash
#
# make-bare-metal.sh — produce a BARE-METAL bootable image of the PLX source bootstrap, to `dd` onto
# a disk and boot on the real KGPE-D16 (a SATA HDD via a SATA-USB adapter, or a USB stick).
#
# It is the hardware sibling of run-qemu.sh. Same builder-hex0 seed image QEMU boots (init.img), with
# the same self-contained sda2 payload baked in (PLX_* below) -- but written to physical media
# instead of booted in a VM. The full multi-hour bootstrap then runs ON the KGPE-D16 at boot:
#   builder-hex0 (BIOS int 0x13) -> live-bootstrap builds Linux 4.14 (SB700 AHCI/USB drivers built in)
#   -> PLX auto-run hook (x86.sh -> x86-gentoo.sh) -> 13-reboot -> GRUB -> amd64 (@system on first boot).
# Because the sda2 payload + lb-distfiles are baked (OFFLINE=1), it needs NO host and NO network,
# exactly as intended on the real board.
#
# This is a thin wrapper around live-bootstrap's `rootfs.py --bare-metal`, which (unlike --qemu) does
# NOT boot anything -- it just assembles the image and prints where it is. It sets BARE_METAL=True
# (same as run-qemu.sh's interactive mode, so the intermediate kernel boot behaves identically) with
# QEMU=False. REQUIRES live-bootstrap patch 0005 so --bare-metal honours --target-size (see the
# pre-flight check below).
#
# OUTPUT: $LB_DIR/target/init.img  -- the printed instructions show the dd command.
#
# USAGE:
#   ./make-bare-metal.sh                       # defaults: 32 build-jobs, 64G image, offline
#   CORES=16 DISK=64G ./make-bare-metal.sh     # override via env
#
set -euo pipefail

thispath="`realpath "$0"`"
thisdir="`dirname "$thispath"`"

# ---- configuration (override via environment) ---------------------------
LB_DIR="${LB_DIR:-$thisdir/live-bootstrap}"   # live-bootstrap checkout (patched)

# CORES: for BARE METAL this is NOT a host knob -- it is the build parallelism (bootstrap.cfg
# JOBS/FINAL_JOBS) BAKED INTO THE IMAGE and used by the TARGET at boot. So set it to the KGPE-D16's
# core count (2x Opteron 6380 = 32), NOT the machine running this script (the Pi). Override for a
# different target. (The Gentoo @system stage auto-detects nproc on the target regardless.)
CORES="${CORES:-32}"

DISK="${DISK:-64G}"        # image size. move_disk.sh (patch 0001) splits it into sda1=29GiB (i686
                           # bootstrap) + sda2=rest (amd64 root). MUST be >30G or write_plx_sda2
                           # aborts "disk too small"; 64G -> sda2 ~= 34 GiB. The target disk/stick
                           # must be at least this big.
ARCH="${ARCH:-x86}"        # live-bootstrap seed arch (x86 = only supported; amd64 built FROM it)

# Source mirror (availability only -- every source is SHA256-pinned in-repo). Local offline dir:
#   (cd "$LB_DIR" && ./download-distfiles.sh)   # fills ./distfiles, verified
MIRROR="${MIRROR:-file:///$thisdir/live-bootstrap/distfiles}"

# OFFLINE=1 bakes live-bootstrap's OWN sources onto sda2 (PLX_LB_DISTFILES -> sda2:/lb-distfiles); the
# get_network.sh patch (0003) binds them onto /external/distfiles at boot so the WHOLE bootstrap runs
# from one disk with no network -- the point of a bare-metal, self-contained board. Needs a COMPLETE
# $LB_DIR/distfiles: (cd "$LB_DIR" && ./download-distfiles.sh).
OFFLINE="${OFFLINE:-1}"

# PLX self-contained sda2 payload (baked by generator.write_plx_sda2). Identical to run-qemu.sh.
#   PLX_DISTFILES -> sda2:/var/cache/distfiles/      (Gentoo @system source tarballs)
#   PLX_SCRIPTS   -> sda2:/root/tmp/bootstrap-amd64/  (the PLX bootstrap scripts, minus distfiles/)
#   PLX_SNAPSHOT  -> sda2:/root/tmp/<basename>        (the Gentoo ebuild repo snapshot)
PLX_DISTFILES="${PLX_DISTFILES:-$HOME/git/plx/bootstrap-amd64/distfiles}"
PLX_SCRIPTS="${PLX_SCRIPTS:-$HOME/git/plx/bootstrap-amd64}"
PLX_SNAPSHOT="${PLX_SNAPSHOT:-$HOME/git/plx/gentoo-20260703.tar.xz}"
PLX_LB_DISTFILES="${PLX_LB_DISTFILES:-}"
[ "$OFFLINE" = 1 ] && PLX_LB_DISTFILES="${PLX_LB_DISTFILES:-$LB_DIR/distfiles}"
export PLX_DISTFILES PLX_SCRIPTS PLX_SNAPSHOT PLX_LB_DISTFILES
# -------------------------------------------------------------------------

die() { echo "make-bare-metal.sh: $*" >&2; exit 1; }

[ -d "$LB_DIR" ]            || die "live-bootstrap not found at $LB_DIR (set LB_DIR=)"
[ -x "$LB_DIR/rootfs.py" ] || die "$LB_DIR/rootfs.py missing or not executable"
command -v fakeroot >/dev/null 2>&1 || die "fakeroot not found -- generator bakes sda2 under fakeroot (emerge sys-apps/fakeroot)"
[ -n "$MIRROR" ] || die "MIRROR is required (source mirror for live-bootstrap).
  Offline/local:  (cd $LB_DIR && ./download-distfiles.sh) then MIRROR=file://$LB_DIR/distfiles $0"
case "$MIRROR" in
    file://*) case "${MIRROR#file://}" in /*) ;; *) die "file:// MIRROR must be an absolute path" ;; esac ;;
esac

# Pre-flight: patch 0005 must be applied, else --bare-metal forces target_size=0 and write_plx_sda2
# aborts "disk too small". Detect the patched gate in rootfs.py.
grep -q 'args.qemu or args.bare_metal' "$LB_DIR/rootfs.py" 2>/dev/null \
    || die "rootfs.py not patched for bare-metal sizing. Apply the PLX patches:
  cd $LB_DIR && git apply ~/git/plx/bootstrap-amd64/live-bootstrap-patches/0005-bare-metal-target-size.patch"

# Pre-flight: rootfs.py does os.mkdir(target/init) with no cleanup -> a stale target/ makes it crash.
img="$LB_DIR/target/init.img"
if [ -e "$LB_DIR/target/init" ] || [ -e "$img" ]; then
    die "previous output present. Remove it first:
  rm -rf $LB_DIR/target/init $img"
fi

hostcores="$(nproc)"
[ "$CORES" -le "$hostcores" ] || echo "make-bare-metal.sh: note: CORES=$CORES > this host's $hostcores cores -- that's fine, CORES is the TARGET's (KGPE-D16) build parallelism baked into the image, not a host limit." >&2

echo ">> Building BARE-METAL image: arch=$ARCH  target-JOBS=$CORES  disk=$DISK  offline=$OFFLINE"
echo ">> sda2 self-contained payload (baked into the amd64 root):"
[ -d "$PLX_DISTFILES" ] && echo ">>   distfiles: $PLX_DISTFILES ($(du -sh "$PLX_DISTFILES" 2>/dev/null | cut -f1)) -> /var/cache/distfiles" \
                        || echo ">>   distfiles: $PLX_DISTFILES NOT FOUND (the amd64 @system will have no baked sources)"
[ -d "$PLX_SCRIPTS" ]   && echo ">>   scripts:   $PLX_SCRIPTS -> /root/tmp/$(basename "$PLX_SCRIPTS")" \
                        || echo ">>   scripts:   $PLX_SCRIPTS NOT FOUND (no PLX auto-run -- plain live-bootstrap)"
[ -f "$PLX_SNAPSHOT" ]  && echo ">>   snapshot:  $PLX_SNAPSHOT -> /root/tmp/$(basename "$PLX_SNAPSHOT")" \
                        || echo ">>   snapshot:  $PLX_SNAPSHOT NOT FOUND"
if [ "$OFFLINE" = 1 ]; then
    [ -d "$PLX_LB_DISTFILES" ] && echo ">>   lb-sources: $PLX_LB_DISTFILES -> /lb-distfiles (one-disk offline boot)" \
                               || die "OFFLINE=1 but PLX_LB_DISTFILES ($PLX_LB_DISTFILES) missing -- run (cd $LB_DIR && ./download-distfiles.sh), or set OFFLINE=0"
fi
echo ">> This only ASSEMBLES the seed image (minutes). The multi-hour bootstrap runs on the KGPE-D16."
echo

cd "$LB_DIR"
./rootfs.py --arch "$ARCH" --bare-metal --target-size "$DISK" --cores "$CORES" --mirrors "$MIRROR" "$@"

echo
[ -f "$img" ] || die "expected image $img was not produced -- see rootfs.py output above"
echo ">> Image ready: $img  ($(du -h "$img" 2>/dev/null | cut -f1))"
echo ">> Write it to the target disk, then boot the KGPE-D16 from it (SeaBIOS boot menu):"
echo ">>   lsblk                                  # find the device -- TRIPLE-CHECK /dev/sdX"
echo ">>   sudo umount /dev/sdX*                   # unmount anything mounted from it"
echo ">>   sudo dd if=$img \\"
echo ">>       of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct"
echo ">> SATA HDD is strongly preferred over USB (much faster; no kernel change). The target disk"
echo ">> must be >= $DISK. On boot it runs the whole bootstrap hands-off and reboots into PLX amd64."

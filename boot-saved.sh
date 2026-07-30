#!/bin/bash
# boot-saved.sh -- boot a SAVED bootstrap disk image directly in QEMU, WITHOUT re-running the
# bootstrap. run-qemu.sh/rootfs.py call generator.prepare() which REBUILDS; this just boots the
# raw image with the same disk-boot flags rootfs.py uses (rootfs.py:322-336): SeaBIOS -> sda1's
# bootloader -> the i686 live-bootstrap shell (or whatever the image now boots to).
#
# Boots a WORKING COPY (IMG, default work.img) so the pristine checkpoint (SRC, default init.img)
# stays intact for repeated re-runs. First launch copies SRC -> IMG; later launches reuse IMG
# (keeping the progress from the last run). FRESH=1 resets IMG back to the pristine checkpoint.
#
# Usage:
#   bash boot-saved.sh                  # boot work.img (copied from init.img on first run)
#   FRESH=1 bash boot-saved.sh          # reset work.img from the pristine checkpoint, then boot
#   HOSTFWD=1 bash boot-saved.sh        # also forward guest :22 -> host :2222 (ssh/scp; needs sshd)
#   IMG=/path/x.img bash boot-saved.sh  # boot a specific image (if == SRC, boots pristine in place)
#   SRC=/path/pristine.img FRESH=1 bash boot-saved.sh   # copy from a specific pristine image
# Overridable like run-qemu.sh:  RAM_MB, CORES, CPU_MODEL, QEMU_BIN.

set -e

SRC="${SRC:-$HOME/git/live-bootstrap/target/init.img}"     # pristine checkpoint (never written)
IMG="${IMG:-$HOME/git/live-bootstrap/target/work.img}"     # working copy (booted, mutated)
RAM_MB="${RAM_MB:-4000}"      # guest RAM in MB
CORES="${CORES:-4}"          # vCPUs
CPU_MODEL="${CPU_MODEL:-}"   # e.g. Opteron_G5 (bdver2 ~ KGPE-D16); empty = QEMU default
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# (Re)create the working copy from the pristine checkpoint when asked (FRESH=1) or if it's absent.
# If IMG and SRC are the SAME file, skip the copy and boot it in place (it WILL be mutated).
if [ "$(realpath -m "$IMG")" = "$(realpath -m "$SRC")" ]; then
    echo ">> NOTE: IMG == SRC ($IMG) -- booting the pristine image in place; it WILL be mutated."
elif [ "${FRESH:-0}" = 1 ] || [ ! -f "$IMG" ]; then
    [ -f "$SRC" ] || { echo "boot-saved.sh: pristine image not found: $SRC" >&2; exit 1; }
    echo ">> copying pristine $SRC -> $IMG (reflink if the filesystem supports it)"
    cp --reflink=auto -f "$SRC" "$IMG"
fi
[ -f "$IMG" ] || { echo "boot-saved.sh: image not found: $IMG" >&2; exit 1; }

[ -r /dev/kvm ] && [ -w /dev/kvm ] || \
    echo "boot-saved.sh: WARNING: /dev/kvm not accessible; -enable-kvm may fail." >&2

# SLIRP user NIC, matching rootfs.py's disk-boot branch.
#   OFFLINE=1  -> restrict=on: NIC + DHCP still come up, but ALL outbound (incl. DNS) is dropped,
#                so a run that completes is provably fully offline/self-contained.
#   HOSTFWD=1  -> forward guest:22 -> host:2222 (an explicit inbound exception even under restrict).
nic="user,ipv6=off,model=e1000"
if [ "${OFFLINE:-0}" = 1 ]; then
    nic="$nic,restrict=on"
    echo ">> OFFLINE on: guest network isolated (restrict=on) -- no host/internet access."
fi
if [ "${HOSTFWD:-0}" = 1 ]; then
    nic="$nic,hostfwd=tcp::2222-:22"
    echo ">> HOSTFWD on: from the host, ssh -p 2222 root@localhost  (guest must have sshd running)"
fi

# Interactive (graphical) -- no -nographic/-no-reboot, so a QEMU window opens and you get the
# guest console. Mirrors rootfs.py's interactive disk boot.
args=(-enable-kvm -m "${RAM_MB}M" -smp "$CORES" -machine kernel-irqchip=split
      -drive "file=$IMG,format=raw" -nic "$nic")
[ -n "$CPU_MODEL" ] && args+=(-cpu "$CPU_MODEL")

echo ">> booting $IMG  (ram=${RAM_MB}M cores=$CORES cpu=${CPU_MODEL:-default} hostfwd=${HOSTFWD:-0})"
exec "$QEMU_BIN" "${args[@]}"

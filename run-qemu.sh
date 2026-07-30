#!/bin/bash
#
# run-qemu.sh — Run the live-bootstrap source bootstrap under QEMU.
#
# This kicks off fosslinux/live-bootstrap's from-scratch bootstrap
#   (hex0 seed -> M2-Planet -> tcc -> gcc/musl userland ...)
# inside a QEMU VM, so we can inspect exactly what userland it produces.
# That userland is the intended future *seed* for PLX's amd64 (KGPE-D16)
# portage bootstrap: live-bootstrap gives us gcc+musl from source, and
# PLX's bootstrap/ scripts take over from there and `emerge @system`.
#
# It is a thin wrapper around live-bootstrap's rootfs.py. rootfs.py binds
# QEMU's -smp directly to --cores, so CORES caps BOTH host CPU usage and
# build parallelism with a single knob.
#
# NOTE ON ARCH: live-bootstrap only fully supports --arch x86 (32-bit i386)
# today; amd64 is "development only". So this bootstraps a 32-bit userland.
# That is fine and expected: PLX builds its 64-bit x86_64 system *from* this
# 32-bit userland (the same 32->64 path Guix uses). The KGPE-D16's Opteron
# runs i386 natively, so the seed is directly usable on the target.
#
# PREREQUISITES:
#   - qemu-system-x86_64 installed
#   - KVM access: /dev/kvm readable/writable (rootfs.py forces -enable-kvm)
#   - Tens of GB of free disk for the target image and distfiles
#
# USAGE:
#   ./run-qemu.sh                       # defaults: 4 cores, 4G RAM, 64G disk
#   CORES=2 RAM_MB=6000 ./run-qemu.sh   # override via env vars
#   ./run-qemu.sh --mirror /path/mirror # extra args pass through to rootfs.py
#
set -euo pipefail

# ---- configuration (override via environment) ---------------------------
LB_DIR="${LB_DIR:-$HOME/git/live-bootstrap}"  # live-bootstrap checkout
CORES="${CORES:-4}"        # vCPUs AND build jobs; keep <= host core count
RAM_MB="${RAM_MB:-4000}"   # guest RAM in MB
DISK="${DISK:-64G}"        # target image size (accepts M/G suffix). 64G because
                           # steps/jump/move_disk.sh (PLX-patched) splits the disk into
                           # sda1=29GiB (i686 bootstrap, unchanged) + sda2=rest (amd64 root).
                           # Needs >30G for sda2 to exist; 64G -> sda2 ~= 34 GiB.
ARCH="${ARCH:-x86}"        # live-bootstrap seed arch (x86 = only supported)
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# INTERACTIVE=1 passes --interactive to rootfs.py. This is NOT headless:
# rootfs.py then omits -nographic/-no-reboot, so QEMU opens a graphical
# window. You get prompted to resolve build issues as they occur, and are
# dropped to a bash shell on the guest console when the bootstrap finishes
# (steps/improve/after.sh). Requires a graphical environment (X/Wayland +
# a QEMU built with a UI); does nothing useful when run headless.
INTERACTIVE="${INTERACTIVE:-1}"

# live-bootstrap REQUIRES a source mirror (rootfs.py aborts with "At least one
# mirror must be provided" otherwise). This is an AVAILABILITY source only, NOT
# a trust anchor: every source file is pinned by a SHA256 in steps/<pkg>/sources
# and verified with `sha256sum -c`, so wrong/tampered bytes fail the build.
# Options:
#   - a public mirror URL from
#       https://github.com/fosslinux/live-bootstrap/wiki/Mirrors
#   - a local, offline dir of pre-downloaded sources (PLX-aligned):
#       (cd "$LB_DIR" && ./download-distfiles.sh)   # fills ./distfiles, verified
#       MIRROR="file://$HOME/git/live-bootstrap/distfiles" ./run-qemu.sh
# A file:// mirror MUST be an absolute path.
MIRROR="${MIRROR:-file:///home/ak/git/live-bootstrap/distfiles}"

# Optional KGPE-D16 CPU realism. rootfs.py hardcodes its QEMU arg list and
# forces -enable-kvm, so extra flags can only be injected via a wrapper that
# we pass as --qemu-cmd. The bootstrap OUTPUT does not depend on the CPU
# model, so this is OFF by default. Set to emulate the target CPU:
#   CPU_MODEL=Opteron_G5  -> Opteron 6300 (Piledriver, -march=bdver2)
#   CPU_MODEL=Opteron_G4  -> Opteron 6200 (Bulldozer,  -march=bdver1)
# WARNING: forcing an AMD model under KVM on an Intel host may fail; leave
# empty unless you specifically want to rehearse the target CPU.
CPU_MODEL="${CPU_MODEL:-}"

# OFFLINE=1 runs the WHOLE bootstrap network-free, to PROVE it is self-contained. Two parts:
#   1. Bake live-bootstrap's OWN distfiles onto sda2 (PLX_LB_DISTFILES -> sda2:/lb-distfiles, below).
#      PLX's get_network.sh patch (0003) mounts sda2 at /mnt/amd64 and bind-mounts them onto
#      /external/distfiles just before the first fetch, so live-bootstrap reads every source LOCALLY
#      (download_source_line: `[ -e $fname ]`) and never hits the mirror -- all on ONE disk (no
#      separate --external-sources disk, no parted). REQUIRES a COMPLETE $LB_DIR/distfiles:
#      (cd "$LB_DIR" && ./download-distfiles.sh).
#   2. restrict=on on the QEMU NIC (via the --qemu-cmd shim below): the e1000 NIC + DHCP still come
#      up, but ALL outbound (DNS included) is dropped -- so any stray fetch fails and a run that
#      COMPLETES proves nothing was downloaded. The Gentoo @system then uses only the sda2-baked
#      PLX_DISTFILES. (get_network.sh's `curl example.com` check can't pass under restrict; patch
#      0003 makes it non-fatal so the run continues past it.)
OFFLINE="${OFFLINE:-1}"

# PLX self-contained sda2: the generator patch (lib/generator.py write_plx_sda2) bakes these
# straight into sda2's ext4 region, so the on-disk bootstrap needs NO host/network -- as it
# must on the real KGPE-D16. Exported so rootfs.py -> generator sees them via os.environ; any
# empty/absent one is skipped.
#   PLX_DISTFILES -> sda2:/var/cache/distfiles/     (Gentoo @system source tarballs)
#   PLX_SCRIPTS   -> sda2:/root/tmp/bootstrap-amd64/ (the PLX bootstrap scripts, minus distfiles/)
#   PLX_SNAPSHOT  -> sda2:/root/tmp/<basename>       (the Gentoo ebuild repo snapshot)
PLX_DISTFILES="${PLX_DISTFILES:-$HOME/git/plx/bootstrap-amd64/distfiles}"
PLX_SCRIPTS="${PLX_SCRIPTS:-$HOME/git/plx/bootstrap-amd64}"
PLX_SNAPSHOT="${PLX_SNAPSHOT:-$HOME/git/plx/gentoo-20260703.tar.xz}"
#   PLX_LB_DISTFILES -> sda2:/lb-distfiles  (live-bootstrap's OWN sources; the get_network.sh patch
#                       binds these onto /external/distfiles for a one-disk offline build). Set
#                       automatically under OFFLINE=1 to $LB_DIR/distfiles; empty otherwise, so a
#                       normal build fetches from the mirror as usual.
PLX_LB_DISTFILES="${PLX_LB_DISTFILES:-}"
[ "$OFFLINE" = 1 ] && PLX_LB_DISTFILES="${PLX_LB_DISTFILES:-$LB_DIR/distfiles}"
export PLX_DISTFILES PLX_SCRIPTS PLX_SNAPSHOT PLX_LB_DISTFILES
# -------------------------------------------------------------------------

die() { echo "run-qemu.sh: $*" >&2; exit 1; }

[ -d "$LB_DIR" ]            || die "live-bootstrap not found at $LB_DIR (set LB_DIR=)"
[ -x "$LB_DIR/rootfs.py" ] || die "$LB_DIR/rootfs.py missing or not executable"
command -v "$QEMU_BIN" >/dev/null 2>&1 || die "$QEMU_BIN not in PATH"
[ -n "$MIRROR" ] || die "MIRROR is required (source mirror for live-bootstrap).
  Offline/local:  (cd $LB_DIR && ./download-distfiles.sh) then
                  MIRROR=file://$LB_DIR/distfiles $0
  Public mirror:  MIRROR=<url from live-bootstrap wiki Mirrors page> $0
  (Integrity is guaranteed by in-repo SHA256 sums regardless of mirror.)"
case "$MIRROR" in
    file://*) case "${MIRROR#file://}" in /*) ;; *) die "file:// MIRROR must be an absolute path" ;; esac ;;
esac
[ -r /dev/kvm ] && [ -w /dev/kvm ] || \
    echo "run-qemu.sh: WARNING: /dev/kvm not accessible; rootfs.py forces -enable-kvm and will fail." >&2

hostcores="$(nproc)"
if [ "$CORES" -gt "$hostcores" ]; then
    echo "run-qemu.sh: WARNING: CORES=$CORES > host cores ($hostcores); oversubscription is slower." >&2
fi

# Build the qemu command rootfs.py will exec. rootfs.py hardcodes its whole arg list (the -nic,
# -enable-kvm, ...), so injections go through a wrapper we pass as --qemu-cmd:
#   CPU_MODEL -> prepend -cpu <model>.
#   OFFLINE=1 -> append ,restrict=on to the value right after -nic (isolate the SLIRP net).
qemu_cmd="$QEMU_BIN"
if [ -n "$CPU_MODEL" ] || [ "$OFFLINE" = 1 ]; then
    shim="$(mktemp --tmpdir plx-qemu-shim.XXXXXX.sh)"
    trap 'rm -f "$shim"' EXIT
    {
        echo '#!/bin/sh'
        if [ "$OFFLINE" = 1 ]; then
            # Rotate through the args, appending ,restrict=on to the arg right after -nic. Pure
            # POSIX (no eval), preserves quoting: pop each arg off the front, tweak, push to back.
            cat <<'SHIM'
prev=0; n=$#
while [ "$n" -gt 0 ]; do
    a=$1; shift
    [ "$prev" = 1 ] && { a="${a},restrict=on"; prev=0; }
    [ "$a" = -nic ] && prev=1
    set -- "$@" "$a"; n=$((n-1))
done
SHIM
        fi
        if [ -n "$CPU_MODEL" ]; then printf 'exec %s -cpu %s "$@"\n' "$QEMU_BIN" "$CPU_MODEL"
        else                        printf 'exec %s "$@"\n'          "$QEMU_BIN"; fi
    } > "$shim"
    chmod +x "$shim"
    qemu_cmd="$shim"
fi

rootfs_args=(--arch "$ARCH" --qemu --qemu-cmd "$qemu_cmd"
             --qemu-ram "$RAM_MB" --target-size "$DISK" --cores "$CORES"
             --mirrors "$MIRROR")

echo ">> live-bootstrap run: arch=$ARCH cores=$CORES ram=${RAM_MB}M disk=$DISK cpu=${CPU_MODEL:-default} interactive=$INTERACTIVE offline=$OFFLINE"
echo ">> sda2 self-contained payload (baked into the amd64 root at build time):"
if [ -d "$PLX_DISTFILES" ]; then echo ">>   distfiles: $PLX_DISTFILES ($(du -sh "$PLX_DISTFILES" 2>/dev/null | cut -f1)) -> /var/cache/distfiles"
else echo ">>   distfiles: $PLX_DISTFILES NOT FOUND (bootstrap will need a network/mirror)"; fi
[ -d "$PLX_SCRIPTS" ]  && echo ">>   scripts:   $PLX_SCRIPTS -> /root/tmp/$(basename "$PLX_SCRIPTS")" \
                       || echo ">>   scripts:   $PLX_SCRIPTS NOT FOUND"
[ -f "$PLX_SNAPSHOT" ] && echo ">>   snapshot:  $PLX_SNAPSHOT -> /root/tmp/$(basename "$PLX_SNAPSHOT")" \
                       || echo ">>   snapshot:  $PLX_SNAPSHOT NOT FOUND"
echo ">> This runs the full from-scratch source bootstrap and can take many hours."
if [ "$INTERACTIVE" = 1 ]; then
    rootfs_args+=(--interactive)
    echo ">> INTERACTIVE: a graphical QEMU window will open (NOT headless);"
    echo ">>   you'll be prompted to resolve build issues, and dropped to a"
    echo ">>   bash shell on the guest console when the bootstrap completes."
else
    echo ">> Headless: serial output streams below; Ctrl-A X or Ctrl-C to abort."
fi

cd "$LB_DIR"
./rootfs.py "${rootfs_args[@]}" "$@"

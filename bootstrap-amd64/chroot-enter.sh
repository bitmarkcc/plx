#!/bin/bash
# chroot-enter.sh -- set up and enter the /mnt/gentoo chroot for the amd64 cross-bootstrap.
#
# The cross steps (x86/09-crossdev, 10-amd64-portage, 11-amd64-kernel) all run INSIDE a
# chroot into the finished i686-musl @system at /mnt/gentoo. This wires up everything that
# chroot needs -- shared distfiles/repo binds, the kernel filesystems, the /dev fd symlinks
# live-bootstrap lacks, resolv.conf -- then drops you into a clean login shell.
#
# Idempotent: skips any mount/symlink already in place, so it's safe to re-run -- e.g. after
# a QEMU reset recovering from an amd64 kexec (the mounts are gone but the disk persists).
#
# Usage (as root in the i686 guest):
#   bash chroot-enter.sh          # set up mounts + enter the chroot
#   bash chroot-enter.sh -u       # tear the mounts back down (do this before a clean reset)
#   GENTOO=/mnt/other bash chroot-enter.sh   # override the target root

set -e

gentoo="${GENTOO:-/mnt/gentoo}"

[ "$(id -u)" = 0 ] || { echo "chroot-enter: run as root"; exit 1; }
[ -d "$gentoo" ]   || { echo "chroot-enter: no such dir: $gentoo"; exit 1; }

is_mounted() { grep -q " $1 " /proc/mounts; }

if [ "$1" = "-u" ] || [ "$1" = "--umount" ]; then
    echo "== tearing down $gentoo mounts =="
    # -R on /dev to catch the rbind sub-mounts (pts, shm, ...). Reverse order of setup.
    umount -R "$gentoo/dev"  2>/dev/null || true
    umount    "$gentoo/proc" 2>/dev/null || true
    umount    "$gentoo/sys"  2>/dev/null || true
    umount    "$gentoo/var/cache/distfiles" 2>/dev/null || true
    umount    "$gentoo/var/db/repos/gentoo" 2>/dev/null || true
    umount    "$gentoo/root/tmp" 2>/dev/null || true
    umount    "$gentoo/usr/x86_64-unknown-linux-musl" 2>/dev/null || true   # sda2 bind
    echo "done"
    exit 0
fi

bind_mount() {
    local src="$1" dst="$2"
    [ -d "$src" ] || { echo "  skip (no source): $src"; return 0; }
    mkdir -p "$dst"
    is_mounted "$dst" || mount --bind "$src" "$dst"
}

echo "== bind shared repo + distfiles into $gentoo =="
# Arch-independent, so the amd64 cross-emerges reuse the same tree + tarballs the i686 @system
# already fetched -- no duplicate downloads.
bind_mount /var/db/repos/gentoo "$gentoo/var/db/repos/gentoo"
bind_mount /var/cache/distfiles "$gentoo/var/cache/distfiles"
bind_mount /root/tmp "$gentoo/root/tmp"
mkdir -p "$gentoo/etc/portage"
[ -e "$gentoo/etc/portage/make.conf" ] || cp -a /etc/portage/make.conf "$gentoo/etc/portage/make.conf"

mkdir -p "$gentoo/dev" "$gentoo/proc" "$gentoo/sys" "$gentoo/run"

echo "== kernel filesystems =="
is_mounted "$gentoo/dev"  || mount --rbind /dev  "$gentoo/dev"
is_mounted "$gentoo/proc" || mount -t proc  none "$gentoo/proc"
is_mounted "$gentoo/sys"  || mount -t sysfs none "$gentoo/sys"

echo "== /dev fd symlinks (live-bootstrap's /dev lacks them; needed for /dev/stdin etc.) =="
# /dev is rbind'd from the host, so these land in the shared /dev (fixes host + chroot at
# once). Same links as x86/01-dev.sh. ln -sf refreshes them harmlessly.
# -n (--no-dereference): /dev/fd already points to /proc/self/fd (a DIRECTORY) after the
# first run, and a plain `ln -sf` would follow it and try to create the link INSIDE
# (/dev/fd/fd -> /proc/self/fd/fd, which fails). -n replaces the symlink itself. Idempotent.
ln -sfn /proc/self/fd   "$gentoo/dev/fd"
ln -sfn /proc/self/fd/0 "$gentoo/dev/stdin"
ln -sfn /proc/self/fd/1 "$gentoo/dev/stdout"
ln -sfn /proc/self/fd/2 "$gentoo/dev/stderr"

echo "== devpts with an accessible ptmx =="
# live-bootstrap mounts /dev/pts with ptmxmode=000 -> /dev/pts/ptmx is inaccessible, so
# openpty() fails "out of pty devices" (some ebuild pre-merge checks / test suites need a
# pty). Mount a FRESH devpts instance (ptmxmode=666) on top and point /dev/ptmx at it.
# Guard on our /dev/ptmx symlink so re-runs don't stack mounts.
if [ ! -L "$gentoo/dev/ptmx" ]; then
    mkdir -p "$gentoo/dev/pts"
    mount -t devpts -o gid=5,mode=620,ptmxmode=666 devpts "$gentoo/dev/pts"
    ln -sf pts/ptmx "$gentoo/dev/ptmx"
fi

echo "== resolv.conf (DNS for fetching over the guest NAT) =="
cp -L /etc/resolv.conf "$gentoo/etc/resolv.conf" 2>/dev/null || true

echo "== bind the amd64 sysroot (sda2) into the chroot =="
# sda2 -- the amd64 root, pre-formatted with the Gentoo distfiles at /var/cache/distfiles
# (generator patch), mounted by 07-portage at the LIVE /usr/x86_64-unknown-linux-musl -- must
# appear at the SAME path INSIDE the chroot so crossdev (09) builds ONTO sda2. We can't mount
# the ext4 twice, so bind it in. Also point the chroot's DISTDIR at sda2's baked distfiles so
# the cross-emerges fetch offline. Skips cleanly if sda2 isn't mounted (e.g. PLX_DISTFILES was
# empty at build time / running before 07-portage).
# sda2 is mounted at $amd64mount in the live guest (07-portage); bind it to the crossdev
# sysroot path INSIDE the chroot. (These differ: $amd64mount is a neutral live-guest mount
# point; $sysroot is where crossdev/09 expects the sysroot.)
amd64mount=/mnt/amd64                      # where 07-portage mounts sda2
sysroot=/usr/x86_64-unknown-linux-musl     # crossdev sysroot path (== 09's $sysroot)
if grep -q " $amd64mount " /proc/mounts; then
    mkdir -p "$gentoo$sysroot"
    is_mounted "$gentoo$sysroot" || mount --bind "$amd64mount" "$gentoo$sysroot"
    if [ -d "$gentoo$sysroot/var/cache/distfiles" ] && [ ! -L "$gentoo/var/cache/distfiles" ]; then
        mkdir -p "$gentoo/var/cache"
        rmdir "$gentoo/var/cache/distfiles" 2>/dev/null || true
        # target resolves to sda2 inside the chroot ($sysroot is the bind of sda2 there)
        [ -e "$gentoo/var/cache/distfiles" ] || \
            ln -s "$sysroot/var/cache/distfiles" "$gentoo/var/cache/distfiles"
    fi
    echo "  sda2 (from $amd64mount) bound at $gentoo$sysroot"
else
    echo "  (sda2 not mounted at $amd64mount -- skipping; run 07-portage / mount sda2 first)"
fi

echo "== refresh profile.env from /etc/env.d (so the login shell gets current PATH etc.) =="
# env.d fragments (e.g. 99plx-splitpath's split-usr PATH from 08-system) only take effect once
# env-update regenerates /etc/profile.env. The `bash --login` below merely SOURCES profile.env, so
# without this it reads a STALE one -- dropping /usr/sbin:/sbin:/bin and giving the old merged PATH.
# Run env-update in the chroot with an EXPLICIT PATH: env-update lives in /usr/sbin and the stale
# profile.env PATH lacks /usr/sbin, so a plain --login shell couldn't even locate env-update itself.
chroot "$gentoo" /usr/bin/env -i HOME=/root PATH="/usr/sbin:/usr/bin:/sbin:/bin" env-update \
    >/dev/null 2>&1 || echo "  (env-update failed -- profile.env may be stale; run it manually)"

# env -i for a clean environment (don't leak the host's); HOME/TERM/PATH set explicitly.
# bash --login sources /etc/profile (-> /etc/profile.env from env-update). Exit code propagates.
# With ARGS ($#>0, and not the -u handled above), run them as a command NON-INTERACTIVELY (for
# hands-off automation, e.g. `chroot-enter.sh 'bash x86-gentoo.sh'`); with no args, drop to a shell.
if [ "$#" -gt 0 ]; then
    echo "== running in chroot ($gentoo): $* =="
    exec chroot "$gentoo" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        /bin/bash --login -c "$*"
fi

echo "== entering chroot ($gentoo) -- 'exit' returns here; mounts persist (re-run is a no-op) =="
exec chroot "$gentoo" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-linux}" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    /bin/bash --login

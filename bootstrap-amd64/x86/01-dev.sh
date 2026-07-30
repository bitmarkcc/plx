set -e

# Create the standard /dev/{fd,stdin,stdout,stderr} symlinks, BEFORE any build runs.
# Driven by ../x86-bash.sh.
#
# Why: live-bootstrap boots a minimal /dev (devtmpfs with the device NODES -- null,
# zero, tty, ... -- but not the fd symlinks). Those symlinks are normally created by
# udev or the init system, neither of which live-bootstrap runs. Many builds read
# /dev/stdin (meson/ninja steps, configure scripts, `cmd < /dev/stdin` idioms);
# without it they die "cannot stat '/dev/stdin': No such file or directory" (first
# seen building sys-apps/gentoo-functions in the amd64 cross-emerge).
#
# The four names are just symlinks into /proc/self/fd, so they need /proc mounted to
# resolve -- which it is in the live-bootstrap guest. Creating them here in the guest's
# /dev also fixes the CHROOT stage for free: the chroot rbind-mounts this same /dev, so
# it inherits these links (no need to recreate them after chrooting).
#
# Idempotent: `ln -sf` just refreshes the links. Cheap enough to run every time.

[ -e /proc/self/fd/0 ] || { echo "/proc not mounted (need it for /dev/fd symlinks)"; exit 1; }

# -n (--no-dereference): once /dev/fd points to /proc/self/fd (a DIRECTORY), a plain
# `ln -sf` would follow it and try to create /dev/fd/fd instead of replacing the link.
ln -sfn /proc/self/fd   /dev/fd
ln -sfn /proc/self/fd/0 /dev/stdin
ln -sfn /proc/self/fd/1 /dev/stdout
ln -sfn /proc/self/fd/2 /dev/stderr

echo "== /dev fd symlinks =="
ls -l /dev/fd /dev/stdin /dev/stdout /dev/stderr
echo hi | cat /dev/stdin >/dev/null && echo "  /dev/stdin readable: OK"

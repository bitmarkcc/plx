set -e

# Install a COMPLETE set of Linux 4.14 kernel headers, replacing live-bootstrap's
# partial one. Driven by ../x86-bash.sh (obuild/oprefix/j in the environment).
#
# Why: live-bootstrap's headers step (steps/linux-headers-4.14.341-openela/pass1.sh)
# deliberately `rm`s ~7 uapi headers its minimal per-file installer couldn't process
# (comment: "Buggy headers/don't know how to account for"):
#   arch/x86/include/uapi/asm/mman.h, asm/auxvec.h, asm-generic/fcntl.h,
#   linux/{pktcdvd,hw_breakpoint,eventpoll,atmdev}.h
# live-bootstrap didn't need them, but modern Gentoo does (sys-libs/libxcrypt fails
# with `asm/mman.h: No such file or directory`). We run the kernel's REAL
# `make headers_install`, which handles all of them, so nothing is dropped.
#
# Run as root: headers install straight into /usr/include, so there's no point
# building as an unprivileged user.
#
# INPUT: the FULL upstream kernel source, staged from the host. NOTE: the reduced
# source in the guest (/external/repo/linux-4.14.341-openela_0.tar.bz2) lacks the
# `headers_install` make target -- live-bootstrap stripped the source down to build
# just vmlinux -- so we use the complete upstream tarball, which has the full
# Makefile machinery.
#   /var/cache/distfiles/linux-4.14.336.tar.xz
#   (from host: ~/git/live-bootstrap/distfiles/linux-4.14.336.tar.xz)

ksrc="/var/cache/distfiles/linux-4.14.336.tar.xz"
builddir="/root/tmp/khdr"

echo "== linux-4.14 kernel headers (complete set, replaces live-bootstrap's partial one) =="
[ -f "$ksrc" ] || { echo "MISSING $ksrc -- expected the live-bootstrap kernel source in /external/repo"; exit 1; }

rm -rf "$builddir"
mkdir -p "$builddir"
cd "$builddir"
tar xf "$ksrc"
cd "$(find . -maxdepth 1 -type d -name 'linux-*' | head -1)"
make headers_install ARCH=x86 INSTALL_HDR_PATH=/usr

hash -r
ls -la /usr/include/asm/mman.h        # confirm the previously-missing header is present

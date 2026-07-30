set -e

# Build a modern findutils from source as the unprivileged `worker` user, OUTSIDE
# portage. Driven by ../x86-bash.sh (vars-x86.sh sourced with set -a, so
# obuild/oprefix/j and the asuser function are in the environment).
#
# Why: live-bootstrap ships findutils 4.2.33 (2007), but portage 3.0.79's find0()
# helper (bin/isolated-functions.sh) does `find -files0-from -`, which requires GNU
# findutils >= 4.9.0. That helper is sourced into every ebuild phase, so with the
# old find every install-phase QA check (ecompress, symlink repair, ...) fails with
# `find: invalid predicate '-files0-from'`. Built outside portage to avoid the
# chicken-and-egg: portage's own install phase would call find0 and fail.
#
# This is the one arm/-style seed build we still need; live-bootstrap provides the
# rest (gcc/binutils/make/bash/...) new enough.
#
# INPUT (staged from host, offline):
#   /root/tmp/bootstrap-amd64/distfiles/findutils-<findpv>.tar.xz

findpv="4.10.0"
distfiles="/var/cache/distfiles"

amd64root=/mnt/amd64
if [ -b /dev/sda2 ]; then
    mkdir -p /var/cache
    if [ -d "$amd64root/var/cache/distfiles" ] && [ ! -L /var/cache/distfiles ]; then
        rmdir /var/cache/distfiles 2>/dev/null || true
        [ -e /var/cache/distfiles ] || ln -s "$amd64root/var/cache/distfiles" /var/cache/distfiles
        echo "  DISTDIR /var/cache/distfiles -> $amd64root/var/cache/distfiles (sda2, offline)"
    fi
fi

echo "== findutils $findpv (source build as worker, replaces live-bootstrap's 4.2.33) =="
[ -f "$distfiles/findutils-$findpv.tar.xz" ] || {
    echo "MISSING $distfiles/findutils-$findpv.tar.xz -- stage it first"; exit 1; }

# worker user + build dir. worker is also (re)created in 07-portage.sh (idempotent).
# /root is mode 700, so copy the tarball into worker's build dir where it can read it.
grep -q '^worker:' /etc/passwd || useradd -m -s /bin/bash -G users worker || true
install -d -o worker -g worker /home/worker/bld
cp "$distfiles/findutils-$findpv.tar.xz" /home/worker/bld/
chown worker:worker "/home/worker/bld/findutils-$findpv.tar.xz"

cd /home/worker/bld
asuser rm -rf "findutils-$findpv"
asuser tar -xf "findutils-$findpv.tar.xz"
cd "findutils-$findpv"
asuser ./configure $obuild $oprefix
asuser make -j$j
make install                    # root: writes to /usr
hash -r
find --version | head -1        # expect $findpv

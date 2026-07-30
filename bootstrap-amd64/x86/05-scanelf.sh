set -e

# Build `scanelf` (from app-misc/pax-utils) from source, OUTSIDE portage. Driven by
# ../x86-bash.sh (obuild/oprefix/j and asuser in the environment).
#
# Why: portage's gen_usr_ldscript reads library SONAMEs with `scanelf` during install
# phases; without it, packages die "unable to read SONAME from lib*.so" (ncurses is the
# first). live-bootstrap doesn't ship pax-utils. We can't `emerge` it here: modern
# pax-utils builds with meson (+ meson-format-array + ninja), none of which exist yet --
# and pax-utils[python] would drag in python->ncurses, which itself needs scanelf
# (chicken-and-egg). But scanelf.c bundles its own elf.h/macho.h and needs no libelf, so
# we compile it directly with gcc. The only thing meson would generate is config.h
# (feature macros + VERSION), which we write by hand. Needs the complete kernel headers
# from 04-linux-headers (linux/seccomp.h, linux/securebits.h) and -D_GNU_SOURCE
# (unshare()). Verified: our scanelf's SONAME output matches readelf.
#
# INPUT (staged from host, offline):
#   /root/tmp/bootstrap-amd64/distfiles/pax-utils-<paxpv>.tar.xz

paxpv="1.3.10"
distfiles="/var/cache/distfiles"

echo "== scanelf $paxpv (source build as worker, live-bootstrap lacks pax-utils) =="
[ -f "$distfiles/pax-utils-$paxpv.tar.xz" ] || {
    echo "MISSING $distfiles/pax-utils-$paxpv.tar.xz -- stage it first"; exit 1; }

# worker user + build dir (idempotent; also (re)created in 03-find.sh / 07-portage.sh).
# /root is mode 700, so copy the tarball into worker's build dir where it can read it.
grep -q '^worker:' /etc/passwd || useradd -m -s /bin/bash -G users worker || true
install -d -o worker -g worker /home/worker/bld
cp "$distfiles/pax-utils-$paxpv.tar.xz" /home/worker/bld/
chown worker:worker "/home/worker/bld/pax-utils-$paxpv.tar.xz"

cd /home/worker/bld
asuser rm -rf "pax-utils-$paxpv"
asuser tar -xf "pax-utils-$paxpv.tar.xz"
cd "pax-utils-$paxpv"

# Generate config.h the way meson would: it defines HAVE_<HEADER> only for headers
# that actually exist on this host (meson.build: `foreach x : [...] if cc.has_header(x)`).
# We replicate that exactly -- probe each candidate with the compiler rather than
# hardcode a guessed set -- so it's correct on any host (BSD/Solaris-only headers are
# simply not defined here because the probe fails). Header list is verbatim from
# pax-utils-1.3.10 meson.build. VERSION + -D_GNU_SOURCE are also set by meson.
: > config.h
echo "#define VERSION \"$paxpv\"" >> config.h
for h in endian.h byteswap.h sys/endian.h sys/isa_defs.h machine/endian.h \
         linux/seccomp.h linux/securebits.h sys/prctl.h elf-hints.h glob.h; do
    if echo "#include <$h>" | gcc -E -x c - >/dev/null 2>&1; then
        echo "#define HAVE_$(echo "$h" | tr 'a-z./' 'A-Z__') 1" >> config.h
    fi
done
echo "--- generated config.h ---"; cat config.h
chown worker:worker config.h

asuser gcc -O2 -D_GNU_SOURCE -o scanelf \
    scanelf.c paxelf.c paxinc.c paxldso.c paxmacho.c security.c xfuncs.c -I.
install -m0755 scanelf /usr/bin/scanelf     # root: install to /usr/bin
hash -r
scanelf --version | head -1

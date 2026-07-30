set -e

# Build the native i686-musl Gentoo @system into a SEPARATE root ($sysroot), driven
# by ../x86-bash.sh (obuild/portagebin/PATH/PYTHONPATH/target/j in the environment).
#
# WHY A SEPARATE ROOT: emerging @system over the running live-bootstrap userland
# rebuilds musl/coreutils/python IN PLACE (collision-protect off) and breaks the
# running system (python -> emerge dies). Learned the hard way 2026-07-05. With ROOT=,
# the target packages (musl, coreutils, ...) install into $sysroot; only build-host
# tools (BDEPEND) touch / -- additively, never replacing the builder's libc.
#
# PREREQS: 03-find, 04-linux-headers, 05-scanelf, 06-getent, 07-portage already run (working emerge with the
# movefile fetcher fix). The fetcher works now, so @system + the seeds fetch their own
# distfiles over the guest's NAT -- no manual distfile staging.
#
# NOTE -- FRONTIER: a ROOT= @system from a non-Gentoo host can shift which build-order
# cycles appear vs the in-place plan (host/target DEPEND vs BDEPEND split). If emerge
# reports a NEW circular dependency, add portage's suggested USE toggle to
# /etc/portage/package.use/00-bootstrap (or seed the package) and re-run. The set below
# is what a clean IN-PLACE plan needed (198 -> clean 256); expect to iterate.

sysroot="/mnt/gentoo"

echo "== [1/5] bootstrap USE cycle-breakers -> /etc/portage/package.use/00-bootstrap =="
mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/bootstrap <<'EOF'
# TEMPORARY -- breaks @system build-order cycles on a from-empty base. Remove after the
# base is built, then re-emerge the affected packages with full USE.
*/* -nls                            # attr <-> gettext (and the nls/gettext cycles)
sys-apps/util-linux -su -pam        # pam <-> docbook <-> util-linux
app-alternatives/awk -gawk mawk     # gawk <-> bison <-> ... <-> awk  (point awk at mawk)
sys-devel/gcc -openmp -fortran      # -openmp: libgomp's pthread configure probe fails on
                                    #   musl ("Pthreads are required to build libgomp").
                                    # -fortran: gfortran/libgfortran are unneeded for this
                                    #   bridge toolchain (nothing in the base uses Fortran)
                                    #   and libgfortran risks the same musl snags. Trim gcc
                                    #   to what the bridge needs: C and C++.
# Since gcc above is -openmp, libgomp (the OpenMP runtime) is NEVER built -- so any package
# that turns openmp ON (e.g. app-crypt/libb2, which defaults it on) fails to link -lgomp.
# Disable openmp EVERYWHERE to match the toolchain. Off until a fuller gcc provides libgomp.
*/* -openmp
# Build merged-usr, matching the merged-usr live-bootstrap HOST. app-alternatives/* (awk,
# bc, cpio, lex, yacc, ...) install split-usr dual symlinks (/bin/foo -> ../usr/bin/foo
# plus /usr/bin/foo). When such a pkg installs to the host / as a BUILD dep, portage's
# collision check (realpath-based) collapses /bin -> /usr/bin on the merged-usr host, so
# both symlinks map to one path -> "internal collisions ... merged directories". OFF
# everywhere avoids this whole class. (Fine here: this i686 stage is a bridge to the amd64
# cross-build, not a pristine split-usr system.)
*/* -split-usr
# Minimal Python: [build] drops the optional stdlib modules (readline, sqlite, tk, gdbm,
# ncurses/_curses, ...) that would otherwise pull extra packages into the early @system
# graph. portage only needs core Python, so this trims deps + breaks their cycles. Off
# until the base is built (then re-emerge dev-lang/python with full USE).
dev-lang/python build
EOF

# Pre-empt app-arch/bzip2's pkg_postinst: it wants /bin/{bzip2,bunzip2,bzcat} to be
# SYMLINKS to bzip2-reference and does `ln -s ... || die` guarded only by "not already a
# symlink". live-bootstrap ships bzip2 as a REAL binary (regular file), so on the merged-
# usr host the guard passes but ln dies "File exists". Convert live-bootstrap's bzip2 to
# the split layout first (keeps a working bzip2 the whole time). Idempotent: skips once
# /usr/bin/bzip2 is already a symlink.
if [ -e /usr/bin/bzip2 ] && [ ! -h /usr/bin/bzip2 ]; then
    mv /usr/bin/bzip2 /usr/bin/bzip2-reference
    for x in bzip2 bunzip2 bzcat; do ln -sf bzip2-reference /usr/bin/$x; done
fi

# Same pattern for app-arch/gzip (`ln: /bin/gunzip: File exists`). Difference from bzip2:
# gzip uses PER-TOOL references -- its postinst does `ln -s ${x}-reference /bin/${x}`, so
# gunzip->gunzip-reference, gzip->gzip-reference, zcat->zcat-reference (not one shared
# reference). Convert each live-bootstrap real file to its own -reference + symlink.
for x in gunzip gzip zcat; do
    if [ -e /usr/bin/$x ] && [ ! -h /usr/bin/$x ]; then
        mv /usr/bin/$x /usr/bin/$x-reference
        ln -sf $x-reference /usr/bin/$x
    fi
done

echo "== [2/5] seed --nodeps cycle-breakers (build host) =="
# Two cycles have no USE lever; pre-install one member of each so the graph is acyclic
# (elt-patches <-> xz-utils ; libcrypt <-> perl). Installed on the build host (not ROOT)
# because they break BUILD-time cycles. Additive: elt-patches is patch data, libxcrypt
# adds libcrypt.so -- neither replaces the builder's musl. libxcrypt's build needs
# asm/mman.h on the host, provided by 04-linux-headers.
emerge -q --oneshot --nodeps app-portage/elt-patches sys-libs/libxcrypt

# elt-patches' eltpatch script (run on the build host during elibtoolize) sources
# /lib/gentoo/functions.sh from sys-apps/gentoo-functions -- a RUNTIME dep our --nodeps
# seed of elt-patches skipped. gentoo-functions builds with meson (which we don't have),
# but its shell parts are ready-to-use (arch-independent, no @TOKEN@ substitution), so we
# fetch the source and install them on the build host. functions.sh (1.7.x) sources its
# modules from ${genfun_basedir}/functions/*.sh, so the whole functions/ subdir is needed
# too -- installing only functions.sh gives "no gentoo-functions modules were found".
# (The consoletype/shquote C helpers are unused by eltpatch and skipped.)
if [ ! -d /lib/gentoo/functions ]; then
    emerge -q --fetchonly sys-apps/gentoo-functions
    gfsrc="$(ls -t /var/cache/distfiles/gentoo-functions-*.tar.* 2>/dev/null | head -1)"
    [ -n "$gfsrc" ] || { echo "could not obtain gentoo-functions source"; exit 1; }
    rm -rf /root/tmp/gf; mkdir -p /root/tmp/gf /lib/gentoo
    tar -xf "$gfsrc" -C /root/tmp/gf
    install -m0644 /root/tmp/gf/gentoo-functions-*/functions.sh /lib/gentoo/functions.sh
    cp -a /root/tmp/gf/gentoo-functions-*/functions /lib/gentoo/
fi

# NOTE: clearing stale live-bootstrap triple-dir libs (which shadow Gentoo's shared libs
# at link time -> undefined refs / DSO-missing / TEXTREL) is now done CONTINUOUSLY by the
# /etc/portage/bashrc post_pkg_postinst hook set up in 07-portage step 1 -- it fires after
# every package install, so a stale shadow is cleared the moment Gentoo's replacement lands
# in /usr/lib, within the SAME emerge run (vs a once-at-start pass here that would need one
# re-run of 08-system per newly-shadowing lib). Nothing to do at this step anymore.

echo "== [3/5] seed acct-user/group accounts @system chowns against on the HOST (/) =="
# sys-apps/man-db's install runs `fowners man:man`, which portage resolves against the BUILD
# HOST's user db (/), NOT ROOT. But `emerge @system` installs the acct-user/man + acct-group/man
# packages into ROOT=$sysroot only -- so / has no `man` account and the chown dies ("illegal
# user name"). Pre-install those onto / (canonical UID 13 / GID 15, matching the target copies)
# BEFORE @system reaches man-db. These are metadata-only ebuilds (no SRC_URI) so this is offline-
# safe, and --noreplace makes it idempotent across reruns. Extend the atom list if another
# package's fowners later hits a missing acct-user (e.g. sshd/messagebus on a fuller build).
emerge -q --oneshot --noreplace acct-group/man acct-user/man

echo "== [4/5] emerge @system into $sysroot =="
install -d "$sysroot"
# No merged-usr skeleton here: in practice @system lands split-usr anyway (the x86 17.0/musl
# profile lays out real /bin, /sbin via baselayout), so we accept that for this throwaway bridge
# rather than pre-symlinking. The split-usr PATH is handled by the 99plx-splitpath env.d fragment
# ([5/5]) + vars-x86.sh; the amd64 TARGET still gets its own merged-usr skeleton in 09-crossdev.
# NB: */* -split-usr stays in package.use above -- it isn't (only) about the sysroot layout, it
# also prevents app-alternatives dual-symlink collisions when their BUILD deps install to the
# merged live-bootstrap host /, which is independent of how this sysroot ends up.
set +e   # --keep-going exits non-zero on partial failures; report, don't abort
# -u (--update): @system is a SET, so a bare `emerge @system` treats every member as an
# explicit atom and REINSTALLS all of them each run (the "R" flag) -- which re-clobbers
# the host (musl reinstall rewrites /etc/ld-musl-*.path, etc.) and never makes forward
# progress. -u skips already-installed up-to-date pkgs. -D checks the full dep tree.
# -N (--newuse) rebuilds pkgs whose USE changed vs when installed -- needed because we
# set -nls/-split-usr/python[build] AFTER some pkgs were already built, so they must be
# brought into line (a one-time catch-up wave; USE is stable after).
ROOT="$sysroot" emerge -quDN --keep-going @system
rc=$?

echo "== [5/5] pre-install chroot build tools into $sysroot =="
# m4/make/texinfo are BDEPEND-only (not @system), so @system left them on the live host only;
# building them later INSIDE the chroot fails on musl (gnulib fseeko/ftello "please port" +
# gettext's mbstate_t/mbrlen pointer-type error) though they build fine HERE on the host. Install
# them (and re-assert the @system bison/flex/gettext) into the target now, so 09's gcc rebuild
# finds them satisfied and never compiles them in the chroot. -1 (oneshot -- keep them out of
# @world, they're just build tools) + --noreplace (fill only what's missing, e.g. m4).
ROOT="$sysroot" emerge -1q --noreplace sys-devel/m4 sys-devel/bison sys-devel/flex sys-devel/gettext

# Bake the split-usr PATH into the sysroot's env.d. This bridge @system comes out split-usr, but
# base-files installs a merged-usr PATH (only /usr/bin; sbin folded into bin), so inside the chroot
# the /sbin, /bin, /usr/sbin binaries would be off-PATH. Add them so env-update's profile.env (which
# chroot-enter's `bash --login` sources) carries them. 99* sorts last -> merged in on top.
mkdir -p "$sysroot/etc/env.d"
printf 'PATH="/usr/sbin:/sbin:/bin"\nROOTPATH="/usr/sbin:/sbin:/bin"\n' > "$sysroot/etc/env.d/99plx-splitpath"

# @system + the build tools are now in $sysroot, so the i686 source-tree emerge's fetch-as-portage-
# user phase is done -- restore /root to 0700 (07 opened it a+rx so the portage user could reach the
# source-tree emerge under /root for Python 3.14's spawn re-exec). Stages 09+ run INSIDE the chroot
# with the installed portage, so the host /root perms no longer matter.
chmod 0700 /root

echo
echo ">> emerge @system exit=$rc  (non-zero is normal with --keep-going if some pkgs failed)"
echo ">> Result: a clean i686-musl Gentoo tree in $sysroot; the live builder is untouched."
echo ">> Next (later steps): chroot into $sysroot, remove package.use/00-bootstrap,"
echo ">>   re-emerge the reduced-USE pkgs with full USE, then crossdev -> $target."

set -e

# Runs inside the live-bootstrap i686-musl guest as root, driven by ../x86-bash.sh
# (which sourced vars-x86.sh with set -a, so obuild/oprefix/portagebin/PATH/target/j
# and the asuser function are in the environment).
#
# Analog of bootstrap/arm/11-portage.sh, modernized for a current Gentoo tree +
# portage 3.0.79 + x86 musl. Since there is no stage3 here, this step also does the
# make.conf/profile/users setup that arm inherited from its stage3 tarball.
#
# Goal: a working `emerge` on an x86-musl profile. It does NOT emerge anything yet;
# it ends at `emerge --info`. @system is step 08-system.sh.
#
# INPUTS (place in /root/tmp first; this script itself makes NO network calls):
#   /root/tmp/gentoo-latest.tar.xz          Gentoo ebuild repo snapshot
#   /root/tmp/portage-3.0.79.tar.bz2        portage source (host /var/cache/distfiles)
# Deliver them from your host however you like (nothing here touches an external
# server), e.g. via the host HTTP server:
#   curl -fLo /root/tmp/gentoo-latest.tar.xz   http://10.0.2.2:8000/gentoo-latest.tar.xz
#   curl -fLo /root/tmp/portage-3.0.79.tar.bz2 http://10.0.2.2:8000/portage-3.0.79.tar.bz2

build="${obuild#--build=}"                                  # i686-unknown-linux-musl (CHOST)
portagepv="$(basename "$(dirname "$portagebin")" | sed 's/^portage-//')"  # 3.0.79, from vars
repo="/var/db/repos/gentoo"                                 # ebuild repo (modern location)
snapshot="/root/tmp/gentoo-20260703.tar.xz" #tmp hardcode the version

echo "== [1/8] build env: devpts + baked distfiles + musl lib path + users =="
# portage build phases need ptys (openpty); ensure devpts is mounted (idempotent:
# a second mount just errors harmlessly and is swallowed).
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts 2>/dev/null || true

# sda2 (the amd64 root -- pre-formatted by the live-bootstrap generator patch with the Gentoo
# distfiles at /var/cache/distfiles) is mounted at /mnt/amd64 by 03-find (the first distfiles
# consumer), which also points the default DISTDIR (/var/cache/distfiles) at sda2's copy. So
# @system builds OFFLINE (no host, no network -- as on the real KGPE-D16), and the SAME physical,
# arch-independent tarballs serve the i686 @system, the cross-emerges, AND the native amd64
# @system. 07 just uses /var/cache/distfiles from here.

# Fix the musl dynamic-linker search path. When /etc/ld-musl-<arch>.path exists it
# REPLACES musl's built-in default (/lib:/usr/local/lib:/usr/lib), it does not extend
# it. live-bootstrap wrote it with only its custom libdir, so the standard /usr/lib is
# no longer searched -- and Gentoo installs build-tool libraries (BDEPENDs land on the
# host /) into /usr/lib, e.g. libpkgconf.so.7, which then fails to load ("Error loading
# shared library ...: No such file or directory"). Restore the standard dirs. Order =
# search precedence (first match wins) and mirrors a real PLX musl system's generated
# path (Gentoo convention: /usr/lib BEFORE /usr/local/lib -- NOT musl's raw hardcoded
# default of /lib:/usr/local/lib:/usr/lib). /lib leads (only the ld-musl symlink lives
# there, nothing to shadow); then live-bootstrap's native libc dir /usr/lib/<triple>
# (the build-host analog of a normal system's /usr/lib native libdir, where libc.so and
# the core libs live); then plain /usr/lib for Gentoo BDEPEND libs; then /usr/local/lib.
cat > /etc/ld-musl-i386.path <<'EOF'
/lib
/usr/lib/i686-unknown-linux-musl
/usr/lib
/usr/local/lib
EOF
# ...but portage runs `env-update` after EVERY emerge, which REGENERATES this file from
# the LDPATH entries in /etc/env.d/* -- dropping our triple dir every pass (breaking
# libpython3.14/libstdc++ -> python3.14 -> meson, intermittently). So also register the
# triple dir in env.d so env-update keeps it. 00 prefix sorts it early in the path.
mkdir -p /etc/env.d
echo 'LDPATH="/usr/lib/i686-unknown-linux-musl"' > /etc/env.d/00musl-triple

# /etc/portage/bashrc: a post_pkg_postinst hook, run after EVERY package install, that
# repairs the two bits of host state @system keeps clobbering. Doing it here (not once at
# 08-system start) means it self-heals WITHIN a single emerge run -- as soon as a Gentoo
# lib lands in /usr/lib, the stale triple-dir shadow is cleared before the next pkg links.
#
#  (1) python3 keeps flip-flopping to the (broken) python-exec wrapper when
#      dev-lang/python[-exec] is reinstalled, breaking meson (mesonbuild is only for 3.14).
#      Pin python3 -> python3.14 (both portage-3.0.79 and meson work under it), else fall
#      back to live-bootstrap's python3.11 (portage works; fine before 3.14 is built).
#  (2) live-bootstrap's stale static libs in the gcc TRIPLE dir (searched before /usr/lib)
#      shadow Gentoo's shared ones once built, breaking links (libblkid: undefined
#      uuid_unparse; libarchive: DSO-missing libcrypto; liblzma: non-PIC .a -> TEXTREL).
#      Drop each triple-dir LINK artifact (.a/.la/.so) once its Gentoo replacement
#      (versioned .so.N) exists in /usr/lib. Never touch runtime .so.N (nothing loaded
#      breaks); protect the interpreter + C/C++/py runtime libs still only in the triple dir.
#  (3) sys-libs/musl (NOT gcc) provides libssp_nonshared.a on musl profiles and installs it
#      NON-PIC (its ebuild compiles stack_chk_fail_local.c with bare ${CFLAGS}), so gcc's later
#      libstdc++.so link (and every other @system link) would TEXTREL on the hardened-PIE
#      profile. Re-PIC every copy after each musl install, using a PIC object pre-built below.
mkdir -p /etc/portage

# Pre-build gcc's stack-protector wrapper PIC once, for the sys-libs/musl hook (3) below.
# Recipe: gcc/ssp-local.c (gcc-15.2.0's libssp/ssp-local.c verbatim) compiled -fPIC IN PLACE in
# gcc/ -- it #includes "config.h", so we drop one (defining HAVE_HIDDEN_VISIBILITY) beside it and
# -I that dir (no /tmp, no source copy), then remove it. Stashed at a fixed path the hook `ar
# rcs`es over each non-PIC libssp_nonshared.a that musl re-drops during @system.
sspobj=/etc/portage/plx-ssp-local-pic.o
sspsrc="$(cd "$(dirname "$0")" && pwd)/../gcc/ssp-local.c"
if [ -f "$sspsrc" ]; then
    work="$(dirname "$sspsrc")"        # bootstrap-amd64/gcc/ (holds ssp-local.c)
    printf '#define HAVE_HIDDEN_VISIBILITY 1\n' > "$work/config.h"
    gcc -fPIC -O2 -I"$work" -c "$sspsrc" -o "$sspobj"
    nm "$sspobj" | grep -q 'T __stack_chk_fail_local' \
        || { echo "07: $sspobj missing __stack_chk_fail_local"; exit 1; }
    rm -f "$work/config.h"
    echo "07: pre-built PIC ssp-local.o -> $sspobj (for the sys-libs/musl re-PIC hook)"
else
    echo "07: WARNING: $sspsrc missing -- libssp re-PIC hook will be a no-op"
fi

cat > /etc/portage/bashrc <<'EOF'
post_pkg_postinst() {
    # (1) pin python3
    if [ -e /usr/bin/python3.14 ]; then
        ln -sf python3.14 /usr/bin/python3
    elif [ -e /usr/bin/python3.11 ]; then
        ln -sf python3.11 /usr/bin/python3
    fi
    ln -sf python3 /usr/bin/python

    # (2) clear stale triple-dir link artifacts Gentoo has replaced
    local triple=/usr/lib/i686-unknown-linux-musl
    local protect="libc libstdc++ libgcc_s libpython3.14 libpython3.11 libssp libgomp"
    local f base
    for f in "$triple"/lib*.a "$triple"/lib*.so; do
        [ -e "$f" ] || continue
        base=$(basename "$f"); base=${base%.a}; base=${base%.so}
        case " $protect " in *" $base "*) continue ;; esac
        ls /usr/lib/$base.so.* >/dev/null 2>&1 && rm -f "$triple/$base".{a,la,so}
    done

    # (3) re-PIC libssp_nonshared.a whenever sys-libs/musl installs it. On musl profiles this
    #     .a is provided by MUSL, not gcc: musl's ebuild compiles stack_chk_fail_local.c with
    #     bare ${CFLAGS} (no -fPIC), so dolib.a installs a NON-PIC libssp_nonshared.a.
    #     Linking it into ANY shared object (gcc's own libstdc++.so
    #     while gcc BUILDS, or any later @system pkg) TEXTRELs on the hardened-PIE profile -> the
    #     link is REJECTED -> gcc's build dies BEFORE it can install (so no gcc-side hook could
    #     ever fire). Overwrite every copy this install dropped with the PIC object pre-built in
    #     07. Fires for both the ROOT=/ build-host copy gcc links and the ROOT=/mnt/gentoo target.
    if [ "${CATEGORY}/${PN}" = "sys-libs/musl" ] && [ -e /etc/portage/plx-ssp-local-pic.o ]; then
        local l
        for l in $(find "${ROOT%/}/usr/lib" "${ROOT%/}/lib" \
                        "${ROOT%/}/usr/lib/i686-unknown-linux-musl" \
                        -name libssp_nonshared.a 2>/dev/null); do
            rm -f "$l" && ar rcs "$l" /etc/portage/plx-ssp-local-pic.o
        done
    fi
}
EOF

grep -q '^portage:' /etc/group  || groupadd portage
grep -q '^portage:' /etc/passwd || useradd -g portage -d /var/tmp/portage -s /bin/false portage
install -d -o portage -g portage /var/tmp/portage
chown -R portage:portage /var/cache/distfiles

# The portage user (fetch runs as it -- profile userfetch) must be able to reach the source-tree
# emerge under /root: Python 3.14 moved multiprocessing's default start method off 'fork', so the
# fetch worker RE-EXECS the emerge script instead of forking, and /root at 0700 makes that read
# fail (PermissionError [Errno 13]) the moment a distfile isn't already baked on sda2 (e.g. skalibs
# via s6-rc). Open /root so the fetch can proceed; 08 restores 0700 once its emerges are done.
chmod a+rx /root

echo "== [2/8] extract ebuild repo -> $repo =="
[ -f "$snapshot" ] || { echo "MISSING $snapshot (fetch it first -- see header)"; exit 1; }
if [ ! -d "$repo/profiles" ]; then
    mkdir -p "$(dirname "$repo")"
    tmpd="$(mktemp -d)"
    tar -xpf "$snapshot" -C "$tmpd"
    inner="$(find "$tmpd" -maxdepth 1 -mindepth 1 -type d | head -1)"   # 'portage' or 'gentoo'
    rm -rf "$repo"; mv "$inner" "$repo"; rm -rf "$tmpd"
fi
#install -d -o portage -g portage "/var/cache/distfiles"
chown portage:portage "$repo"
#cp -a "/root/tmp/bootstrap-amd64/distfiles/." /var/cache/distfiles/

echo "== [3/8] sys-apps/portage versions in tree (confirm $portagepv is present) =="
ls -1 "$repo"/sys-apps/portage/portage-*.ebuild 2>/dev/null \
    | sed 's#.*/portage-##;s#\.ebuild$##' | grep -v 9999 | sort -V | tail -3 || true

echo "== [4/8] select x86 musl profile =="
prof="$(ls -d "$repo"/profiles/default/linux/x86/*/musl 2>/dev/null | sort -V | tail -1)"
if [ -z "$prof" ]; then
    echo "No x86 musl profile under $repo/profiles/default/linux/x86/*/musl ; available:"
    ls -d "$repo"/profiles/default/linux/x86/*/ 2>/dev/null
    exit 1
fi
mkdir -p /etc/portage
ln -sfn "$prof" /etc/portage/make.profile
echo "  profile: $prof"

# Un-force split-usr. The x86 17.0/musl profile is split-usr and FORCE-enables the
# split-usr flag (use.force), so `-split-usr` in package.use is ignored ("(split-usr)"
# in emerge -pv). We build merged-usr to match the merged-usr live-bootstrap HOST (see
# the */* -split-usr note in 08-system) -- otherwise app-alternatives/* dual symlinks
# collide when installed to / as build deps. /etc/portage/profile stacks on top of the
# profile; a `-flag` line in its use.force removes that flag from the forced set, letting
# package.use's `-split-usr` take effect.
mkdir -p /etc/portage/profile
grep -qx -- '-split-usr' /etc/portage/profile/use.force 2>/dev/null || echo '-split-usr' >> /etc/portage/profile/use.force

echo "== [5/8] make.conf =="
cat > /etc/portage/make.conf <<EOF
CHOST="$build"
CFLAGS="-O2 -pipe"
CXXFLAGS="\${CFLAGS}"
COMMON_FLAGS="\${CFLAGS}"
MAKEOPTS="-j$j"
# Relaxed for bootstrapping onto a non-Gentoo host (no sandbox binary yet, root
# builds, overlaying files owned by the live-bootstrap userland):
FEATURES="-sandbox -usersandbox -userpriv -ipc-sandbox -network-sandbox -pid-sandbox -protect-owned -collision-protect"
ACCEPT_LICENSE="*"
USE="-X -gtk -qt5 -qt6 -gnome -kde -wayland -systemd -introspection -doc -urandom -gui -llvm -clang"
DISTDIR="/var/cache/distfiles"
PORTAGE_TMPDIR="/var/tmp"
EOF

# curl fetcher (wget is absent in this userland). Separate QUOTED heredoc so the
# backslashes land verbatim: \$ defers ${FILE}/${URI} to portage's fetch-time
# substitution, \" gives literal quotes for path safety. Do NOT fold these into
# the unquoted (<<EOF) block above -- it would eat the backslashes.
cat >> /etc/portage/make.conf <<'EOF'
FETCHCOMMAND="curl -f -L --retry 3 -o \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
RESUMECOMMAND="curl -f -L --retry 3 -C - -o \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
EOF

echo "== [6/8] repos.conf =="
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<EOF
[DEFAULT]
main-repo = gentoo

[gentoo]
location = $repo
auto-sync = no
EOF

echo "== [7/8] toolchain + GNU-name symlinks ($build-*, gtar/gpatch/gsed) =="
cd /usr/bin
gcc_bin="$(command -v gcc)"; gxx_bin="$(command -v g++ || echo "$gcc_bin")"
[ -e "$build-gcc" ] || ln -s "$gcc_bin" "$build-gcc"
[ -e "$build-g++" ] || ln -s "$gxx_bin" "$build-g++"
[ -e "$build-c++" ] || ln -s "$gxx_bin" "$build-c++"
for b in ar as ld nm ranlib strip objcopy objdump readelf size strings addr2line c++filt; do
    p="$(command -v "$b" 2>/dev/null || true)"
    if [ -n "$p" ] && [ ! -e "$build-$b" ]; then ln -s "$p" "$build-$b"; fi
done
# GNU tool names portage's build helpers call (bin/phase-helpers.sh unpack, etc.):
# gtar/gpatch/gsed. live-bootstrap ships tar/patch/sed (which ARE GNU); the Gentoo
# packages provide the g-names once @system is built, so these just bridge the gap.
for g in tar patch sed; do
    p="$(command -v "$g" 2>/dev/null || true)"
    if [ -n "$p" ] && [ ! -e "g$g" ]; then ln -s "$p" "g$g"; fi
done
cd - >/dev/null

echo "== [8/8] portage source ($portagepv) -> /root/portage-$portagepv, then validate =="
# Pre-placed local input (like the ebuild snapshot in step 2). No network here:
# supply this tarball yourself (e.g. from the host's /var/cache/distfiles).
portage_src="/var/cache/distfiles/portage-$portagepv.tar.bz2"
if [ ! -x "$portagebin/emerge" ]; then
    [ -f "$portage_src" ] || { echo "MISSING $portage_src -- place the portage source tarball there first (see header)"; exit 1; }
    cd /root/tmp
    tar -xf "$portage_src"
    d="$(find . -maxdepth 1 -type d -name "portage-*$portagepv*" | head -1)"
    [ "$d" = "./portage-$portagepv" ] || mv "$d" "portage-$portagepv"
fi

# Preload portage.util.movefile at 'import portage' time so emerge's forked fetcher
# inherits it already in sys.modules. Running portage from a raw source tree, the
# fetcher fork otherwise fails to import it fresh ("No module named
# 'portage.util.movefile'"), which breaks ALL fetching. Idempotent.
pinit="$(dirname "$portagebin")/lib/portage/__init__.py"
grep -q '^import portage.util.movefile' "$pinit" 2>/dev/null || echo 'import portage.util.movefile' >> "$pinit"

set +e
echo "--- emerge --version ---"
emerge --version
echo "--- emerge --info (head) ---"
emerge --info 2>&1 | head -40
echo
echo ">> If 'emerge --version' printed @VERSION@ or errored, portage's raw source"
echo ">> tree needs meson-era template substitution -- paste the output and we'll"
echo ">> fix step 8 (e.g. tar the host's already-installed /usr/lib/portage instead)."

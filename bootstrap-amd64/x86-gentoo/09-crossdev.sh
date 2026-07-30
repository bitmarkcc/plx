set -e

# Build the x86_64-unknown-linux-musl CROSS-toolchain and stage a MERGED-USR amd64 sysroot
# at /usr/${target}/ under the standard 23.0/musl profile, using crossdev.
#
# CONTEXT -- DIFFERENT FROM 01-08: those run in the live-bootstrap i686 guest and build
# the native i686 @system into /mnt/gentoo (via ROOT=). THIS script runs INSIDE a chroot
# into that finished /mnt/gentoo -- a clean, self-hosting i686-musl Gentoo with a working
# portage and a native gcc. Not driven by x86-bash.sh; run it by hand after:
#     mount --rbind /dev /mnt/gentoo/dev ; mount -t proc none /mnt/gentoo/proc
#     mount -t sysfs none /mnt/gentoo/sys ; cp /etc/resolv.conf /mnt/gentoo/etc/
#     chroot /mnt/gentoo /bin/bash
#
# PREREQ: the chroot's native gcc must be openmp-capable, because crossdev's final
# ("canadian") gcc build probes for it. If you trimmed gcc with -openmp during the i686
# @system build (08-system's package.use), rebuild it in the chroot first:
#     echo 'sys-devel/gcc openmp' > /etc/portage/package.use/gcc-openmp
#     emerge -1 sys-devel/gcc
#
# WHY A CROSS-TOOLCHAIN: this is a 32-bit guest -- its kernel can't exec 64-bit ELF, so we
# can't natively build amd64 here. crossdev gives us x86_64-...-gcc (runs on i686, emits
# amd64) and, via cross-emerge, a native amd64 gcc INSIDE the sysroot -- the seed that lets
# the amd64 system self-host once it boots (11-amd64-kernel.sh).
#
# MERGED-USR: crossdev defaults the target to the `embedded` profile (split-usr, near-empty
# @system). We want the standard 23.0/musl profile, which is merged-usr and REFUSES to build
# into a split-usr root (its profile.bashrc dies). The 23.0 disk check is simply "is /bin a
# symlink?" -- so we pre-create a merged-usr symlink SKELETON in the (empty) sysroot before
# crossdev builds. Everything then installs into the merged layout automatically (a file
# written to /lib follows /lib->usr/lib into /usr/lib) with no file-moving and no self-loops.

target="${target:-x86_64-unknown-linux-musl}"
j="${j:-$(nproc)}"
sysroot="/usr/${target}"
overlay="/var/db/repos/crossdev"
profile="default/linux/amd64/23.0/musl"
prof_target="/var/db/repos/gentoo/profiles/$profile"

[ -d "$prof_target" ] || { echo "profile missing: $prof_target"; exit 1; }

# $sysroot must BE sda2 (the amd64 root), bound in by chroot-enter.sh, so the whole amd64
# build lands on sda2 and its baked distfiles are at $sysroot/var/cache/distfiles. If it's a
# plain dir instead (sda2 not bound), warn -- the build would go onto sda1 and miss the
# offline distfiles. NOT fatal: a no-distfiles/network dev run can still proceed.
if grep -q " $sysroot " /proc/mounts; then
    echo ">> $sysroot is a mount (sda2). distfiles: $(ls "$sysroot/var/cache/distfiles" 2>/dev/null | wc -l) files"
else
    echo ">> WARN: $sysroot is NOT a mount -- sda2 not bound in. The amd64 build will land on"
    echo ">>       sda1 and won't see the baked distfiles. Exit, run chroot-enter.sh (which"
    echo ">>       binds sda2), and re-enter -- OR proceed if you intend a non-sda2 dev build."
fi

# Activate the native gcc profile. sys-devel/gcc was emerged into /mnt/gentoo with ROOT=/mnt/gentoo
# (08-system), and the toolchain eclass runs gcc-config ONLY when ROOT=/ -- it won't configure a
# foreign root from the host. So the profile got REGISTERED (/etc/env.d/gcc/<tuple>-15 + the gcc-15
# symlink) but never ACTIVATED: no /usr/bin/gcc wrapper, "No gcc profile is active". Now that we're
# INSIDE that root, activate it -- crossdev's gcc rebuild below AND the bare `gcc` call in the libssp
# re-PIC need a working `gcc`. Profile 1 is the sole native toolchain here (crossdev hasn't added the
# cross ones yet). Idempotent. NOTE: we do NOT `source /etc/profile` after -- that resets PATH to
# base-files' merged-usr default and would undo the split-usr PATH from vars-x86.sh; the gcc wrapper
# lands in /usr/bin (already on PATH) either way.
gcc-config 1

#link to profile
ln -sfn /var/db/repos/gentoo/profiles/default/linux/x86/17.0/musl /etc/portage/make.profile

#force -split-usr
mkdir -p /etc/portage/profile /etc/portage/package.use
grep -qx -- '-split-usr' /etc/portage/profile/use.force 2>/dev/null || echo '-split-usr' >> /etc/portage/profile/use.force
echo '*/* -split-usr' > /etc/portage/package.use/bootstrap

# so that cross-x86_64-unknown-linux-musl/binutils builds
echo '*/* -debuginfod' >> /etc/portage/package.use/bootstrap

#build gcc with openmp
echo 'sys-devel/gcc openmp -fortran -nls' > /etc/portage/package.use/gcc

# PREREQ: the build tools gcc's rebuild needs (m4 + the @system bison/flex/gettext) must ALREADY
# be installed in /mnt/gentoo. m4/make/texinfo are BDEPEND-only (not @system), so 08-system's
# ROOT=/mnt/gentoo emerge left them on the live-bootstrap HOST only -- and building them HERE, in
# the chroot, fails on musl (gnulib fseeko/ftello "please port" + gettext's mbstate_t/mbrlen
# pointer-type error) even though they build cleanly on the live host. So install them into the
# target from OUTSIDE the chroot, BEFORE entering (built by the host's working toolchain):
#     ROOT=/mnt/gentoo emerge -1 sys-devel/m4 sys-devel/bison sys-devel/flex sys-devel/gettext
# With them present, the gcc rebuild below finds them satisfied and never tries to compile them in
# the chroot. (If it still pulls one, exit and run the line above for that atom.)

# Re-PIC the chroot's libssp_nonshared.a ONCE. musl's ebuild builds it non-PIC, and 07's re-PIC
# hook lives in the HOST's /etc/portage/bashrc -- the chroot's /etc/portage is separate and has no
# such hook, so /mnt/gentoo/usr/lib/libssp_nonshared.a is non-PIC. Linking it into a PIE object
# (gcc's OWN configure test -- which then misreports the TEXTREL as "Building GCC requires GMP" --
# or libstdc++.so during the rebuild) fails: "read-only segment has dynamic relocations". No
# post_pkg_postinst hook needed: musl is already emerged in /mnt/gentoo and nothing below
# reinstalls the host i686 musl (crossdev builds the amd64 TARGET musl, not this one). Same
# ssp-local.c recipe as 02-gcc/07, compiled IN PLACE in gcc/: ssp-local.c #includes "config.h", so
# we drop one (defining HAVE_HIDDEN_VISIBILITY) beside it, build, then remove the generated files.
sspsrc="$(cd "$(dirname "$0")" && pwd)/../gcc/ssp-local.c"
if [ -f "$sspsrc" ]; then
    work="$(dirname "$sspsrc")"        # bootstrap-amd64/gcc/ (holds ssp-local.c)
    printf '#define HAVE_HIDDEN_VISIBILITY 1\n' > "$work/config.h"
    gcc -fPIC -O2 -I"$work" -c "$sspsrc" -o "$work/ssp-local.o"
    nm "$work/ssp-local.o" | grep -q 'T __stack_chk_fail_local' \
        || { echo "09: ssp-local.o missing __stack_chk_fail_local"; exit 1; }
    for lib in /usr/lib/libssp_nonshared.a /usr/lib/i686-unknown-linux-musl/libssp_nonshared.a; do
        [ -e "$lib" ] || continue
        rm -f "$lib"; ar rcs "$lib" "$work/ssp-local.o"; echo "09: re-PIC'd $lib"
    done
    rm -f "$work/config.h" "$work/ssp-local.o"
else
    echo "09: WARNING: $sspsrc missing -- cannot re-PIC libssp_nonshared.a"
fi

# PLX ramdisk (part 1/2): the native gcc rebuild here AND crossdev's toolchain build below (binutils
# + stage1 gcc + musl + full gcc) are the HEAVIEST compiles in the whole cross stage, and they build
# in the CHROOT's /var/tmp/portage (PORTAGE_TMPDIR=/var/tmp, from the make.conf chroot-enter.sh
# copied) -- NOT the $sysroot tree. Mount a tmpfs there BEFORE they run. (Part 2/2 below covers the
# cross ${target}-emerges + 10/11 in $sysroot/var/tmp/portage.) No-op on small-RAM dev runs. The
# helper is sourced+exported by x86-gentoo.sh (like asuser); the guard lets a by-hand 09 run (where
# it isn't sourced) proceed disk-backed instead of erroring under set -e.
command -v plx_mount_portage_tmpfs >/dev/null && plx_mount_portage_tmpfs /var/tmp/portage

emerge -q1uN sys-devel/gcc

echo "== [1/5] crossdev tool + its overlay =="
# --noreplace: install sys-devel/crossdev if missing, else leave the installed one as-is.
emerge -q --noreplace sys-devel/crossdev
if [ ! -d "$overlay" ]; then
    install -d "$overlay/metadata" "$overlay/profiles"
    echo crossdev > "$overlay/profiles/repo_name"
    printf 'masters = gentoo\nthin-manifests = true\n' > "$overlay/metadata/layout.conf"
    mkdir -p /etc/portage/repos.conf
    cat > /etc/portage/repos.conf/crossdev.conf <<EOF
[crossdev]
location = $overlay
masters = gentoo
priority = 10
auto-sync = no
EOF
    echo "  created crossdev overlay at $overlay"
fi

echo "== [2/5] merged-usr skeleton on sda2 (the amd64 root; NO etc/ here -- see below) =="
# $sysroot IS sda2, MOUNTED here -- pre-populated by the live-bootstrap generator with the
# Gentoo distfiles at var/cache/distfiles. crossdev builds the toolchain into it; the skeleton's
# bin/lib symlinks coexist with var/cache/distfiles (different top-level dirs). MOUNT (never
# mkfs) sda2 at $sysroot -- reformatting would erase the baked distfiles.
#   TODO (amd64-stage rework): chroot-enter must bind the sda2-mounted sysroot into the chroot,
#   so $sysroot here (inside /mnt/gentoo) actually IS sda2. And switch_root'ing into the amd64
#   root becomes switch_root /dev/sda2.
# Pre-create the merged-usr symlinks so crossdev builds straight into the merged layout (the
# guard skips if already a symlink). For a clean REBUILD do NOT `rm -rf $sysroot` (erases the
# distfiles): `crossdev --clean $target`, then remove everything EXCEPT var/cache/distfiles.
#
# CRITICAL: do NOT create $sysroot/etc here. crossdev's emerge-wrapper writes the sysroot
# make.conf/profile (cross_wrap_etc) ONLY when ${SYSROOT}/etc does NOT already exist. If we
# pre-create etc/portage, it SKIPS that -> no make.conf -> ROOT unset -> ${target}-emerge
# dies "SYSROOT must be set to / when ROOT is /". So create ONLY bin/lib; the 23.0 profile is
# set in step [4], AFTER crossdev has generated etc/portage.
if [ ! -h "$sysroot/bin" ]; then
    mkdir -p "$sysroot/usr/bin" "$sysroot/usr/lib"
    ln -s usr/bin "$sysroot/bin"        # 23.0 disk check == "/bin is a symlink" -> merged
    ln -s usr/bin "$sysroot/sbin"       # (canonical 23.0: sbin merges into bin)
    ln -s usr/lib "$sysroot/lib"
    ln -s usr/lib "$sysroot/lib64"      # musl no-multilib: lib64 -> usr/lib
    ln -s bin     "$sysroot/usr/sbin"
    ln -s lib     "$sysroot/usr/lib64"
    echo "  created merged-usr skeleton (no etc/ -- crossdev generates it)"
fi

echo "== [3/5] crossdev --stable --target $target =="
# Builds the stack in order: binutils -> stage1 gcc -> linux-headers -> musl -> full gcc,
# installing into the merged skeleton. The -musl tuple selects musl automatically.
# --stable (-S): use STABLE versions and keyword-accept the cross packages as plain `amd64`
# rather than ~amd64 (crossdev otherwise writes ~${TARCH} into package.accept_keywords/cross-*).
# musl/binutils/gcc/linux-headers/gdb all have stable amd64 keywords, so this yields a fully
# stable cross toolchain -- matching the stable-only sysroot (ACCEPT_KEYWORDS="${ARCH}" in [1]).
# NB: --stable picks the newest STABLE gcc, which is older than the ~amd64 one.
crossdev --stable --target "$target"

echo "== [4/5] ensure sysroot config + re-assert 23.0 profile + populate =="
# crossdev --target should have generated $sysroot/etc/portage/{make.conf,profile/*} via
# emerge-wrapper. If make.conf is missing (e.g. a manual sysroot manipulation left etc/
# present, so cross_wrap_etc's `[[ ! -d $SYSROOT/etc ]]` gate skipped it), regenerate the
# FULL config with emerge-wrapper -- NOT a hand-written ROOT= line, which would miss
# CBUILD/ARCH/ELIBC/PKGDIR/etc. (emerge-wrapper skips if etc exists, so rm it first.) The
# generated make.conf sets ROOT=$sysroot, so ${target}-emerge's ROOT==SYSROOT (else it dies
# "SYSROOT must be set to / when ROOT is /").
if [ ! -f "$sysroot/etc/portage/make.conf" ]; then
    echo "  make.conf missing -- regenerating cross config via emerge-wrapper"
    rm -rf "$sysroot/etc"
    emerge-wrapper --target "$target" --init
fi
# emerge-wrapper/crossdev set make.profile -> embedded; re-point to the standard profile.
# The disk is already merged-usr (skeleton), so the 23.0 check passes.
ln -sfn "$prof_target" "$sysroot/etc/portage/make.profile"
case "$(readlink "$sysroot/etc/portage/make.profile")" in
    *embedded*|"") echo "profile not 23.0/musl -- aborting"; exit 1 ;;
esac
# Force STABLE keywords BEFORE 09's own target-emerges below. crossdev's make.conf template sets
# ACCEPT_KEYWORDS="${ARCH} ~${ARCH}" (accepts TESTING), and --stable only keyword-accepts the CROSS
# packages -- it does NOT touch this sysroot make.conf. So without this, the native sys-devel/gcc
# emerged below grabs the ~amd64 gcc (e.g. 16.x) while the crossdev cross-compiler is stable (e.g.
# 15.x): a canadian-cross build then compiles the newer gcc's libgcc/cpuinfo.c with the OLDER cross
# gcc, whose cpuid.h lacks the new CPUID macros -> "bit_AVX512BMM / bit_AMD_PREFETCHI /
# signature_HYGON_ebx undeclared". Dropping ~${ARCH} (portage expands ${ARCH}->amd64 at read time)
# makes the native gcc the SAME newest-stable version as the cross gcc, so their cpuid.h match.
# 10-amd64-portage re-asserts this; here is where it first matters (09 emerges gcc before 10 runs).
sed -i 's|^ACCEPT_KEYWORDS=.*|ACCEPT_KEYWORDS="${ARCH}"|' "$sysroot/etc/portage/make.conf"

# Disable debuginfod for the TARGET/sysroot too. The `*/* -debuginfod` at the top is the CHROOT's
# package.use (governs crossdev's CROSS binutils); the ${target}-emerge below builds the NATIVE amd64
# binutils using the SYSROOT config, which lacks it -> sys-devel/binutils[debuginfod] pulls
# dev-libs/elfutils[debuginfod] -> net-libs/libmicrohttpd, whose configure force-enables
# --enable-itc=eventfd but "assumes no" on the eventfd(2) probe when cross-compiled (can't RUN the
# test) -> "eventfd(2) is not usable" econf failure. NB: 10-amd64-portage APPENDS its cycle-breakers
# to this file (>>), so this -debuginfod line survives into 10's @system (keeps @system's native
# binutils off libmicrohttpd).
mkdir -p "$sysroot/etc/portage/package.use"
echo '*/* -debuginfod' > "$sysroot/etc/portage/package.use/bootstrap"

# PLX ramdisk (part 2/2): the cross ${target}-emerges below (attr, binutils, gcc) and 10's @system +
# 11's kernel build into the SYSROOT tree. Standardize it to ${ROOT}var/tmp (10 also asserts this;
# set it HERE so 09's target-emerges use it too), then mount a tmpfs OVER $sysroot/var/tmp/portage.
# Mounting over the build DIR (not pointing PORTAGE_TMPDIR at a tmpfs path) keeps the make.conf value
# correct for the booted amd64 system and leaves no build scratch on sda2. (helper sourced in part 1.)
sed -i 's|^PORTAGE_TMPDIR=.*|PORTAGE_TMPDIR=${ROOT}var/tmp/|' "$sysroot/etc/portage/make.conf"
grep -q '^PORTAGE_TMPDIR=' "$sysroot/etc/portage/make.conf" \
    || echo 'PORTAGE_TMPDIR=${ROOT}var/tmp/' >> "$sysroot/etc/portage/make.conf"
command -v plx_mount_portage_tmpfs >/dev/null && plx_mount_portage_tmpfs "$sysroot/var/tmp/portage"

# Pre-seed sys-apps/attr FIRST (oneshot, so it doesn't land in @world): something in the
# populate set's dep tree pulls sys-apps/acl, which needs attr's headers -- attr/error_context.h
# -- at BUILD time. In the -uDN run acl reached its compile before attr's headers were in place
# and died "attr/error_context.h does not exist". Merging attr to completion first removes the race.
"${target}-emerge" -1q sys-apps/attr
# ${target}-emerge sets ROOT=$sysroot: these install as amd64 binaries INTO the sysroot.
# NOTE: under 23.0/musl @system is the FULL ~40-pkg base -- we do NOT cross-emerge that
# (it's built NATIVELY on first boot by 12's local.d script, dodging the cross-compile pain).
# Cross-build ONLY the native amd64 binutils+gcc here: a real amd64 toolchain in the sysroot is
# the seed that lets the booted system self-host that first-boot @system.
"${target}-emerge" -quDN sys-devel/binutils sys-devel/gcc

echo "== [5/5] sanity (informational) =="
[ -h "$sysroot/bin" ] && echo "  merged-usr OK (/bin -> $(readlink "$sysroot/bin"))"
ldso="$(ls "$sysroot"/lib/ld-musl-x86_64.so.1 "$sysroot"/usr/lib/ld-musl-x86_64.so.1 2>/dev/null | head -1)"
[ -n "$ldso" ] && echo "  musl loader: $ldso"
tgcc="$(ls "$sysroot"/usr/bin/gcc 2>/dev/null | head -1)"
[ -n "$tgcc" ] && { echo -n "  native amd64 gcc: "; file -b "$tgcc"; }
echo
echo ">> merged-usr amd64 sysroot ready at $sysroot (profile: $profile)."
echo ">> Next: 10-amd64-portage.sh -> 11-amd64-kernel.sh (disk-boot kernel, no initramfs) -> 12-amd64-init.sh."

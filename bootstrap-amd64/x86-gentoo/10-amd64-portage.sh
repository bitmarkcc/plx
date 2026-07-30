set -e

# Cross-emerge the PORTAGE RUNTIME SET into the amd64 sysroot (/usr/${target}), so the
# booted amd64 system can run `emerge` NATIVELY. This is Route B: cross-build only the
# minimum needed to RUN emerge, then (once the amd64 disk boots -- 11 builds the kernel, 12
# sets up init+GRUB, then reboot) build the real base with a NATIVE `emerge -e @system` --
# native builds sidestep the cross-compile quirks (especially python) of cross-emerging a whole @system.
#
# CONTEXT: runs INSIDE the /mnt/gentoo chroot, AFTER 09-crossdev.sh (needs the cross
# toolchain + sysroot). Not driven by x86-bash.sh; run by hand.
#
# NB: unlike the i686 bridge (07-portage), there is NO portage-tarball hack here -- that
# only existed because live-bootstrap shipped zero emerge. crossdev gives us a real
# `${target}-emerge sys-apps/portage`, which installs portage + pulls dev-lang/python as
# proper amd64 packages into the sysroot.

target="${target:-x86_64-unknown-linux-musl}"
j="${j:-$(nproc)}"
sysroot="/usr/${target}"
profile="default/linux/amd64/23.0/musl"

command -v "${target}-emerge" >/dev/null 2>&1 || { echo "no ${target}-emerge -- run 09-crossdev.sh first"; exit 1; }

echo "== [1/4] point the target at a STANDARD profile ($profile) =="
# crossdev defaults the target to the `embedded` profile, whose @system is nearly empty
# (that's why a cross `emerge @system` pulled only busybox). For a real amd64 musl system
# use 23.0/musl: the modern profile, merged-usr by default (matches our layout -- no
# split-usr dance) = 23.0 base + arch/amd64/no-multilib + features/musl.
prof_target="/var/db/repos/gentoo/profiles/$profile"
[ -d "$prof_target" ] || { echo "profile missing: $prof_target"; exit 1; }
ln -sfn "$prof_target" "$sysroot/etc/portage/make.profile"
echo "  make.profile -> $(readlink "$sysroot/etc/portage/make.profile")"
case "$(readlink "$sysroot/etc/portage/make.profile")" in
    *embedded*) echo "still pointing at embedded -- aborting"; exit 1 ;;
esac

# STABLE keywords are already enforced in 09-crossdev (it drops crossdev's ~${ARCH} from the sysroot
# make.conf -> ACCEPT_KEYWORDS="${ARCH}"), done there because 09 emerges gcc BEFORE this script runs.
# Consequence to know here: packages that are ~amd64-only (common on musl) show as "masked by:
# ~amd64 keyword" -- unmask those selectively, e.g.
# `echo 'net-misc/rsync ~amd64' >> "$sysroot/etc/portage/package.accept_keywords"`. This make.conf
# also becomes sda2's /etc/portage, so the booted amd64 system stays stable-by-default too.
if [ -f "$sysroot/etc/portage/make.conf" ]; then
    # crossdev's template puts the build tree at ${ROOT}tmp/ (=> /tmp after de-cross). Move it to
    # the standard ${ROOT}var/tmp/ (=> /var/tmp) -- avoids /tmp sticky-dir quirks, stays isolated in
    # the sysroot while cross ($sysroot/var/tmp). No crossdev flag for this, so we sed it.
    sed -i 's|^PORTAGE_TMPDIR=.*|PORTAGE_TMPDIR=${ROOT}var/tmp/|' "$sysroot/etc/portage/make.conf"
fi
echo "  ACCEPT_KEYWORDS -> $(grep '^ACCEPT_KEYWORDS=' "$sysroot/etc/portage/make.conf" 2>/dev/null)  (set in 09)"
echo "  PORTAGE_TMPDIR  -> $(grep '^PORTAGE_TMPDIR=' "$sysroot/etc/portage/make.conf" 2>/dev/null)"

echo "== [2/4] bootstrap USE cycle-breakers -> $sysroot/etc/portage/package.use/bootstrap =="
# Building a base from a near-empty sysroot re-creates the SAME dependency-graph cycles the
# i686 @system hit (08-system) -- same musl profile family, same offenders. Written into the
# TARGET config root. TEMPORARY: after the native `emerge -e @system` on-target, drop this
# and rebuild the affected pkgs with full USE. EXPECT TO ITERATE: if emerge reports a NEW
# circular dep, add its suggested toggle here. (No split-usr line: 23.0 is merged-usr.)
mkdir -p "$sysroot/etc/portage/package.use"
cat >> "$sysroot/etc/portage/package.use/bootstrap" <<'EOF'
*/* -nls                            # attr <-> gettext (and the nls/gettext cycles)
                                    #   that still runs emerge (catalyst stage1 uses this).
                                    #   The native emerge -e @system rebuilds it in full.
sys-apps/util-linux -su -pam        # pam <-> docbook <-> util-linux (if pulled as a dep)
app-alternatives/awk -gawk mawk     # gawk <-> bison cycle: point awk at mawk for the seed
sys-apps/portage -rsync-verify      # rsync-verify -> gemato[gpg] -> requests ->
                                    #   charset-normalizer -> dev-python/mypy, which is
                                    #   package.mask'd (it now needs NIH Rust pkgs). We don't
                                    #   need GPG tree verification for a seed; this cuts the
                                    #   whole chain. Re-enable on the real system if wanted.
EOF

# net-misc/rsync (pulled by sys-apps/portage for `emerge --sync`) fails to cross-compile on
# amd64-musl: its x86_64 SIMD checksum (simd-checksum-x86_64.cpp) uses GCC target-multiversioning,
# which needs GNU IFUNC -- unsupported on musl ("multiversioning needs 'ifunc' ..."). There is no
# simd USE flag, but the ebuild uses econf, so pass --disable-roll-simd via EXTRA_ECONF. Written
# into the TARGET config so it ALSO applies to the native emerge -e @system after boot -- amd64-
# musl can't do IFUNC multiversioning natively either, so rsync's x86_64 SIMD fails the same way.
mkdir -p "$sysroot/etc/portage/env"
echo 'EXTRA_ECONF="--disable-roll-simd"' > "$sysroot/etc/portage/env/nosimd"
grep -q '^net-misc/rsync nosimd' "$sysroot/etc/portage/package.env" 2>/dev/null || \
    echo 'net-misc/rsync nosimd' >> "$sysroot/etc/portage/package.env"

echo "== [3/4] cross-emerge the portage runtime into $sysroot =="
# The minimum to RUN emerge on-target: portage (+ its python dep), a shell, the coreutils/
# text tools ebuilds invoke, the archivers portage unpacks with, make/patch for builds, and
# gentoo-functions (ebuild helper). net-misc/wget is portage's default fetcher -- it drags
# in a TLS lib (openssl); if that cross-build fights us, drop wget and instead set curl as
# FETCHCOMMAND on-target (the guest already uses curl). NOTE distfiles are arch-independent,
# so the amd64 build can REUSE /var/cache/distfiles already populated on sda1 by the i686
# @system -- bind-mount it into the amd64 root post-boot to cut fetching.
#not used for now (instead emerging @system)
runtime="sys-apps/portage \
         app-shells/bash \
         sys-apps/coreutils sys-apps/findutils sys-apps/sed sys-apps/grep \
         app-alternatives/awk \
         sys-devel/make sys-devel/patch \
         app-arch/tar app-arch/gzip app-arch/bzip2 app-arch/xz-utils app-arch/zstd \
         sys-apps/gentoo-functions \
         net-misc/wget"
set +e   # --keep-going returns non-zero on partial failure; report, don't abort
"${target}-emerge" -quDN --keep-going @system
rc=$?
set -e
echo ">> runtime emerge exit=$rc  (non-zero is normal with --keep-going if some pkgs failed)"

echo "== [4/4] sanity: key runtime binaries present + amd64 (informational) =="
# Static inspection only -- we CAN'T run the amd64 emerge here (32-bit kernel). Running it
# natively happens after the amd64 disk boots (11 kernel + 12 init/GRUB, then reboot).
for rel in usr/bin/emerge usr/bin/python3 usr/bin/make bin/bash usr/bin/bash \
           bin/tar usr/bin/tar usr/bin/wget; do
    f="$(ls "$sysroot/$rel" 2>/dev/null | head -1)"
    [ -n "$f" ] && { echo -n "  $rel: "; file -b "$f" 2>/dev/null | cut -c1-60; }
done
echo
echo ">> portage runtime staged in $sysroot."
echo ">> Next: 11-amd64-kernel.sh (kernel) -> 12-amd64-init.sh (init+GRUB) -> reboot -> native emerge -e @system."

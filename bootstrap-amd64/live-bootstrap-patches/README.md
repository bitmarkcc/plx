# live-bootstrap patches (PLX)

Patches PLX applies to a fresh `~/git/live-bootstrap` checkout. Kept here so the
modifications are tracked in PLX and survive re-cloning/updating live-bootstrap.

Apply into the live-bootstrap tree:

```sh
cd ~/git/live-bootstrap
git apply ~/git/plx/bootstrap-amd64/live-bootstrap-patches/*.patch
```

## 0001-move_disk-two-partitions.patch

`steps/jump/move_disk.sh` — split the guest disk into **two** partitions instead of one:

- **sda1**: start sector 2097152 (1 GiB), size 60817408 sectors (**29 GiB**) — the *exact*
  extent of the original single-partition layout, so the i686 bootstrap is unaffected.
- **sda2**: start sector 62914560 (the old 30 GiB disk end), size = **rest of the disk** —
  reserved for the PLX **amd64 root** filesystem (unformatted here; the amd64 stage does
  `mkfs.ext4 /dev/sda2`, mounts it at `/usr/x86_64-unknown-linux-musl` before crossdev, and
  `switch_root`s into it at the end).

Requires a disk larger than 30 GiB. `run-qemu.sh` now defaults `DISK=64G` (→ sda2 ≈ 34 GiB).
Sizing rule: p1 + 1 GiB front = 30 GiB, so **sda2 = DISK − 30 GiB**.

## 0002-generator-sda2-payload.patch

`lib/generator.py` — pre-populate **sda2 (the amd64 root)** as a ready-made ext4 filesystem so
the bootstrap is fully self-contained (no host, no network — as on the real KGPE-D16),
**without** routing anything through builder-hex0's `srcfs`.

> **Why not the srcfs?** An earlier version baked the distfiles into the srcfs; builder-hex0
> **stage2** (bare-metal hex0) then extracted them into a fixed **~1744 MB** file-memory region,
> which crawled all night on 1.5 G and would eventually overflow. The srcfs is the wrong channel
> for GB-scale data — it's fine only for live-bootstrap's small seed sources.

New method `write_plx_sda2()` writes a ready-made **ext4 filesystem** directly into sda2's region
via `mkfs.ext4 -E offset=<sda2 start>` (sector **62914560** = 30 GiB — must match `move_disk.sh`),
populated with:

| env var | → on sda2 | contents |
|---|---|---|
| `PLX_DISTFILES` | `/var/cache/distfiles/` | Gentoo `@system` source tarballs |
| `PLX_SCRIPTS`   | `/root/tmp/bootstrap-amd64/` | the PLX bootstrap scripts (minus their own `distfiles/`) |
| `PLX_SNAPSHOT`  | `/root/tmp/<basename>` | the Gentoo ebuild repo snapshot |
| `PLX_LB_DISTFILES` | `/lb-distfiles/` | live-bootstrap's OWN source tarballs — for a one-disk offline build (`OFFLINE=1`); the `0003` patch bind-mounts these onto `/external/distfiles` so live-bootstrap fetches nothing. Set to `$LB_DIR/distfiles` by `run-qemu.sh` under `OFFLINE=1`, else empty (skipped). |

Any unset/missing var is skipped; nothing to write ⇒ no-op. ext4 features newer than
live-bootstrap's ~4.14 kernel are disabled (`^orphan_file,^metadata_csum_seed`) since that kernel
also mounts sda2 in the i686 stage. stage2 never sees any of it.

**Host prerequisite — `fakeroot`:** the generator runs *unprivileged* (as the host user), but
`mkfs.ext4 -d` preserves the staging tree's uid/gid — so the baked `/var`, `/root`, … would
otherwise come out owned by the **host UID** instead of root, and systemd-tmpfiles' "unsafe path
transition" guard then fails on the amd64 system's first boot. So the `chown -R 0:0` + `mkfs.ext4
-d` run under **`fakeroot`** (fakes root ownership ⇒ root-owned dirs baked in). Install it
(`emerge sys-apps/fakeroot`); without it on `$PATH`, `run-qemu.sh` fails loudly with
`FileNotFoundError: 'fakeroot'`.

Wiring:
- `run-qemu.sh` exports all three vars (defaults under `~/git/plx/`).
- `move_disk.sh` (patch 0001) defines the sda2 partition at that offset and **does not mkfs it**
  (sfdisk only writes the sector-0 table; the baked ext4 survives).
- **Manual pre-`x86.sh` step** (in the booted guest, before running the i686 stage): sda2 is
  ALREADY mounted at `/mnt/amd64` (the `0003` `get_network.sh` patch mounts it there during
  live-bootstrap), so you only point `/root/tmp` at it —
  `rm -rf /root/tmp; ln -s /mnt/amd64/root/tmp /root/tmp`.
  With sda2 mounted, `x86/03-find.sh` symlinks the default `DISTDIR` (`/var/cache/distfiles`) →
  `sda2:/var/cache/distfiles` (it keys off `/mnt/amd64/var/cache/distfiles` existing; `04`/`05`/`07`/`08`
  use it). The `/root/tmp` link makes `07`'s snapshot (`/root/tmp/gentoo-*.tar.xz`) + the baked scripts
  reachable. (`03-find.sh` only does the `DISTDIR` symlink — it does not mount sda2 itself; and you no
  longer mount it by hand either, since `get_network` did.)
- `chroot-enter.sh` binds sda2 (from `/mnt/amd64`) to `/mnt/gentoo/usr/x86_64-unknown-linux-musl`
  so `09-crossdev`'s `$sysroot` is sda2. `09` MOUNTs (never mkfs/`rm -rf`) sda2; `11`'s `/init`
  mounts `/dev/sda2` directly.
- **amd64 self-boot (done, via GRUB — not kexec/`switch_root`):** `11-amd64-kernel.sh` cross-builds
  `sys-kernel/gentoo-kernel` with AHCI/EXT4 built in, so `root=/dev/sda2` mounts directly — no
  initramfs, no `switch_root`. `12-amd64-init.sh` installs sysvinit+openrc, writes `/etc/fstab` + a
  preseeded root password + a first-boot `emerge @system` script, and installs GRUB (i386-pc/BIOS)
  on the disk. Boot path: GRUB → kernel → openrc → first-boot `@system` on the **VGA** console
  (`console=tty0`, getty on `tty1`) → login. `13-reboot.sh` (SysRq) reboots the i686 guest into it.

## 0003-get-network-offline.patch

`steps/improve/get_network.sh` — two changes that make a fully **OFFLINE** run
(`OFFLINE=1 ./run-qemu.sh`, which adds QEMU SLIRP `restrict=on`) work on a **single disk**.

`get_network.sh` runs right after `curl` is built and right before the first *network*-era package
(`bash-5.2.15`) — live-bootstrap genuinely fetches its late sources in-guest from the host mirror
over the NAT (early sources are baked; late ones are not). Under `restrict` that fetch fails, so:

1. **Local sources (the real fix).** Just before `dhcpcd`, mount sda2 (the amd64 root) at
   `/mnt/amd64` and, if it carries the baked live-bootstrap distfiles (`sda2:/lb-distfiles`, from
   `PLX_LB_DISTFILES` — see `0002`), **bind-mount them onto `/external/distfiles`**. Then
   `download_source_line`'s `[ -e $fname ]` guard finds every source locally and never fetches — all
   on one disk (no separate `--external-sources` disk, no `parted`). This mount is **reused by the
   PLX amd64 stage** (`x86.sh` no longer mounts sda2 itself). Skips cleanly on a normal online build
   (no `/lb-distfiles`), so the fetches then run for real.
2. **Non-fatal connectivity check.** The step still loops on `curl example.com` ("ensure network
   accessible") and originally ran `false` on a 120 s timeout, dropping to the debug trap. Under
   `restrict` that check can never pass, so `false` → `break`: online runs pass instantly, an offline
   run continues after the wait.

Only needed for `OFFLINE=1`. Without change (2), `OFFLINE=1` hangs at *"Timeout reached for internet
to become accessible"*; without change (1), it then panics (`bash-5.2.15.tar.gz does not exist!`)
when the first real fetch fails. The Gentoo `@system` stage is offline-capable independently, as
long as `PLX_DISTFILES` holds the full distfile set.

## 0004-after-plx-autorun.patch

New file `steps/after/plx-bootstrap.sh` — auto-run the **whole** amd64 bootstrap, hands-off, when
live-bootstrap finishes.

live-bootstrap's last step, `improve/after.sh`, runs every `/steps/after/*.sh` **before** it drops to
the interactive shell — its official post-bootstrap hook. This launcher uses it: sda2 is already
mounted at `/mnt/amd64` (patch `0003`), so it sets `HOME=/root`, points `/root/tmp` at sda2, and runs
the full chain unattended —
`x86.sh` (i686 `@system`, `01`–`08`) → `chroot-enter.sh 'bash x86-gentoo.sh'` (amd64 cross, `09`–`12`)
→ `13-reboot.sh`. On success it reboots into the amd64 disk (GRUB → kernel → first-boot `@system` →
login). If **any** stage fails it does **not** reboot — it returns, and `after.sh` opens the shell so
you can debug (both `x86.sh` and `x86-gentoo.sh` run under `set -e`, so a hard failure exits non-zero).

This relies on PLX's `chroot-enter.sh` supporting a **non-interactive mode**: with an argument it runs
that command in the chroot instead of dropping to a login shell.

Self-gating: exits immediately if the PLX scripts aren't baked (a plain live-bootstrap run is
unaffected), and honours an opt-out marker — `touch /mnt/amd64/.plx-no-autorun` to bake in "drop me
straight to the shell instead".

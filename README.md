# PLX

This is a continuation of Pirate Linux (https://gitub.com/piratelinux/Pirate-Linux) by the same developer. Yes, 10 years later. piratelinux.org is no longer under my control. It is a fake site that redirects to ad/referral schemes. The original github account, piratelinux, is also not under my control (lost password).

Currently designed only for Raspberry Pi, this first release _automatically_ builds a standard Gentoo desktop system, with some modifications:
- Default console font is large and readable on high definition monitors
- An initramfs with a musl-built busybox is used to check the root filesystem before booting it
- A guest user is created (added to some common groups) that auto starts on tty1 and boots openbox with an xterm with some design modifications for look and usability.
- No mouse support is built in. You can use the keypad mouse by pressing SHIFT+NUMLOCK.
- The openrc-shutdowntime file used by swclock is "touched" every minute to ensure that the clock is always monotonic.
- CUPS is configured for easy printing (this needs more testing)
- SSHD disallows password logins. The config is setup so that you must login with your SSH key.
- WiFi is not enabled. You can optionally add it by installing the needed firmware.
- As you can see in the world file, some noteworthy packages include gimp, zbar, cryptsetup, tor, bitcoin-core, openvpn, amule, irssi (with otr), transmission, and our custom program, cwallet (a tool for viewing wallet keys and managing/creating a paper wallet).

# Automatically

By automatically, we mean fully automated. Once you power on the Raspberry Pi with the sdcard containing the disk image, the system starts building itself completely from source, and no Internet access needed. Of course, it may take a few days for the Raspberry Pi to complete the installation...For now we rely on the stage3 binaries, however, in a future release we plan to bootstrap the tarball through a more trustless method.

# Prerequisites

- Standard Linux toolset (binutils), xz, tar, mount, umount, ...
- chroot (and root access)
- parted
- cpio
- Internet connection with /etc/resolv.conf available (to downloaded sources)
- sudo
- mkfs.ext4, mkfs.vfat
- bash
- curl

# Installation

`sudo ./build.sh`
`dd if=plx<random>.img of=/dev/sdx bs=1M status=progress`

# More details:

# build.sh
This is the main script that builds the system. You can easily configure some basic variables/parameters at the top. Run it as root (`sudo ./build.sh`). The parts that don't need root privileges will be run as the regular user. The first argument is the number of parallel jobs (`nproc` by default).

# install.sh
This is meant to run inside the target system. You can also run this in a chroot. If you do so, you should set installinchroot=1 (in build.sh).

# init.sh
This runs inside the initramfs (before mounting the root filesystem).

# ssh access
For ssh access, add your id_rsa.pub to the root directory when building.

# root password
The root password is the name of the generated image file, of the form `plx<random>.img` where `<random>` is an 8 character random base64 string (alphanum + `_-+`).

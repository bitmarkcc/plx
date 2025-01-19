# PLX

This is a continuation of Pirate Linux (https://gitub.com/piratelinux/Pirate-Linux) by the same developer. Yes, 10 years later. piratelinux.org is no longer under my control. It is a fake site that redirects to ad/referral schemes. The original github account, piratelinux, is also not under my control (lost password).

Currently designed only for Raspberry Pi, this first release _automatically_ builds a standard Gentoo desktop system, with some modifications:
- Default console font is large and readable on high definition monitors
- An initramfs with a musl-built busybox is used to check the root filesystem before booting it
- A guest user is created (added to some common groups) that auto logs into tty2 and from there you can startx (openbox) and you have an xterm with some design modifications for look and usability.
- You can use the keypad mouse by pressing SHIFT+NUMLOCK. To make the xterm full screen, press ALT+ENTER.
- The openrc-shutdowntime file used by swclock is "touched" every minute to ensure that the clock is always monotonic.
- CUPS is configured for easy printing (this needs more testing)
- SSHD disallows password logins. The config is setup so that you must login with your SSH key.
- WiFi is not enabled. You can optionally add it by installing the needed firmware.
- As you can see in the world file, some noteworthy packages include zbar, cryptsetup, tor, bitcoin-core, openvpn, amule, irssi (with otr), transmission, and our custom program, cwallet (a tool for viewing wallet keys and managing/creating a paper wallet).
- As you can see in portage/make.conf, urandom USE flag is disabled as are various graphical interfaces (some programs of course have the graphical interfaces' USE flags enabled).
- The web browser (firefox) is available as a pre-compiled package that runs in a sandbox (bubblewrap).

# Automatically

By automatically, we mean fully automated. Once you power on the Raspberry Pi with the SD card containing the disk image, the system starts building itself completely from source, and no Internet access needed. It should take about 1 day for the Raspberry Pi to complete the installation. For now we rely on the stage3 binaries, however, in a future release we plan to bootstrap the tarball through a more trustless method.

# Prerequisites

- Standard Linux toolset, core utils, C compiler, xz, tar, mount, umount, ...
- chroot (and root access)
- parted
- cpio
- Internet connection with /etc/resolv.conf available (to downloaded sources)
- sudo
- mkfs.ext4, mkfs.vfat
- bash
- curl
- \>= 128 GiB micro-SD card (initially 8 GiB is written, but more partitions are added later)

# Installation

`sudo ./build.sh` (or download an image from plx.im/downloads)

`dd if=plx<random>.img of=/dev/sdx bs=1M status=progress`

# build.sh
This is the main script that builds the system. You can easily configure some basic variables/parameters at the top. Run it as root (`sudo ./build.sh`). The parts that don't need root privileges will be run as the regular user. The first argument is the number of parallel jobs (`nproc` by default).

# install.sh
This is meant to run inside the target system. You can also run this in a chroot. If you do so, you should set installinchroot=1 (in build.sh).

# init.sh
This runs inside the initramfs (before mounting the root filesystem).

# ssh access
For ssh access, add your id_rsa.pub to the root directory when building. The IP address of the machine is set to 192.168.6.66.

# root password
The root password is the name of the generated image file, of the form `plx<random>.img` where `<random>` is an 8 character random base64 string (alphanum and `_-+`).

# sandbox
To build the packages that are meant to run in a glibc sandbox, see the function `build_unsafe_packages` in build.sh. The configuration for this build process is in the `unsafe` directory. You can start the default program firefox by running `firefox` from the xterm. The executable is actually a shell script that executes firefox with the `bwrap` command, that binds the necessary directories and environment variables.

# rootcode
At the end of the installation process, a 3 character code is randomly generated and added to the command prompt for the root user ($PS1 variable). This code is meant as a way to verify that the root shell is authentic and not spoofed by some unprivileged process.

# screen lock
To lock the screen simply run `lock` in an xterm or `vlock -a` in TTY/console. `lock` is an alias using a combination of `slock` and `physlock`. The monitor should automatically turn off with the `lock` command, and after 10 minutes with the `vlock -a` command. The magic sysrq key is disabled in this kernel.

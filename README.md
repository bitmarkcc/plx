# PLX

This is a continuation of Pirate Linux (https://gitub.com/piratelinux/Pirate-Linux) by the same developer. Yes, 10 years later. piratelinux.org is no longer under my control. It is a fake site that redirects to ad/referral schemes. The original github account, piratelinux, is also not under my control (lost password).

Currently designed only for Raspberry Pi. This first commit only builds a 'vanilla' Gentoo desktop system. Extra packages are coming soon.

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

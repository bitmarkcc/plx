# PLX

This is a continuation of Pirate Linux (https://gitub.com/piratelinux/Pirate-Linux) by the same developer. Yes, 10 years later. piratelinux.org is no longer under my control. It is a fake site that redirects to ad/referral schemes. The original github account, piratelinux, is also not under my control (lost password).

Currently designed only for Raspberry Pi. This first commit only builds a 'vanilla' Gentoo desktop system. Extra packages are coming soon.

# build.sh
This is the main script that builds the system. You can easily configure some basic variables/parameters at the top. Run it as root (sudo ./build.sh). The parts that don't need root privileges will be run as the regular user.

# install.sh
This is meant to run inside the target system. You can also run this in a chroot. If you do so, you should set installinchroot=1 (in build.sh).

# init.sh
This runs inside the initramfs (before mounting the root filesystem)

set -e

cd /etc/portage/profile
sed -i '/^sys-libs\/ncurses/d' package.provided
cd

FEATURES="-protect-owned" emerge -qu --exclude "sys-devel/gcc sys-apps/busybox" @system

cd /etc/portage
rm make.profile
ln -s ../../usr/portage/profiles/default/linux/arm64/17.0/musl make.profile

FEATURES="-protect-owned" emerge -qu --exclude "sys-devel/gcc" @system

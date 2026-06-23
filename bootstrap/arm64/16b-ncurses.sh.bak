set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/ncurses-6.1.tar.gz
cd ncurses-6.1
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
echo "sys-libs/ncurses-6.1" >> /etc/portage/profile/package.provided

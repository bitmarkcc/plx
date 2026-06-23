set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/perl-5.24.3.tar.xz
cd perl-5.24.3
asuser sh Configure -Dprefix=/usr -de
asuser make -j$j
make install
echo "dev-lang/perl-5.24.3" >> /etc/portage/profile/package.provided

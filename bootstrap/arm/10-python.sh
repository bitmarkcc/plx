set -e

cd /home/worker/bld
asuser tar -xf /usr/portage/distfiles/Python-3.7.10.tar.xz
cd Python-3.7.10
asuser ./configure $obuild $oprefix
asuser make -j$j
make install
cd /usr/bin
ln -s python3 python

set -e

cd
emerge -qDN sys-devel/gcc
sed -i 's/ -fPIC//' /etc/portage/make.conf
cd /usr/bin
ln -s /usr/armv7a-unknown-linux-uclibceabihf/binutils-bin/2.30/ar ar
ln -s /usr/armv7a-unknown-linux-uclibceabihf/binutils-bin/2.30/nm nm
ln -s /usr/armv7a-unknown-linux-uclibceabihf/binutils-bin/2.30/ranlib ranlib

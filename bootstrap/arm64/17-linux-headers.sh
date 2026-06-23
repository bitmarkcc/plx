set -e

cd /etc/portage/profile
sed -i '/^dev-lang\/perl/d' package.provided
sed -i '/^app-arch\/xz-utils/d' package.provided
#sed -i '/^sys-kernel\/linux-headers/d' package.provided
cd

FEATURES="-protect-owned" emerge -quDN --exclude "sys-devel/gcc" sys-kernel/linux-headers

cd /usr/bin
rm python python3
ln -s python3.7 python3
ln -s python3 python

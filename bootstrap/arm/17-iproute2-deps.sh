set -e

cd /etc/portage/profile
sed -i '/^dev-lang\/perl/d' package.provided
sed -i '/^app-arch\/xz-utils/d' package.provided
cd

emerge -quDN net-libs/libmnl net-firewall/iptables app-arch/xz-utils virtual/pkgconfig sys-devel/bison sys-devel/flex sys-kernel/linux-headers

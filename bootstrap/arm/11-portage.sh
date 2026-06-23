set -e

cd
echo "Extracting gentoo snapshot ..."
tar -xpf /root/tmp/gentoo-2018.tar.xz -C /usr/
echo "Extracted gentoo snapshot"
cd /usr
mv portage/distfiles gentoo-2018/
rmdir portage
mv gentoo-2018 portage
chown -R portage:portage portage
cd /root
tar -xf /usr/portage/distfiles/portage-2.3.49.tar.bz2

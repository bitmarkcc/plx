set -e

cd /etc/portage
sed -i 's/^PYTHON_TARGETS=.*$/PYTHON_TARGETS="python3_10"/' make.conf
echo 'sys-apps/systemd-utils -udev' >> package.use/plx
echo 'sys-apps/util-linux pam' >> package.use/plx
echo 'sys-libs/libxcrypt ~arm64' >> package.accept_keywords/plx

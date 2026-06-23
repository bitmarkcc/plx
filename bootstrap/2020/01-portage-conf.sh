set -e

cd /etc/portage
sed -i 's/^PYTHON_TARGETS=.*$/PYTHON_TARGETS="python3_8"/' make.conf

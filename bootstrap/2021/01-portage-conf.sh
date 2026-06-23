set -e

cd /etc/portage
sed -i 's/ -openmp//' make.conf
sed -i 's/^PYTHON_TARGETS=.*$/PYTHON_TARGETS="python3_9"/' make.conf
echo '>=dev-lang/perl-5.34.0' >> package.mask/plx
echo '=virtual/perl-Data-Dumper-2.179.0' >> package.mask/plx
echo '=virtual/perl-Test-Harness-3.430.0' >> package.mask/plx

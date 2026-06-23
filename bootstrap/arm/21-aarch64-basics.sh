set -e

target=aarch64-unknown-linux-musl

cd /usr/$target/etc/portage
echo 'PYTHON_TARGETS="python3_6"' >> make.conf
mkdir -p package.use
echo "sys-devel/gcc -* cxx pch openmp pie ssp" >> package.use/plx
cd
$target-emerge -quDN sys-devel/binutils sys-devel/gcc

cd /usr/$target/etc/portage
cp /etc/portage/make.conf ./
sed -i 's/armv7a/aarch64/' make.conf
sed -i 's/uclibceabihf/musl/' make.conf
sed -i '/^USE="bindist"/d' make.conf
echo 'USE="-readline -pam -nls -clang -llvm -openmp"' >> make.conf
echo 'ARCH=arm64' >> make.conf
echo 'ELIBC="musl"' >> make.conf
echo 'ACCEPT_KEYWORDS="arm64"' >> make.conf
mkdir -p package.accept_keywords
echo 'sys-kernel/linux-headers ~arm64' >> package.accept_keywords/plx
echo 'sys-libs/musl ~arm64' >> package.accept_keywords/plx
echo 'sys-apps/sandbox ~arm64' >> package.accept_keywords/plx
echo 'sys-libs/ncurses ~arm64' >> package.accept_keywords/plx
echo 'net-libs/libtirpc ~arm64' >> package.accept_keywords/plx
echo 'sys-apps/attr ~arm64' >> package.accept_keywords/plx
echo 'app-crypt/gnupg ssl' >> package.use/plx
echo 'dev-lang/python -ncurses' >> package.use/plx
echo 'app-shells/bash readline' >> package.use/plx
#mkdir -p profile
#echo 'sys-kernel/linux-headers-5.3' >> profile/package.provided

mkdir -p package.mask
echo '=sys-libs/musl-1.1.23' >> package.mask/plx

cd /usr/$target
mkdir -p proc sys dev run root usr/portage/distfiles var/cache/distfiles bin
mv /root/tmp root/
head -n 2 /etc/passwd >> etc/passwd
head -n 2 /etc/group >> etc/group

cd lib
rm ld-musl-aarch64.so.1
ln -s ../usr/lib/libc.so ld-musl-aarch64.so.1
cd ../usr/bin
rm ldd
ln ../../lib/ld-musl-aarch64.so.1 -s ldd
ln -s $target-ar ar
ln -s $target-nm nm
ln -s $target-ranlib ranlib
ln -s ../$target/bin/ar $target-ar
ln -s ../$target/bin/nm $target-nm
ln -s ../$target/bin/ranlib $target-ranlib

cd /usr/$target
cp /home/worker/bld/busybox-1.29.0/busybox bin/
sed -i 's/stage=1/stage=2/' root/tmp/init.sh
cp root/tmp/init.sh sbin/init
mv /usr/portage/distfiles/* usr/portage/distfiles/
mv /var/cache/distfiles/* var/cache/distfiles/
cp /etc/hostname etc/
cp /etc/fstab etc/
cp /etc/inittab etc/
cp -r /etc/local.d etc/
if [ -e /root/.ssh ]
then
    cp -r /root/.ssh root/
fi
mkdir -p usr/local/bin
cp /usr/local/bin/* usr/local/bin/
mkdir -p var/lib/portage
cp /var/lib/portage/* var/lib/portage/
mv /lib/modules lib/

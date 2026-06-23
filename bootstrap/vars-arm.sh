obuild="--build=arm-unknown-linux-uclibc"
oprefix="--prefix=/usr"
workerbuilddir="/home/worker/bld"
portagebin="/root/portage-2.3.49/bin"
PATH="$PATH:$portagebin"
j=$(nproc)

asuser() {
    su -c "cd $(pwd) && $*" - worker
}

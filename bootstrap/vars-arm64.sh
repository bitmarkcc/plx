obuild="--build=aarch64-unknown-linux-musl"
oprefix="--prefix=/usr"
workerbuilddir="/home/worker/bld"
portagebin="/root/portage-2.3.49/bin"
PATH="/usr/sbin:/usr/bin:/sbin:/bin:$portagebin"
HOME="/root"
j=$(nproc)

asuser() {
    su -c "cd $(pwd) && $*" - worker
}

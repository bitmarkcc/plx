obuild="--build=i686-unknown-linux-musl"
oprefix="--prefix=/usr"
workerbuilddir="/home/worker/bld"
portagebin="/root/tmp/portage-3.0.79/bin"
PATH="$PATH:$portagebin"
target="x86_64-unknown-linux-musl"
j=$(nproc)

asuser() {
    su -c "cd $(pwd) && $*" - worker
}

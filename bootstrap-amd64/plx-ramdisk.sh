# plx-ramdisk.sh -- mount a tmpfs OVER portage's build directory when there's RAM to spare, so the
# compile-heavy emerge phases (unpack + object files + linking) happen in RAM instead of on the slow
# bootstrap disk (HDD seeks / USB flash). Sourced by the stage drivers; call the function once, right
# before a stage's emerges.
#
# POLICY (the caller's rule): only use a ramdisk when RAM comfortably exceeds what the parallel
# compile itself needs. Reserve ~2 GB per core for the cc1/ld processes, and require >= 32 GB left
# over for the tmpfs; below that stay disk-backed (correct + safe for small-RAM QEMU dev runs):
#     avail = RAM_GB - nproc*2 ;   avail >= 32  ->  tmpfs sized avail GB
#
# WHY MOUNT OVER THE DIR (not edit PORTAGE_TMPDIR in make.conf): the amd64 CROSS make.conf becomes
# the booted system's make.conf, so a build-only tmpfs PATH written there would leak into the running
# system (pointing at a tmpfs nothing mounts). Mounting a tmpfs over the actual build dir is
# transient (vanishes on reboot), needs no make.conf change, and leaves no build scratch on the disk.

# plx_mount_portage_tmpfs <build_dir>   (build_dir == $PORTAGE_TMPDIR/portage for the stage)
plx_mount_portage_tmpfs() {
    local dir="$1" ram_gb cores avail
    [ -n "$dir" ] || { echo "plx-ramdisk: no build dir given -- skipping"; return 0; }
    ram_gb=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1024 / 1024 ))
    cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    avail=$(( ram_gb - cores * 2 ))
    if [ "$avail" -ge 32 ]; then
        mkdir -p "$dir"
        if grep -q " $dir tmpfs " /proc/mounts 2>/dev/null; then
            echo "plx-ramdisk: tmpfs already mounted at $dir"
        elif mount -t tmpfs -o "size=${avail}G,mode=0775" plx-portage-ram "$dir"; then
            # Match portage's default build-dir ownership. Needed when userpriv is on (builds run as
            # the portage user, which must be able to write here); harmless when it's off (root ignores
            # it). Guarded in case the portage account doesn't exist in this context yet.
            chown portage:portage "$dir" 2>/dev/null || true
            echo "plx-ramdisk: mounted ${avail}G tmpfs at $dir  [RAM ${ram_gb}G - ${cores}*2 = ${avail}G >= 32]"
        else
            echo "plx-ramdisk: WARN mount failed at $dir -- continuing disk-backed"
        fi
    else
        echo "plx-ramdisk: RAM ${ram_gb}G - ${cores}*2 = ${avail}G < 32 -- keeping $dir disk-backed"
    fi
    return 0
}

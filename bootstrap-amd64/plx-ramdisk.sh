# plx-ramdisk.sh -- mount a tmpfs OVER portage's build directory when there's RAM to spare, so the
# compile-heavy emerge phases (unpack + object files + linking) happen in RAM instead of on the slow
# bootstrap disk (HDD seeks / USB flash). Sourced by the stage drivers; call the function once, right
# before a stage's emerges.
#
# POLICY (the caller's rule): only use a ramdisk when RAM comfortably exceeds what the parallel
# compile itself needs. Reserve ~2 GB per core for the cc1/ld processes, and require >= 32 GB left
# over for the tmpfs; below that stay disk-backed (correct + safe for small-RAM QEMU dev runs):
#     avail = RAM_GB - nproc*2 ;   avail >= 32  ->  tmpfs sized avail GB
# HARD EXCLUSION: on a 32-bit (i686) kernel the ramdisk is ALWAYS disabled regardless of RAM --
# tmpfs metadata lives in the tiny ~896 MB lowmem and tips the kernel into shrink_slab livelock /
# inode ENOSPC (see the uname guard below).
#
# WHY MOUNT OVER THE DIR (not edit PORTAGE_TMPDIR in make.conf): the amd64 CROSS make.conf becomes
# the booted system's make.conf, so a build-only tmpfs PATH written there would leak into the running
# system (pointing at a tmpfs nothing mounts). Mounting a tmpfs over the actual build dir is
# transient (vanishes on reboot), needs no make.conf change, and leaves no build scratch on the disk.

# plx_mount_portage_tmpfs <build_dir>   (build_dir == $PORTAGE_TMPDIR/portage for the stage)
plx_mount_portage_tmpfs() {
    local dir="$1" ram_gb cores avail
    [ -n "$dir" ] || { echo "plx-ramdisk: no build dir given -- skipping"; return 0; }

    # NEVER use a tmpfs ramdisk on a 32-bit kernel. tmpfs inode/dentry metadata lives in the i686
    # kernel's ~896 MB lowmem, which is already starved (the struct-page array for large RAM eats
    # most of it) -- a build ramdisk here tips it into a shrink_slab reclaim livelock ("negative
    # objects to delete nr=-2147...") or inode ENOSPC. The i686 @system (x86.sh) and crossdev (09)
    # stages run on the 32-bit kernel, so they always stay disk-backed. The 64-bit amd64 stage
    # (12-amd64-init.sh) has its own separate mount and is unaffected by this guard.
    case "$(uname -m 2>/dev/null)" in
        i386|i486|i586|i686|x86)
            echo "plx-ramdisk: 32-bit kernel ($(uname -m)) -- keeping $dir disk-backed (lowmem safety)"
            return 0 ;;
    esac

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

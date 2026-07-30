# plx-status.sh -- a fixed top-line status bar for the PLX bootstrap console (Linux VT).
#
# Source it, then:
#   plx_status_init            # clear the screen (wipes the kernel boot penguins) + reserve line 1
#   plx_stage "09 crossdev"    # update the bar before each stage
#   plx_status_end             # release the reserved line
# Everything printed between init and end scrolls BELOW the bar: init sets a DECSTBM scroll region
# of lines 2..N (ESC[2;Nr), so line 1 stays pinned while normal output scrolls under it. plx_stage
# rewrites line 1 without moving the output cursor (save/restore). If stdout isn't a tty it degrades
# to plain ">> STAGE: ..." prints. Linux-VT / xterm escapes only -- fine for the QEMU text console.
#
# Meant to be sourced from the driver scripts (x86.sh, x86-gentoo.sh); use `trap plx_status_end EXIT`
# after init so the region is released even if a step aborts (set -e).

plx_status_init() {
    if [ ! -t 1 ]; then PLX__TTY=0; return 0; fi
    PLX__TTY=1
    plx__sz="$(stty size 2>/dev/null || echo '24 80')"   # "rows cols"
    PLX__ROWS="${plx__sz% *}"; PLX__COLS="${plx__sz#* }"
    [ "$PLX__ROWS" -gt 2 ] 2>/dev/null || PLX__ROWS=24
    [ "$PLX__COLS" -gt 0 ] 2>/dev/null || PLX__COLS=80
    # clear screen (removes penguins), scroll region = lines 2..N, park cursor on the last line
    printf '\033[2J\033[H\033[2;%dr\033[%d;1H' "$PLX__ROWS" "$PLX__ROWS"
    PLX__STAGE=""
}

plx_stage() {
    PLX__STAGE="$*"
    if [ "${PLX__TTY:-0}" != 1 ]; then printf '>> STAGE: %s\n' "$PLX__STAGE"; return 0; fi
    PLX__TEXT="[PLX] $PLX__STAGE"
    # save cursor -> home -> clear line -> reverse-video full-width bar (pad+truncate to COLS) ->
    # reset attrs -> restore cursor (back into the scroll region, where output continues).
    printf '\0337\033[H\033[K\033[7m%-*.*s\033[0m\0338' "$PLX__COLS" "$PLX__COLS" "$PLX__TEXT"
}

plx_status_end() {
    [ "${PLX__TTY:-0}" = 1 ] || return 0
    printf '\033[r\033[%d;1H\n' "${PLX__ROWS:-24}"   # release scroll region, cursor to last line
    PLX__TTY=0                                        # idempotent: a second call (e.g. EXIT trap) no-ops
}

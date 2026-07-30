set -e

# Fix live-bootstrap gcc's wrong multiarch tuple, BEFORE anything uses the compiler.
# Driven by ../x86-bash.sh (obuild in the environment).
#
# Why: live-bootstrap's `gcc -print-multiarch` reports i386-linux-GNU (the glibc form)
# even though it's a musl compiler (`gcc -dumpmachine` = i686-unknown-linux-musl).
# dev-lang/python's configure computes PLATFORM_TRIPLET=i386-linux-musl from preprocessor
# macros and requires -print-multiarch to MATCH -- gnu != musl -> it aborts with
# "internal configure error for the platform triplet". A properly built musl gcc returns
# i386-linux-musl (or empty). We can't easily rebuild gcc, so wrap it to correct just
# that one query; every other invocation execs the untouched real binary.
#
# NOTE: `gcc` and the CHOST-prefixed `${CHOST}-gcc` are SEPARATE binaries in live-
# bootstrap (not symlinks to each other), and python's ebuild invokes CC=${CHOST}-gcc --
# so BOTH must be wrapped. Same for g++/${CHOST}-g++ (preempts a C++ pkg hitting the same
# via `g++ -print-multiarch`). We resolve each driver name to its real binary and wrap
# each DISTINCT one once. Idempotent: skips a binary already wrapped (its .orig exists).

build="${obuild#--build=}"    # i686-unknown-linux-musl (CHOST)

wrap_multiarch() {
    real="$1"
    [ -e "$real.orig" ] && { echo "  already wrapped: $real"; return 0; }
    mv "$real" "$real.orig"
    # match BOTH -print-multiarch and --print-multiarch: gcc accepts either, and
    # python's configure uses the DOUBLE-dash form (MULTIARCH=$($CC --print-multiarch)).
    # A single-dash-only pattern silently misses it and the real gcc's wrong value leaks.
    cat > "$real" <<EOF
#!/bin/sh
case " \$* " in
  *" -print-multiarch "*|*" --print-multiarch "*) echo i386-linux-musl; exit 0 ;;
esac
exec "$real.orig" "\$@"
EOF
    chmod +x "$real"
    echo "  wrapped: $real"
}

seen=""
for name in gcc g++ "$build-gcc" "$build-g++"; do
    p="$(command -v "$name" 2>/dev/null || true)"
    [ -n "$p" ] || continue
    real="$(readlink -f "$p")"
    case " $seen " in *" $real "*) continue ;; esac    # already handled this real binary
    seen="$seen $real"
    wrap_multiarch "$real"
done

hash -r
echo "gcc         -print-multiarch -> $(gcc -print-multiarch)"
echo "$build-gcc  -print-multiarch -> $("$build-gcc" -print-multiarch 2>/dev/null)"
# both should print: i386-linux-musl

set -e

# Build a minimal `getent` (passwd/group), OUTSIDE portage. Driven by ../x86-bash.sh.
# Run as root: it installs to /usr/bin, and the source is our own trivial file.
#
# Why: portage's egetent (user-info.eclass) checks whether a group/user already exists
# before creating it (acct-group/acct-user pkg_preinst). On this musl host it falls into
# its `getent "${db}" "${key}"` branch -- and `getent` is a GLIBC program, ABSENT on the
# musl live-bootstrap userland. The failed check makes acct-group/root think `root`
# doesn't exist -> it runs `groupadd root` -> dies "groupadd failed with status 9"
# (group already in use). sys-apps/getent is a PLX-overlay package (not in the main
# tree), so rather than pull the overlay we provide getent directly.
#
# Scope = egetent's entire domain: passwd/group, by name or numeric id (egetent die's on
# any other db). Uses libc getpwnam/getpwuid/getgrnam/getgrgid, which on musl read
# /etc/passwd,/etc/group directly (files-only -- exactly right for a bootstrap). Output
# and exit codes were verified byte-identical to the reference getent(1) for the query
# shapes egetent makes (name lookup, id lookup, not-found=2, both dbs).

builddir="/root/tmp/getent"
mkdir -p "$builddir"

cat > "$builddir/getent.c" <<'CEOF'
/* Minimal getent for passwd/group (name or numeric key). Exit 0=found, 2=not found. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pwd.h>
#include <grp.h>

static int is_num(const char *s){ if(!*s) return 0; for(; *s; s++) if(!isdigit((unsigned char)*s)) return 0; return 1; }
static void put_pw(struct passwd *p){ printf("%s:%s:%u:%u:%s:%s:%s\n", p->pw_name,p->pw_passwd,(unsigned)p->pw_uid,(unsigned)p->pw_gid,p->pw_gecos,p->pw_dir,p->pw_shell); }
static void put_gr(struct group *g){ printf("%s:%s:%u:", g->gr_name,g->gr_passwd,(unsigned)g->gr_gid); for(char**m=g->gr_mem; m&&*m; m++) printf("%s%s", m==g->gr_mem?"":",", *m); putchar('\n'); }

int main(int argc, char **argv){
    if(argc < 2) return 1;
    const char *db = argv[1];
    if(!strcmp(db,"passwd")){
        if(argc==2){ struct passwd *p; setpwent(); while((p=getpwent())) put_pw(p); endpwent(); return 0; }
        int found=0; for(int i=2;i<argc;i++){ struct passwd *p = is_num(argv[i])?getpwuid((uid_t)atol(argv[i])):getpwnam(argv[i]); if(p){put_pw(p);found=1;} }
        return found?0:2;
    }
    if(!strcmp(db,"group")){
        if(argc==2){ struct group *g; setgrent(); while((g=getgrent())) put_gr(g); endgrent(); return 0; }
        int found=0; for(int i=2;i<argc;i++){ struct group *g = is_num(argv[i])?getgrgid((gid_t)atol(argv[i])):getgrnam(argv[i]); if(g){put_gr(g);found=1;} }
        return found?0:2;
    }
    return 2; /* unsupported db (egetent only uses passwd/group) */
}
CEOF

echo "== getent (minimal passwd/group, live-bootstrap/musl lacks glibc getent) =="
gcc -O2 -o "$builddir/getent" "$builddir/getent.c"
install -m0755 "$builddir/getent" /usr/bin/getent
hash -r
getent group root >/dev/null && echo "getent works (group root found)"

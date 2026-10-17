TERMUX_PKG_HOMEPAGE=https://pragtical.dev
TERMUX_PKG_DESCRIPTION="The practical and pragmatic code editor (Lite XL fork)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.13.1"
TERMUX_PKG_SRCURL=https://github.com/pragtical/pragtical/archive/refs/heads/master.tar.gz
TERMUX_PKG_SHA256=SKIP_CHECKSUM
TERMUX_PKG_AUTO_UPDATE=false

TERMUX_PKG_DEPENDS="freetype, harfbuzz, libandroid-posix-semaphore, libx11, luajit, pcre2, sdl3, sdl3-image, sdl3-mixer, uchardet, libwebp, libgit2, liblzma, libzip, zlib"
TERMUX_PKG_BUILD_DEPENDS="xorgproto"
TERMUX_PKG_RECOMMENDS="termux-x11-nightly"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--buildtype=release
--wrap-mode=default
--force-fallback-for=sdl3_net
-Db_lto=false
-Djit=true
-Duse_system_lua=true
"

TERMUX_PKG_RM_AFTER_INSTALL="
include
lib/*.a
lib/pkgconfig
lib/cmake
"

termux_step_pre_configure() {
	# Some subprojects (mbedtls, ...) may need cmake on the host.
	termux_setup_cmake

	# src/api/shmem.c uses named POSIX semaphores (sem_open/sem_close/
	# sem_unlink), which bionic lacks. Termux's <semaphore.h> from
	# libandroid-posix-semaphore renames them to libandroid_sem_*, so the
	# library has to be linked explicitly (otherwise: "undefined symbol:
	# libandroid_sem_open" at the final link step).
	LDFLAGS+=" -landroid-posix-semaphore"

	# PATCH: under Termux meson reports host_machine.system() as 'android', so
	# the `== 'linux'` block that installs the icon, .desktop file and appdata
	# is skipped. Treat android like linux there. (The other `== 'linux'` in
	# meson.build only sets a cmake define in the forcefallback SDL3 branch,
	# which is unused here, so changing it is harmless.)
	sed -i "s/host_machine\.system() == 'linux'/host_machine.system() in ['linux', 'android']/" \
		"$TERMUX_PKG_SRCDIR/meson.build"
	grep -q "'linux', 'android'" "$TERMUX_PKG_SRCDIR/meson.build" ||
		termux_error_exit "meson.build patch failed (file layout changed?)"

	# PATCH: src/api/shmem.c calls shm_open()/shm_unlink(), which bionic does
	# not provide (clang: "call to undeclared function 'shm_open'"). Add a
	# header that emulates them with plain files under $TMPDIR (callers only
	# do ftruncate() + mmap(MAP_SHARED) on the returned fd, which works on
	# files) and include it at the top of shmem.c.
	cat > "$TERMUX_PKG_SRCDIR/src/api/termux_shm_compat.h" <<'EOF'
/* Termux compat - see build.sh. bionic has no shm_open()/shm_unlink();
 * emulate them with plain files under $TMPDIR. The callers only use the
 * returned fd with ftruncate() + mmap(MAP_SHARED), which works on files. */
#ifndef TERMUX_SHM_COMPAT_H
#define TERMUX_SHM_COMPAT_H
#ifdef __ANDROID__

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static inline int termux_shm_path(const char *name, char *out, size_t outlen)
{
	const char *dir = getenv("TMPDIR");
	if (!dir || !*dir)
		dir = "@TERMUX_PREFIX@/tmp";
	while (*name == '/')
		name++;
	if (!*name || strchr(name, '/')) {
		errno = EINVAL;
		return -1;
	}
	if (snprintf(out, outlen, "%s/shm.%s", dir, name) >= (int) outlen) {
		errno = ENAMETOOLONG;
		return -1;
	}
	return 0;
}

static inline int shm_open(const char *name, int oflag, mode_t mode)
{
	char path[PATH_MAX];
	if (termux_shm_path(name, path, sizeof(path)) < 0)
		return -1;
	return open(path, oflag | O_CLOEXEC, mode);
}

static inline int shm_unlink(const char *name)
{
	char path[PATH_MAX];
	if (termux_shm_path(name, path, sizeof(path)) < 0)
		return -1;
	return unlink(path);
}

#endif /* __ANDROID__ */
#endif /* TERMUX_SHM_COMPAT_H */
EOF
	sed -i "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
		"$TERMUX_PKG_SRCDIR/src/api/termux_shm_compat.h"
	grep -q termux_shm_compat.h "$TERMUX_PKG_SRCDIR/src/api/shmem.c" ||
		sed -i '1i #include "termux_shm_compat.h"' "$TERMUX_PKG_SRCDIR/src/api/shmem.c"
	grep -q termux_shm_compat.h "$TERMUX_PKG_SRCDIR/src/api/shmem.c" ||
		termux_error_exit "shmem.c patch failed"
}

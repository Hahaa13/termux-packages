# =============================================================================
# Termux recipe: pragtical (Lite XL fork)
# Location: termux-packages/x11-packages/pragtical/build.sh
# Build:    ./build-package.sh -a aarch64 pragtical
#
# STATUS: UNTESTED. Written by reading Pragtical's meson.build, src/meson.build
# and src/main.c; no NDK or network was available to run a real build.
# Besides configure flags, the only patch is a one-line sed on meson.build so
# the icon, .desktop and appdata get installed (see termux_step_pre_configure).
# Spots that need checking are marked [VERIFY].
# =============================================================================

TERMUX_PKG_HOMEPAGE=https://pragtical.dev
TERMUX_PKG_DESCRIPTION="The practical and pragmatic code editor (Lite XL fork)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
# [VERIFY] meson.build on master says 3.13.1; check that tag v3.13.1 exists.
TERMUX_PKG_VERSION="3.13.1"
TERMUX_PKG_SRCURL=https://github.com/pragtical/pragtical/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
# [VERIFY] run: curl -L <SRCURL> | sha256sum  and paste the result here.
TERMUX_PKG_SHA256=SKIP_CHECKSUM
TERMUX_PKG_AUTO_UPDATE=false

# x11-repo already ships sdl3 (3.4.18), sdl3-image (3.4.8) and sdl3-mixer
# (3.2.4), confirmed with `pkg search sdl3`. There is no sdl3-net yet, so it
# is built from a subproject (static).
TERMUX_PKG_DEPENDS="freetype, harfbuzz, libx11, luajit, pcre2, sdl3, sdl3-image, sdl3-mixer, uchardet"
TERMUX_PKG_BUILD_DEPENDS="xorgproto"
TERMUX_PKG_RECOMMENDS="termux-x11-nightly"

# About the flags:
#  --buildtype=release      Termux defaults to minsize (-Os); override it so the
#                           renderer runs faster.
#  --wrap-mode=default      Termux defaults to "nodownload"; meson must be
#                           allowed to fetch subprojects (sdl3_net, mbedtls,
#                           linenoise, colors, widget, plugins). When
#                           --wrap-mode is passed twice, the last one wins.
#  --force-fallback-for     Termux has no sdl3-net, but net=true needs SDL3_net,
#                           so build it statically from the subproject.
#                           (sdl3-mixer 3.2.4 comes from the system and meets
#                           Pragtical's minimum of >=3.2.4.)
#  -Db_lto=false            LTO and LuaJIT FFI exports (ffi_export_symbols) can
#                           clash; disabled to be safe.
#  -Djit=true
#  -Duse_system_lua=true    By default Pragtical builds LuaJIT from a
#                           subproject, which is messy to cross-compile for
#                           Android; use Termux's luajit instead.
#  -Dppm=false              Skip the plugin manager (pulls in libgit2, libzip,
#                           mbedtls...). Install ppm separately if needed.
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--buildtype=release
--wrap-mode=default
--force-fallback-for=sdl3_net
-Db_lto=false
-Djit=true
-Duse_system_lua=true
-Dppm=false
"

# Subprojects install headers and static libs into the prefix; drop them from
# the package. This only affects this package's files, not its dependencies.
TERMUX_PKG_RM_AFTER_INSTALL="
include
lib/*.a
lib/pkgconfig
lib/cmake
"

termux_step_pre_configure() {
	# Some subprojects (mbedtls, ...) may need cmake on the host.
	termux_setup_cmake

	# PATCH: under Termux meson reports host_machine.system() as 'android', so
	# the `== 'linux'` block that installs the icon, .desktop file and appdata
	# is skipped. Treat android like linux there. (The other `== 'linux'` in
	# meson.build only sets a cmake define in the forcefallback SDL3 branch,
	# which is unused here, so changing it is harmless.)
	sed -i "s/host_machine\.system() == 'linux'/host_machine.system() in ['linux', 'android']/" \
		"$TERMUX_PKG_SRCDIR/meson.build"
	grep -q "'linux', 'android'" "$TERMUX_PKG_SRCDIR/meson.build" ||
		termux_error_exit "meson.build patch failed (file layout changed?)"
}

# =============================================================================
# NOTES
#
# Under Termux, meson reports host_machine.system() as 'android', not 'linux':
#  - The ARCH tuple becomes <cpu>-android (e.g. aarch64-android); no patch needed.
#  - The `== 'linux'` block in meson.build would skip installing the icon,
#    .desktop file and appdata; that is what the sed in
#    termux_step_pre_configure fixes. They end up in share/icons/hicolor/
#    scalable/apps/pragtical.svg, share/applications/ and share/metainfo/.
#  - The LuaJIT FFI symbol export branch in src/meson.build still applies
#    (it only excludes windows and darwin).
#
# Things the old Lite XL recipe needed that are NOT needed here:
#  - No fake librt.so: meson.build uses find_library('rt', required: false)
#    and Pragtical no longer uses reproc.
#  - The dirmonitor backend picks inotify by itself (bionic has <sys/inotify.h>).
#
# If linking fails with an undefined `main`: src/main.c uses SDL3 main
# callbacks (SDL_MAIN_USE_CALLBACKS) and has no main() of its own, and the SDL3
# headers may treat NDK builds as Android and skip generating it. In that case
# a small main() calling SDL_EnterAppMainCallbacks() has to be added.
#
# If Termux gains sdl3-net later: remove it from --force-fallback-for and add
# sdl3-net to TERMUX_PKG_DEPENDS.
# To drop networking/TLS entirely: add -Dnet=false (removes SDL3_net + mbedtls).
# Without luajit: use -Djit=false -Duse_system_lua=true and depend on lua54.
#
# Building directly on the device (without termux-packages):
#   pkg install x11-repo
#   pkg install git meson ninja clang cmake pkg-config freetype harfbuzz \
#       libx11 xorgproto luajit pcre2 sdl3 sdl3-image sdl3-mixer uchardet
#   git clone https://github.com/pragtical/pragtical && cd pragtical
#   sed -i "s/host_machine\.system() == 'linux'/host_machine.system() in ['linux', 'android']/" meson.build
#   meson setup build --buildtype=release --prefix=$PREFIX --wrap-mode=default \
#       --force-fallback-for=sdl3_net -Db_lto=false \
#       -Djit=true -Duse_system_lua=true -Dppm=false
#   meson compile -C build && meson install -C build
# =============================================================================

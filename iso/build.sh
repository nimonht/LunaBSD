#!/bin/sh
#
# iso/build.sh - build the LunaBSD live image: one ISO file that starts from
# a USB stick (written with Rufus in DD mode, balenaEtcher or dd) or a DVD,
# on UEFI and legacy BIOS PCs, into a live KDE Plasma desktop with the
# graphical installer.
#
#   doas sh iso/build.sh
#
# Needs FreeBSD 15 (amd64) as root, the zfs kernel module, about 40 GB of free
# disk space, 8 GB of memory and an internet connection. Result:
# iso/out/lunabsd-<version>-amd64.iso, with .sha256 and a package list.
#
# How the live media starts (docs/BUILDING.md has the details):
#   1. FreeBSD's boot loader loads the kernel and a small ramdisk.
#   2. The ramdisk's init.sh copies the compressed system (luna/system.zfs,
#      a ZFS stream) into a ZFS pool in memory and switches to it (reboot -r).
#   3. The live system starts; luna_live picks the graphics driver and
#      starts KDE Plasma, or the installer on a basic framebuffer.
#
# Environment:
#   WORK=DIR          work directory (default iso/work, about 30 GB)
#   OUT=DIR           where the ISO goes (default iso/out)
#   FREEBSD_RELEASE   overrides distro.conf, e.g. 15.2-RELEASE
#   PKG_BRANCH        package branch (default LIVE_PKG_BRANCH in distro.conf)
#   PKG_SITE          package server while building. Default
#                     pkg+https://pkg.FreeBSD.org (mirrors picked by DNS SRV
#                     records); use https://pkg.FreeBSD.org where those
#                     lookups fail (e.g. behind an HTTP proxy)
#   DIST_SITE         where base.txz and kernel.txz come from
#                     (default https://download.freebsd.org/releases/amd64)
#   PATCH_BASE=no     do not apply freebsd-update patches to the image
#   ZSTD_LEVEL=N      final compression of the system image (default 19,
#                     the smallest; packages are installed with fast zstd and
#                     everything is recompressed once in the image step)
#   EXTRA_CA=FILE     CA bundle for a TLS-intercepting proxy; used while
#                     building only, never put on the ISO
#   SECURE_BOOT=no    FreeBSD's loader alone, unsigned (needs Secure Boot
#                     off). Default yes (docs/SECUREBOOT.md): Fedora's
#                     Microsoft-signed shim starts FreeBSD's loader, signed
#                     with a key made for this build alone (its private half
#                     is deleted right after signing); the first start with
#                     Secure Boot on asks to enroll its certificate once
#   SB_KEY=FILE SB_CERT=FILE   sign with this key instead (PEM), to keep one
#                     key across releases; whoever holds it can sign programs
#                     every computer that enrolled it will start
#   STEPS="..."       run only these steps, on the work directory of an
#                     earlier run (for development): fetch root packages
#                     configure trim image ramdisk iso
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$HERE")
. "$REPO_DIR/distro.conf"
. "$REPO_DIR/lib/secureboot.sh"
REL=${FREEBSD_RELEASE}
BRANCH=${PKG_BRANCH:-$LIVE_PKG_BRANCH}
PKG_SITE=${PKG_SITE:-pkg+https://pkg.FreeBSD.org}
DIST_SITE=${DIST_SITE:-https://download.freebsd.org/releases/amd64}
ZSTD_LEVEL=${ZSTD_LEVEL:-19}
SECURE_BOOT=${SECURE_BOOT:-yes}
WORK=${WORK:-$HERE/work}
OUT=${OUT:-$HERE/out}
ROOT=$WORK/root          # the live system, a ZFS pool in a file
CD=$WORK/cd              # what goes on the ISO
BPOOL=lunabuild
IPOOL=lunaimage         # the same, recompressed, for the ISO
ISO_NAME="$DISTRO_ID-$DISTRO_VERSION-amd64"
ALL_STEPS="fetch root packages configure trim image ramdisk iso"
STEPS=${STEPS:-$ALL_STEPS}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }
want() { case " $STEPS " in *" $1 "*) return 0 ;; esac; return 1; }

[ "$(uname -s)" = FreeBSD ] || die "this runs on FreeBSD 15 (the build needs FreeBSD's pkg, makefs, mkimg and ZFS)"
[ "$(id -u)" -eq 0 ] || die "run it as root"
for _t in makefs mkimg etdump pkg zpool zfs mdconfig kldxref; do
	command -v "$_t" >/dev/null 2>&1 || die "$_t is missing"
done
kldload -n zfs
mkdir -p "$WORK" "$OUT"

# ------------------------------------------------------------- the pool ---

MD=""
pool_mounts_off() {
	umount "$ROOT/var/cache/pkg" 2>/dev/null || true
	umount "$ROOT/dev" 2>/dev/null || umount -f "$ROOT/dev" 2>/dev/null || true
}
pool_close() {
	pool_mounts_off
	zpool list "$BPOOL" >/dev/null 2>&1 && { zpool export "$BPOOL" || true; }
	zpool list "$IPOOL" >/dev/null 2>&1 && { zpool destroy -f "$IPOOL" || true; }
	for _m in $(mdconfig -l -v 2>/dev/null | awk -v a="$WORK/root.img" -v b="$WORK/image.img" '$4 == a || $4 == b { print $1 }'); do
		mdconfig -d -u "$_m" || true
	done
	rm -f "$WORK/image.img"
	return 0
}
# (and a one-time signing key never outlives the build, even a failed one)
trap 'pool_close; [ -z "${SB_ONE_TIME:-}" ] || rm -rf "$SB_ONE_TIME"' EXIT
trap 'exit 130' INT TERM

pool_open() {
	zpool list "$BPOOL" >/dev/null 2>&1 && return 0
	[ -f "$WORK/root.img" ] || die "no image from an earlier run in $WORK (run the root step)"
	MD=$(mdconfig -a -t vnode -f "$WORK/root.img")
	zpool import -R "$ROOT" -d "/dev/$MD" "$BPOOL" || die "could not import $BPOOL"
}

pool_new() {
	pool_close
	zpool list "$BPOOL" >/dev/null 2>&1 && die "a pool named $BPOOL is in use"
	rm -f "$WORK/root.img"
	truncate -s 30G "$WORK/root.img"
	MD=$(mdconfig -a -t vnode -f "$WORK/root.img")
	# altroot: mounted at $ROOT here, "/" inside the image
	zpool create -f -R "$ROOT" -O mountpoint=/ -O compression=zstd \
		-O atime=off "$BPOOL" "/dev/$MD"
}

# Package commands inside the image (its own ABI, repositories and scripts).
in_root_pkg() {
	_ca=""
	if [ -n "${EXTRA_CA:-}" ]; then
		cp "$EXTRA_CA" "$ROOT/tmp/build-ca.pem"
		_ca="SSL_CA_CERT_FILE=/tmp/build-ca.pem CURL_CA_BUNDLE=/tmp/build-ca.pem"
	fi
	# shellcheck disable=SC2086
	env ASSUME_ALWAYS_YES=yes IGNORE_OSVERSION=yes $_ca pkg -c "$ROOT" "$@"
}

pkg_repos() { # pkg_repos SITE   the image's repository configuration
	_mt=none
	case "$1" in pkg+*) _mt=srv ;; esac
	mkdir -p "$ROOT/usr/local/etc/pkg/repos"
	cat > "$ROOT/usr/local/etc/pkg/repos/FreeBSD.conf" <<CONF
# Written by FreeBSD-setup. Overrides /etc/pkg/FreeBSD.conf.
FreeBSD-ports: {
  url: "$1/\${ABI}/$BRANCH",
  mirror_type: "$_mt"
}
FreeBSD-ports-kmods: {
  url: "$1/\${ABI}/kmods_${BRANCH}_\${VERSION_MINOR}",
  mirror_type: "$_mt"
}
CONF
}

# ---------------------------------------------------------------- steps ---

step_fetch() {
	log "Downloading FreeBSD $REL (base system and kernel)"
	_d=$WORK/dist/$REL
	mkdir -p "$_d"
	fetch -q -o "$_d/MANIFEST" "$DIST_SITE/$REL/MANIFEST" || die "could not download $DIST_SITE/$REL/MANIFEST"
	for _s in base kernel; do
		_want=$(awk -v f="$_s.txz" '$1 == f { print $2 }' "$_d/MANIFEST")
		[ -n "$_want" ] || die "$_s.txz is not in the MANIFEST"
		if [ -f "$_d/$_s.txz" ] && [ "$(sha256 -q "$_d/$_s.txz")" = "$_want" ]; then continue; fi
		fetch -o "$_d/$_s.txz" "$DIST_SITE/$REL/$_s.txz" || die "download of $_s.txz failed"
		[ "$(sha256 -q "$_d/$_s.txz")" = "$_want" ] || die "$_s.txz does not match its checksum"
	done
	if [ "$SECURE_BOOT" = yes ]; then
		log "Downloading the Microsoft-signed shim (Fedora's)"
		sb_fetch_shim "$WORK/shim" || die "could not get the shim"
	fi
}

step_root() {
	log "Creating the image and unpacking FreeBSD $REL"
	pool_new
	for _s in base kernel; do
		tar -xpf "$WORK/dist/$REL/$_s.txz" -C "$ROOT"
	done
	if [ "${PATCH_BASE:-yes}" != no ]; then
		log "Applying FreeBSD security patches (freebsd-update)"
		mkdir -p "$ROOT/var/db/freebsd-update"
		_fu="freebsd-update -b $ROOT -d $ROOT/var/db/freebsd-update -f $ROOT/etc/freebsd-update.conf --not-running-from-cron --currently-running $REL"
		# shellcheck disable=SC2086
		if env PAGER=cat $_fu fetch; then
			env PAGER=cat $_fu install || true
		else
			die "freebsd-update could not fetch patches (PATCH_BASE=no builds without them)"
		fi
		rm -rf "$ROOT/var/db/freebsd-update"/*
	fi
}

# nvidia_packages "names"   NVIDIA's driver, its kernel module and its DRM
# module must be one version and built for the DRM version installed. The
# FreeBSD-ports-kmods repository has carried newer modules than the driver,
# built against another DRM version, so try the main repository on its own
# first. Without a consistent set, the live image goes without NVIDIA (those
# cards then get the installer on the basic framebuffer).
nvidia_packages() {
	for _r in "-r FreeBSD-ports" ""; do
		# shellcheck disable=SC2086
		if in_root_pkg install -y $_r $1; then
			_d=$(in_root_pkg query '%v' nvidia-driver 2>/dev/null | sed 's/[_,].*//')
			_k=$(in_root_pkg query '%v' nvidia-kmod 2>/dev/null)
			case "$_k" in "$_d".*|"$_d") log "NVIDIA driver $_d"; return 0 ;; esac
			printf 'build.sh: NVIDIA driver %s and kernel module %s differ\n' "$_d" "$_k" >&2
		fi
		# shellcheck disable=SC2046
		in_root_pkg delete -y $(in_root_pkg query -g '%n' 'nvidia-*' 2>/dev/null) 2>/dev/null || true
	done
	printf 'build.sh: WARNING: no consistent NVIDIA driver in the package repositories; the live image has none\n' >&2
}

step_packages() {
	log "Installing the live system's packages ($BRANCH branch; the longest step)"
	pool_open
	pkg_repos "$PKG_SITE"
	mkdir -p "$ROOT/dev" "$WORK/pkgcache" "$ROOT/var/cache/pkg"
	pool_mounts_off
	mount -t devfs devfs "$ROOT/dev"
	mount -t nullfs "$WORK/pkgcache" "$ROOT/var/cache/pkg"
	cp /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true
	_list=$(sed 's/#.*//' "$HERE/packages.txt" | xargs)
	in_root_pkg update -f
	# One DRM version for every graphics driver: the meta packages drm-kmod
	# and nvidia-drm-kmod are updated separately and can point at different
	# ones (e.g. 6.12 and 5.15), which cannot be installed together. Take
	# the version drm-kmod picks, and NVIDIA's module built for it.
	_drm=$(in_root_pkg rquery -U '%dn' drm-kmod | grep -E '^drm-[0-9]+-kmod$' | head -1)
	[ -n "$_drm" ] || die "the drm-kmod package names no DRM driver version"
	_dv=${_drm#drm-}; _dv=${_dv%-kmod}
	_nv=""
	for _p in $_list; do case "$_p" in nvidia-*) _nv="$_nv $_p" ;; esac; done
	_list=$(printf '%s\n' $_list | grep -v '^nvidia-' | sed -e "s/^drm-kmod\$/$_drm/" | xargs)
	log "graphics drivers: $_drm"
	# shellcheck disable=SC2086
	in_root_pkg install -y $_list
	[ -n "$_nv" ] && nvidia_packages "$(echo "$_nv" | sed "s/nvidia-drm-kmod/nvidia-drm-$_dv-kmod/")"
	in_root_pkg query '%n %v' | sort > "$WORK/packages.list"
	pool_mounts_off
	rm -f "$ROOT/tmp/build-ca.pem"
}

step_configure() {
	log "Configuring the live system"
	pool_open
	_live=$HERE/live
	_share=/usr/local/share/freebsd-setup

	# This repository, as on an installed system (the installer runs from it).
	rm -rf "${ROOT:?}$_share"
	mkdir -p "$ROOT$_share" "$ROOT/usr/local/sbin"
	(cd "$REPO_DIR" && tar -cf - --exclude ./.git --exclude ./iso/work --exclude ./iso/out \
		--exclude ./iso/vm --exclude ./tests/vm/work --exclude './tests/vm/live-work*' \
		--exclude './tests/vm/sb-work*' --exclude '__pycache__' .) | tar -xf - -C "$ROOT$_share"
	ln -sf "$_share/setup.sh" "$ROOT/usr/local/sbin/freebsd-setup"
	# Secure Boot: the installer puts shim on the new system's EFI partition.
	rm -rf "${ROOT:?}$SB_SHARE"
	if [ "$SECURE_BOOT" = yes ]; then
		sb_shim_ok "$WORK/shim" || die "the shim is missing: run the fetch step"
		mkdir -p "$ROOT$SB_SHARE"
		install -m 444 "$WORK/shim/shimx64.efi" "$WORK/shim/mmx64.efi" "$ROOT$SB_SHARE/"
	fi

	# Branding: boot menu, wallpaper, About page, os-release.
	. "$REPO_DIR/lib/branding.sh"
	BRANDING_NO_LOADER_CONF=yes branding_apply "$ROOT"

	# The graphical installer and its helpers.
	install -m 755 "$REPO_DIR/installer/luna-installer" "$ROOT/usr/local/bin/luna-installer"
	install -m 755 "$REPO_DIR/installer/luna-wifi" "$ROOT/usr/local/sbin/luna-wifi"
	install -m 644 "$REPO_DIR/installer/luna-installer.desktop" \
		"$ROOT/usr/local/share/applications/luna-installer.desktop"

	# The live session: hardware -> graphics driver -> desktop or installer.
	install -m 755 "$_live/luna_live" "$ROOT/usr/local/etc/rc.d/luna_live"
	install -m 755 "$_live/luna-installer-session" "$ROOT/usr/local/libexec/luna-installer-session"
	install -m 755 "$_live/luna-plasma" "$ROOT/usr/local/libexec/luna-plasma"
	# The first console logs the live user in when Plasma is to start
	# (luna_live switches ttyv0 to this entry; ~/.profile then starts it).
	if ! grep -q '^luna.live' "$ROOT/etc/gettytab"; then
		printf '\n# LunaBSD live: the live user on the first console (iso/live/luna_live).\nluna.live:\\\n\t:al=%s:tc=Pc:\n' \
			"$LIVE_USER" >> "$ROOT/etc/gettytab"
	fi
	mkdir -p "$ROOT/usr/local/share/xsessions" "$ROOT/usr/local/etc/sddm.conf.d" "$ROOT/usr/local/etc/xdg/autostart"
	install -m 644 "$_live/luna-installer.session.desktop" "$ROOT/usr/local/share/xsessions/luna-installer.desktop"
	install -m 644 "$_live/sddm-live.conf" "$ROOT/usr/local/etc/sddm.conf.d/10-luna-live.conf"
	install -m 644 "$_live/luna-welcome.desktop" "$ROOT/usr/local/etc/xdg/autostart/luna-welcome.desktop"
	install -m 755 "$_live/rc.local" "$ROOT/etc/rc.local"
	install -m 644 "$_live/rc.conf" "$ROOT/etc/rc.conf"
	sed -i '' "s/@HOSTNAME@/$LIVE_HOSTNAME/" "$ROOT/etc/rc.conf"
	install -m 600 "$_live/doas.conf" "$ROOT/usr/local/etc/doas.conf"
	install -m 644 "$_live/motd" "$ROOT/etc/motd.template"
	install -m 644 "$_live/sysctl.conf" "$ROOT/etc/sysctl.conf"
	printf 'proc\t/proc\tprocfs\trw\t0\t0\nfdescfs\t/dev/fd\tfdescfs\trw\t0\t0\n' > "$ROOT/etc/fstab"

	# What an installed desktop gets from stages/system.sh, desktop.sh, audio.sh
	# and kde.sh, from the same files: GPU and backlight access for the video
	# group, polkit (mount drives, restart), PipeWire, KDE defaults.
	install -m 644 "$REPO_DIR/files/devfs.rules" "$ROOT/etc/devfs.rules"
	mkdir -p "$ROOT/usr/local/etc/polkit-1/rules.d" "$ROOT/usr/local/etc/pulse/client.conf.d"
	install -m 644 "$REPO_DIR/files/desktop/50-freebsd-setup.rules" "$ROOT/usr/local/etc/polkit-1/rules.d/50-freebsd-setup.rules"
	install -m 755 "$REPO_DIR/files/bin/start-pipewire" "$ROOT/usr/local/bin/start-pipewire"
	install -m 644 "$REPO_DIR/files/desktop/start-pipewire.desktop" "$ROOT/usr/local/etc/xdg/autostart/start-pipewire.desktop"
	install -m 644 "$REPO_DIR/files/desktop/pulse-client.conf" "$ROOT/usr/local/etc/pulse/client.conf.d/50-freebsd-setup.conf"
	install -m 644 "$REPO_DIR/files/kde/kdeglobals" "$ROOT/usr/local/etc/xdg/kdeglobals"
	install -m 755 "$REPO_DIR/files/bin/brightnessctl" "$ROOT/usr/local/bin/brightnessctl"

	# NVIDIA's EGL and Vulkan libraries register themselves for every
	# program, and crash without NVIDIA's kernel module: X died in GLX
	# initialisation (libnvidia-egl-gbm) on a machine without NVIDIA.
	# Installations only get them on NVIDIA machines; the live system puts
	# them back at start when the NVIDIA driver runs (iso/live/luna_live).
	_off=$ROOT/usr/local/share/luna-live/nvidia-off
	for _f in share/glvnd/egl_vendor.d/10_nvidia.json share/vulkan/icd.d/nvidia_icd.json \
		share/vulkan/implicit_layer.d/nvidia_layers.json; do
		[ -f "$ROOT/usr/local/$_f" ] || continue
		mkdir -p "$_off/${_f%/*}"
		mv "$ROOT/usr/local/$_f" "$_off/$_f"
	done
	printf 'kern.geom.label.disk_ident.enable="0"\nkern.geom.label.gptid.enable="0"\n' > "$ROOT/boot/loader.conf"
	cp "$ROOT/usr/share/zoneinfo/UTC" "$ROOT/etc/localtime"

	# The live user: no password, administrator (doas without password).
	chroot "$ROOT" pw userdel "$LIVE_USER" -r 2>/dev/null || true
	chroot "$ROOT" pw useradd "$LIVE_USER" -m -c "Live user" -G wheel,operator,video -s /bin/sh -w none
	chroot "$ROOT" pw usermod root -w none
	_home="$ROOT/home/$LIVE_USER"
	(cd "$_live/home" && tar -cf - .) | tar -xf - -C "$_home"
	cat >> "$_home/.profile" <<'PROFILE'

# Written by FreeBSD-setup: on the LunaBSD live system the first console
# starts KDE Plasma when luna_live chose it (iso/live/luna_live).
if [ "$(tty)" = /dev/ttyv0 ] && [ "$(cat /var/run/luna-live/session 2>/dev/null)" = plasma ]; then
	exec /usr/local/libexec/luna-plasma
fi
PROFILE
	mkdir -p "$_home/Desktop"
	install -m 755 "$REPO_DIR/installer/luna-installer.desktop" "$_home/Desktop/install-$DISTRO_ID.desktop"
	chroot "$ROOT" chown -R "$LIVE_USER:$LIVE_USER" "/home/$LIVE_USER"

	# The installer checks the base system it downloads against this list
	# (from the media, so a tampered mirror cannot slip anything in).
	mkdir -p "$ROOT/usr/freebsd-dist"
	cp "$WORK/dist/$REL/MANIFEST" "$ROOT/usr/freebsd-dist/MANIFEST"

	# What users of the live system get from pkg: the normal mirrors.
	pkg_repos pkg+https://pkg.FreeBSD.org
	rm -f "$ROOT/etc/resolv.conf"
	echo "$DISTRO_NAME $DISTRO_VERSION live ($REL, $BRANCH packages, built $(date -u +%Y-%m-%d))" \
		> "$ROOT/usr/local/share/$DISTRO_ID/live-build"
}

# Files nobody needs on a live system: compilers, headers, static libraries,
# documentation. Installations download their own packages, so this only
# makes the ISO smaller.
step_trim() {
	log "Trimming the image"
	pool_open
	_before=$(zfs get -Hp -o value used "$BPOOL")
	(
		cd "$ROOT"
		rm -rf usr/share/doc usr/local/share/doc usr/share/examples usr/tests usr/lib/debug \
			usr/include usr/lib/clang usr/local/share/gtk-doc var/cache/pkg/* var/db/freebsd-update/* \
			usr/share/man usr/local/share/man usr/local/man usr/local/share/info
		# test suites of Python and its packages
		find usr/local/lib/python3* -type d \( -name test -o -name tests -o -name idle_test \) \
			-prune -exec rm -rf {} + 2>/dev/null || true
		find usr/lib usr/lib32 -name '*.a' -type f -delete 2>/dev/null || true
		for _f in cc c++ clang clang++ clang-cpp cpp ld ld.lld lld lldb lldb-server \
			llvm-addr2line llvm-ar llvm-cov llvm-cxxfilt llvm-nm llvm-objcopy llvm-objdump \
			llvm-profdata llvm-ranlib llvm-readelf llvm-readobj llvm-size llvm-strings \
			llvm-strip llvm-symbolizer; do
			rm -f "usr/bin/$_f"
		done
	)
	# Compilers that came as dependencies: keep their shared libraries only.
	for _p in llvm19 llvm20 llvm21 gcc13 gcc14 gcc15 binutils; do
		in_root_pkg info -e "$_p" 2>/dev/null || continue
		in_root_pkg info -ql "$_p" | grep -Ev '\.so(\.[0-9]+)*$' | sed "s|^|$ROOT|" |
			tr '\n' '\0' | xargs -0 rm -f
	done
	# C/C++ headers (Python keeps its own: sysconfig can read pyconfig.h).
	find "$ROOT/usr/local/include" -mindepth 1 -maxdepth 1 ! -name 'python*' -exec rm -rf {} + 2>/dev/null || true
	_after=$(zfs get -Hp -o value used "$BPOOL")
	log "image: $((_before / 1048576)) MiB -> $((_after / 1048576)) MiB (compressed)"
}

step_image() {
	log "Compressing the system image (zstd-$ZSTD_LEVEL: slow, once)"
	pool_open
	pool_mounts_off
	mkdir -p "$CD/luna"
	zfs destroy "$BPOOL@live" 2>/dev/null || true
	zfs snapshot "$BPOOL@live"
	# Every block rewritten at the final level, in a second pool: an
	# uncompressed stream in, a compressed one out (-c keeps the blocks as
	# they are stored).
	zpool list "$IPOOL" >/dev/null 2>&1 && zpool destroy -f "$IPOOL"
	rm -f "$WORK/image.img"
	truncate -s 30G "$WORK/image.img"
	_imd=$(mdconfig -a -t vnode -f "$WORK/image.img")
	zpool create -f -m none -O atime=off "$IPOOL" "/dev/$_imd"
	zfs send -p "$BPOOL@live" | zfs receive -u -F -o compression="zstd-$ZSTD_LEVEL" "$IPOOL"
	zfs send -p -c -e "$IPOOL@live" > "$CD/luna/system.zfs"
	zpool destroy -f "$IPOOL"
	mdconfig -d -u "$_imd"
	rm -f "$WORK/image.img"
	_sz=$(stat -f %z "$CD/luna/system.zfs")
	[ "$_sz" -lt 4294967295 ] || die "the system image is $((_sz / 1048576)) MiB: an ISO 9660 file must stay under 4 GiB"
	log "system image: $((_sz / 1048576)) MiB"
}

step_ramdisk() {
	log "Building the ramdisk"
	pool_open
	_rd=$WORK/ramdisk
	rm -rf "$_rd"; mkdir -p "$_rd/dev" "$_rd/etc" "$_rd/cdrom" "$_rd/tmp"
	tar -cf - -C "$ROOT" rescue | tar -xf - -C "$_rd"
	sed "s/@LABEL@/$ISO_LABEL/" "$HERE/ramdisk/init.sh" > "$_rd/init.sh"
	chmod 755 "$_rd/init.sh"
	install -m 755 "$HERE/ramdisk/rc" "$_rd/etc/rc"
	cp "$ROOT/etc/login.conf" "$_rd/etc/login.conf"
	: > "$_rd/etc/fstab"
	makefs -t ffs -B little -o version=2 -b 10% -f 10% "$WORK/ramdisk.ufs" "$_rd"
	mkdir -p "$CD/luna"
	gzip -9 -c "$WORK/ramdisk.ufs" > "$CD/luna/ramdisk.ufs.gz"
}

# The key the live media's loader is signed with: SB_KEY/SB_CERT, or, by
# default, one made for this build alone. Its private half only signs this
# loader and is deleted right after (sb_project_key_done), so nothing can be
# signed with it later. The cost: each new ISO's certificate is enrolled
# once more (installed systems use their own keys and are not affected).
SB_ONE_TIME=""
sb_project_key() {
	if [ -n "${SB_KEY:-}" ] || [ -n "${SB_CERT:-}" ]; then
		[ -f "${SB_KEY:-}" ] && [ -f "${SB_CERT:-}" ] || die "SB_KEY and SB_CERT must both name files"
		return 0
	fi
	SB_ONE_TIME=$(mktemp -d "$WORK/sbkey.XXXXXX")
	SB_KEY=$SB_ONE_TIME/key.pem SB_CERT=$SB_ONE_TIME/cert.pem
	(umask 077 && openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 10950 \
		-subj "/O=$DISTRO_NAME/CN=$DISTRO_NAME $DISTRO_VERSION live media ($(date -u +%Y-%m-%d))" \
		-keyout "$SB_KEY" -out "$SB_CERT") >/dev/null 2>&1 || die "could not make a signing key"
}
sb_project_key_done() {
	[ -n "$SB_ONE_TIME" ] || return 0
	rm -rf "$SB_ONE_TIME"
	SB_ONE_TIME="" SB_KEY="" SB_CERT=""
}

step_iso() {
	log "Building the ISO"
	pool_open
	# Only boot/ and luna/ belong on the ISO: drop whatever an earlier
	# build (or an older layout) left in the staging directory.
	find "$CD" -mindepth 1 -maxdepth 1 ! -name boot ! -name luna -exec rm -rf {} +
	# The boot loader and its files; of the kernel only what starts the
	# ramdisk (the live system brings its own copy of everything else).
	rm -rf "${CD:?}/boot"
	tar -cf - -C "$ROOT" --exclude ./boot/kernel --exclude ./boot/kernel.old --exclude ./boot/modules \
		--exclude ./boot/firmware --exclude ./boot/efi --exclude ./boot/zfs --exclude ./boot/entropy \
		--exclude ./boot/loader.conf --exclude ./boot/loader.conf.d ./boot | tar -xf - -C "$CD"
	mkdir -p "$CD/boot/kernel"
	cp "$ROOT/boot/kernel/kernel" "$ROOT/boot/kernel/zfs.ko" "$CD/boot/kernel/"
	kldxref "$CD/boot/kernel"
	install -m 444 "$HERE/boot/loader.conf" "$CD/boot/loader.conf"
	install -m 444 "$HERE/boot/local.lua" "$CD/boot/lua/local.lua"
	install -m 444 "$REPO_DIR/branding/loader/brand-luna.lua" "$CD/boot/lua/brand-luna.lua"
	install -m 444 "$REPO_DIR/branding/loader/logo-luna.lua" "$CD/boot/lua/logo-luna.lua"
	mkdir -p "$CD/boot/images"
	install -m 444 "$REPO_DIR/branding/loader/lunabsd-brand.png" "$REPO_DIR/branding/loader/lunabsd-logo.png" "$CD/boot/images/"
	cp "$ROOT/COPYRIGHT" "$CD/COPYRIGHT" 2>/dev/null || true
	printf '%s %s (%s) - %s\n' "$DISTRO_NAME" "$DISTRO_VERSION" "$REL" "$DISTRO_URL" > "$CD/README.TXT"

	# UEFI: a small FAT image with the loader, as FreeBSD's own media have
	# (FAT16: FAT12 cannot address its size in 512-byte clusters; makefs
	# then writes a broken file system that UEFI firmware cannot read).
	_esp=$WORK/esp
	rm -rf "$_esp"; mkdir -p "$_esp/EFI/BOOT"
	if [ "$SECURE_BOOT" = yes ]; then
		# shim (signed by Microsoft) -> grubx64.efi next to it: FreeBSD's
		# loader with SBAT data, signed with the project key. MokManager and
		# the key file are there for the first start with Secure Boot on.
		sb_project_key
		sb_shim_ok "$WORK/shim" || die "the shim is missing: run the fetch step"
		_sbw=$ROOT/tmp/lunabsd-sb
		rm -rf "$_sbw"; mkdir -p "$_sbw"
		cp "$REPO_DIR/lib/secureboot.py" "$ROOT/boot/loader.efi" "$_sbw/"
		# (python3 of the live system: the build host needs none)
		chroot "$ROOT" /usr/local/bin/python3 /tmp/lunabsd-sb/secureboot.py sbat \
			/tmp/lunabsd-sb/loader.efi /tmp/lunabsd-sb/loader-sbat.efi "${REL%%-*}" ||
			die "could not add SBAT data to the loader"
		uefisign -k "$SB_KEY" -c "$SB_CERT" -o "$_esp/EFI/BOOT/grubx64.efi" "$_sbw/loader-sbat.efi" >/dev/null ||
			die "could not sign the loader"
		rm -rf "$_sbw"
		cp "$WORK/shim/shimx64.efi" "$_esp/EFI/BOOT/BOOTX64.EFI"
		cp "$WORK/shim/mmx64.efi" "$_esp/EFI/BOOT/mmx64.efi"
		openssl x509 -in "$SB_CERT" -outform DER -out "$_esp/$SB_KEYFILE"
		cp "$_esp/$SB_KEYFILE" "$CD/$SB_KEYFILE"
		sb_project_key_done
	else
		cp "$ROOT/boot/loader.efi" "$_esp/EFI/BOOT/BOOTX64.EFI"
	fi
	rm -f "$WORK/efiboot.img"
	makefs -t msdos -o fat_type=16 -o sectors_per_cluster=1 -o volume_label=EFISYS \
		-s 8192k "$WORK/efiboot.img" "$_esp"

	_iso=$OUT/$ISO_NAME.iso
	rm -f "$_iso"
	makefs -t cd9660 -o rockridge -o label="$ISO_LABEL" -o publisher="$DISTRO_NAME $DISTRO_URL" \
		-o "bootimage=i386;$CD/boot/cdboot" -o no-emul-boot \
		-o "bootimage=i386;$WORK/efiboot.img" -o no-emul-boot -o platformid=efi \
		"$_iso" "$CD"

	# USB sticks: a GPT in the ISO's first 32 KB (as FreeBSD's
	# mkisoimages.sh does): BIOS boot code, and the EFI image as a partition.
	_espparam=""
	for _e in $(etdump --format shell "$_iso"); do
		eval "$_e"
		# shellcheck disable=SC2154
		if [ "$et_platform" = efi ]; then
			_espparam="-p efi::$((et_sectors * 512)):$((et_lba * 2048))"
			break
		fi
	done
	[ -n "$_espparam" ] || die "the EFI boot image is missing from the ISO"
	_hy=$WORK/hybrid.img
	# shellcheck disable=SC2086
	mkimg -s gpt --capacity "$(stat -f %z "$_iso")" -b "$CD/boot/pmbr" \
		-p "freebsd-boot:=$CD/boot/isoboot" $_espparam -o "$_hy"
	dd if="$_hy" of="$_iso" bs=32k count=1 conv=notrunc 2>/dev/null
	rm -f "$_hy"

	(cd "$OUT" && sha256 "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256")
	cp "$WORK/packages.list" "$OUT/$ISO_NAME.packages.txt" 2>/dev/null || true
	log "done: $_iso ($(( $(stat -f %z "$_iso") / 1048576 )) MiB)"
	[ "$(stat -f %z "$_iso")" -le 2147483648 ] ||
		printf 'build.sh: note: the ISO is larger than 2 GiB (2048 MiB), the limit for a file in a GitHub release\n' >&2
}

for _s in $ALL_STEPS; do
	want "$_s" && "step_$_s"
done
exit 0

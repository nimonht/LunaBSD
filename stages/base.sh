# Stage: base - package branch, updates, core tools, privileges, language.

POOL=$(root_pool)

# A boot environment to fall back to, before anything is changed.
if is_live && [ -n "$POOL" ] && ! bectl list -H 2>/dev/null | grep -q '^pre-setup'; then
	BE="pre-setup-$(date +%Y%m%d-%H%M)"
	bectl create "$BE" && say "boot environment '$BE' created (undo everything: bectl activate $BE && reboot)"
fi

# Package branch. Never move a machine from "latest" back to "quarterly":
# pkg cannot downgrade cleanly.
_repo=/usr/local/etc/pkg/repos/FreeBSD.conf
if [ "$PKG_BRANCH" = quarterly ] && grep -qs '/latest"' "$_repo"; then
	say "this machine already uses the 'latest' package branch - keeping it"
	PKG_BRANCH=latest
fi
say "package branch: $PKG_BRANCH"
mkdir -p /usr/local/etc/pkg/repos
if [ -f "$_repo" ] && ! grep -q 'Written by FreeBSD-setup' "$_repo"; then
	say "kept your own $_repo (package branch settings are not changed)"
else
	cat > "$_repo" <<CONF
# Written by FreeBSD-setup. Overrides /etc/pkg/FreeBSD.conf.
FreeBSD-ports: {
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/$PKG_BRANCH"
}
FreeBSD-ports-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/kmods_${PKG_BRANCH}_\${VERSION_MINOR}"
}
CONF
fi

say "bootstrapping pkg and updating the package catalogue"
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f >> "$LOG" 2>&1 ||
	die "pkg bootstrap failed - is the network up? (try: ping pkg.freebsd.org)"
pkg update -f >> "$LOG" 2>&1 || die "pkg update failed (details: $LOG)"
# doas first, on its own: if anything later fails, the advice to run
# "doas freebsd-setup" must work. "persist" remembers the password a while.
pkg_get -q doas || warn "doas could not be installed yet (it is retried below)"
if [ ! -f /usr/local/etc/doas.conf ]; then
	cat > /usr/local/etc/doas.conf <<CONF
permit persist :wheel
permit nopass :wheel cmd /sbin/shutdown
permit nopass :wheel cmd /usr/sbin/zzz
CONF
	chmod 600 /usr/local/etc/doas.conf
fi
say "upgrading installed packages"
env ASSUME_ALWAYS_YES=yes pkg upgrade -y >> "$LOG" 2>&1 || warn "pkg upgrade reported a problem (details: $LOG)"

if is_live && is_yes RUN_FREEBSD_UPDATE && freebsd-version -u | grep -q RELEASE; then
	say "freebsd-update: base system security patches (a few minutes)"
	if env PAGER=cat freebsd-update --not-running-from-cron fetch >> "$LOG" 2>&1; then
		env PAGER=cat freebsd-update --not-running-from-cron install >> "$LOG" 2>&1 || true
	else
		warn "freebsd-update could not fetch patches; run 'sysup' later"
	fi
fi

pkg_install doas sudo git curl bash nano htop rsync unzip zip 7-zip jq ca_root_nss \
	pciutils usbutils dmidecode smartmontools fastfetch
# fastfetch looks for os-release under /usr/local/etc and otherwise shows no
# OS name ("Could not detect OS"); FreeBSD keeps it in /etc.
[ -e /usr/local/etc/os-release ] || [ -L /usr/local/etc/os-release ] ||
	ln -s /etc/os-release /usr/local/etc/os-release

# sudo as well: many scripts and desktop tools written for Linux call it.
# sudo reads sudoers.d in name order and the last matching rule wins, so this
# general rule must sort first: packages add password-free rules for single
# tools (networkmgr's tray applet is started as "sudo networkmgr" at login,
# with no terminal to ask for a password).
mkdir -p /usr/local/etc/sudoers.d
printf '# Written by FreeBSD-setup.\n%%wheel ALL=(ALL:ALL) ALL\n' > /usr/local/etc/sudoers.d/00-freebsd-setup
chmod 440 /usr/local/etc/sudoers.d/00-freebsd-setup
# Earlier versions wrote the same rule as "wheel", which sorted last.
[ "$(cat /usr/local/etc/sudoers.d/wheel 2>/dev/null)" = '%wheel ALL=(ALL:ALL) ALL' ] &&
	rm -f /usr/local/etc/sudoers.d/wheel

say "adding $TARGET_USER to the wheel, operator and video groups"
for g in wheel operator video; do pw groupmod "$g" -m "$TARGET_USER"; done

# Language: the system locale for programs, LANGUAGE for desktop translations
# (FreeBSD has no system locale for some languages, e.g. Vietnamese).
_loc=${LOCALE:-}
[ -z "$_loc" ] && [ ! -f "$TARGET_HOME/.login_conf" ] && _loc=en_US.UTF-8
if [ -n "$_loc" ]; then
	[ -d "/usr/share/locale/$_loc" ] || _loc=en_US.UTF-8
	say "locale for $TARGET_USER: $_loc${DESKTOP_LANGUAGE:+ (desktop language: $DESKTOP_LANGUAGE)}"
	_lang=""
	case "${DESKTOP_LANGUAGE:-}" in
	""|en) ;;
	pt-br) _lang="pt_BR" ;; zh-cn) _lang="zh_CN" ;; zh-tw) _lang="zh_TW" ;;
	*) _lang=$DESKTOP_LANGUAGE ;;
	esac
	{
		echo "me:\\"
		echo "	:charset=UTF-8:\\"
		[ -n "$_lang" ] && echo "	:setenv=LANGUAGE=$_lang:\\"
		echo "	:lang=$_loc:"
	} > "$TARGET_HOME/.login_conf"
	chown "$TARGET_USER" "$TARGET_HOME/.login_conf"
fi

# Console keyboard layout (the desktop layout is set by the desktop stage).
if [ -n "${KEYBOARD_LAYOUT:-}" ]; then
	_km=$(wiz_layout_keymap "$KEYBOARD_LAYOUT")
	[ -n "$_km" ] && [ -f "/usr/share/vt/keymaps/$_km" ] && sysrc keymap="${_km%.kbd}" >/dev/null
fi

true   # (a stage must not end on a failed test: setup.sh runs under set -e)

# Stage: kde - KDE Plasma 6 (Wayland session, started by SDDM).

[ "$WANT_KDE" = yes ] || { say "KDE Plasma not selected - skipped"; return 0; }

say "KDE Plasma (several hundred packages; the longest download)"
if ! pkg_get plasma6-plasma; then
	if pkg_has plasma6-plasma; then
		warn "KDE Plasma could not be downloaded completely (network or mirror trouble; details: $LOG). Check the connection and run: doas freebsd-setup kde"
	else
		warn "KDE Plasma (plasma6-plasma) cannot be installed from the '$PKG_BRANCH' package branch right now - FreeBSD rebuilds it after big updates. Try again in a few days: doas freebsd-setup kde"
	fi
	return 0
fi
pkg_try plasma6-xdg-desktop-portal-kde plasma6-sddm-kcm plasma6-kde-gtk-config \
	plasma6-spectacle konsole dolphin kate ark gwenview okular kcalc
is_yes INSTALL_PRINTING && pkg_try plasma6-print-manager skanlite

# Plasma's language and keyboard settings for the user (only when unset).
_cfg="$TARGET_HOME/.config"
mkdir -p "$_cfg"
if [ -n "${KEYBOARD_LAYOUT:-}" ] && [ ! -f "$_cfg/kxkbrc" ]; then
	_xkb=$KEYBOARD_LAYOUT _var=""
	case "$_xkb" in us-intl) _xkb=us _var=intl ;; esac
	printf '[Layout]\nLayoutList=%s\nVariantList=%s\nUse=true\n' "$_xkb" "$_var" > "$_cfg/kxkbrc"
fi
case "${DESKTOP_LANGUAGE:-}" in
""|en) ;;
*)	if [ ! -f "$_cfg/plasma-localerc" ]; then
		_l=$DESKTOP_LANGUAGE
		case "$_l" in pt-br) _l=pt_BR ;; zh-cn) _l=zh_CN ;; zh-tw) _l=zh_TW ;; esac
		printf '[Translations]\nLANGUAGE=%s\n' "$_l" > "$_cfg/plasma-localerc"
	fi ;;
esac
chown -R "$TARGET_USER" "$_cfg"
# File search indexing (Baloo) off by default: on FreeBSD it watches files
# through kqueue, which keeps a file open per watched file and can run out of
# file handles. Dolphin's search still works, only more slowly. Turn it back
# on in System Settings > Search.
mkdir -p /usr/local/etc/xdg
[ -e /usr/local/etc/xdg/baloofilerc ] ||
	printf '# Written by FreeBSD-setup\n[Basic Settings]\nIndexing-Enabled=false\n' > /usr/local/etc/xdg/baloofilerc
# System-wide KDE defaults (each user's own settings win): the dark Breeze
# theme, and Ark opening the folder it extracted to. The arkrc goes to
# /etc/xdg because the ark package ships its own /usr/local/etc/xdg/arkrc;
# KDE merges both, key by key. (The About page is branded by the
# kinfocenter package already.)
sys_file "$REPO_DIR/files/kde/kdeglobals" /usr/local/etc/xdg/kdeglobals || true
sys_file "$REPO_DIR/files/kde/arkrc" /etc/xdg/arkrc || true
# System Settings > Date & Time changes the time zone and clock through the
# org.freedesktop.timedate1 service (systemd-timedated on Linux): ours,
# started on demand. It needs Python's GObject package (system stage).
if [ -x /usr/local/bin/python3 ] && /usr/local/bin/python3 -c 'import gi' 2>/dev/null; then
	_td="$REPO_DIR/files/timedate"
	mkdir -p /usr/local/libexec /usr/local/share/dbus-1/system.d /usr/local/share/dbus-1/system-services \
		/usr/local/share/polkit-1/actions /usr/local/etc/polkit-1/rules.d
	install_file "$_td/fbs-timedate" /usr/local/libexec/fbs-timedate 755
	install_file "$_td/fbs-timedate.conf" /usr/local/share/dbus-1/system.d/fbs-timedate.conf
	install_file "$_td/org.freedesktop.timedate1.service" /usr/local/share/dbus-1/system-services/org.freedesktop.timedate1.service
	install_file "$_td/org.freedesktop.timedate1.policy" /usr/local/share/polkit-1/actions/org.freedesktop.timedate1.policy
	install_file "$_td/50-fbs-timedate.rules" /usr/local/etc/polkit-1/rules.d/50-fbs-timedate.rules
	is_live && { dbus-send --system --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig >> "$LOG" 2>&1 || true; }
else
	warn "KDE's Date & Time page cannot change the time zone (Python's GObject package is missing); use: doas tzsetup"
fi

# Open the KDE wallet with the login password, so programs do not ask for a
# wallet password (only after Plasma installed: it brings the PAM module).
[ "$DISPLAY_MANAGER" = sddm ] && sddm_pam_enable pam_kwallet5
if [ "$DISPLAY_MANAGER" = sddm ]; then
	warn "KDE Plasma (Wayland) does not start from the SDDM login screen on FreeBSD (no logind: KWin gets no graphics card); use ly: set DISPLAY_MANAGER=ly in /usr/local/etc/freebsd-setup.conf and run: doas freebsd-setup desktop"
else
	say "KDE Plasma installed - choose 'Plasma (Wayland)' at the login screen (left/right arrow keys)"
fi

true   # (a stage must not end on a failed test: setup.sh runs under set -e)

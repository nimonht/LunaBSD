# Stage: desktop - what every graphical desktop needs: fonts, portals,
# removable drives, keyboard layout and the login screen.

[ "$DESKTOP" = none ] && { say "no desktop selected - skipped"; return 0; }
[ "$HW_DESKTOP" = yes ] || warn "installing a desktop although this machine cannot run it: $HW_DESKTOP_WHY"

say "fonts"
pkg_install noto-basic noto-emoji dejavu liberation-fonts-ttf
pkg_try webfonts                       # Arial, Times New Roman... for documents
# Chinese, Japanese and Korean text on web pages and in file names shows as
# empty boxes without a font that has those characters: one for everybody.
pkg_try noto-sans-sc
case " $INPUT_METHODS ${DESKTOP_LANGUAGE:-} " in
*" zh-cn "*|*" zh-tw "*|*" ja "*|*" ko "*) pkg_try noto-sc noto-tc noto-jp noto-kr ;;
esac

say "desktop plumbing: portals, polkit, keyring, user folders"
pkg_install xdg-utils xdg-user-dirs xdg-desktop-portal polkit xwayland
as_user 'xdg-user-dirs-update' >> "$LOG" 2>&1 || true

say "USB drives, phones and other operating systems' partitions"
pkg_install bsdisks fusefs-ntfs fusefs-exfat fusefs-ext2 fusefs-simple-mtpfs
svc bsdisks
mkdir -p /usr/local/etc/polkit-1/rules.d
install_file "$REPO_DIR/files/desktop/50-freebsd-setup.rules" /usr/local/etc/polkit-1/rules.d/50-freebsd-setup.rules

# Keyboard layout for X11 programs and the SDDM login screen.
if [ -n "${KEYBOARD_LAYOUT:-}" ]; then
	_xkb=$KEYBOARD_LAYOUT _var=""
	case "$_xkb" in us-intl) _xkb=us _var=intl ;; esac
	_kbc=$(mktemp)
	cat > "$_kbc" <<XORG
# Written by FreeBSD-setup.
Section "InputClass"
	Identifier "keyboard"
	MatchIsKeyboard "on"
	Option "XkbLayout" "$_xkb"
	Option "XkbVariant" "$_var"
EndSection
XORG
	sys_file "$_kbc" /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf || true
	rm -f "$_kbc"
fi

# ---- login screen ------------------------------------------------------------
case "$DISPLAY_MANAGER" in
sddm)
	say "login screen: SDDM"
	pkg_install sddm xorg-minimal
	mkdir -p /usr/local/etc/sddm.conf.d
	cat > /usr/local/etc/sddm.conf.d/10-freebsd-setup.conf <<'CONF'
# Written by FreeBSD-setup.
[Theme]
Current=breeze
[Users]
MinimumUid=1001
MaximumUid=60000
CONF
	sysrc sddm_enable=YES >/dev/null
	sysrc -x ly_enable >/dev/null 2>&1 || true
	sed -i '' -E 's|^ttyv1([[:space:]]+)"/usr/libexec/getty Ly"|ttyv1\1"/usr/libexec/getty Pc"|' /etc/ttys
	;;
ly)
	say "login screen: ly (on the second console, ttyv1)"
	pkg_install ly
	sysrc sddm_enable=NO >/dev/null 2>&1 || true
	if ! grep -q '^Ly:' /etc/gettytab; then
		cat >> /etc/gettytab <<'TAB'

# ly login screen (FreeBSD-setup)
Ly:\
	:lo=/usr/local/bin/ly_wrapper:\
	:al=root:
TAB
	fi
	sed -i '' -E 's|^ttyv1[[:space:]]+"/usr/libexec/getty Pc"[[:space:]]+xterm[[:space:]]+on(ifexists)?[[:space:]]+secure|ttyv1	"/usr/libexec/getty Ly"		xterm	on  secure|' /etc/ttys
	grep -q 'getty Ly' /etc/ttys || warn "could not switch ttyv1 to ly in /etc/ttys - see docs/TROUBLESHOOTING.md"
	;;
none)
	say "no login screen: log in on the console and type 'startplasma' or 'hypr-session'" ;;
esac

true   # (a stage must not end on a failed test: setup.sh runs under set -e)

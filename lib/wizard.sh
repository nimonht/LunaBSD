# lib/wizard.sh - the questions, shared by setup.sh and install.sh, plus
# turning "auto" answers into concrete ones. POSIX sh, sourced after
# common.sh, hw.sh and ui.sh.

# Keyboard layouts: XKB name | console keymap | label
WIZ_LAYOUTS='us|us.kbd|English (US)
gb|uk.kbd|English (UK)
us-intl|us.acc.kbd|English (US, international with dead keys)
de|de.kbd|German
fr|fr.kbd|French
es|es.kbd|Spanish
latam|latinamerican.kbd|Spanish (Latin America)
pt|pt.kbd|Portuguese
br|br.kbd|Portuguese (Brazil)
it|it.kbd|Italian
nl|nl.kbd|Dutch
be|be.kbd|Belgian
ch|ch.kbd|Swiss German
se|se.kbd|Swedish
no|no.kbd|Norwegian
dk|dk.kbd|Danish
fi|fi.kbd|Finnish
pl|pl.kbd|Polish
cz|cz.kbd|Czech
hu|hu.102.kbd|Hungarian
ru|ru.kbd|Russian
ua|ua.kbd|Ukrainian
tr|tr.kbd|Turkish
gr|gr.kbd|Greek
jp|jp.kbd|Japanese'

# Languages: language code | system locale | label (ASCII only: the install
# media's text console cannot show other scripts). When FreeBSD has no system
# locale for a language, desktops still show their translations through
# LANGUAGE (see stages/base.sh).
WIZ_LANGS='en|en_US.UTF-8|English
vi|en_US.UTF-8|Vietnamese (Tieng Viet)
de|de_DE.UTF-8|German (Deutsch)
fr|fr_FR.UTF-8|French (Francais)
es|es_ES.UTF-8|Spanish (Espanol)
pt-br|pt_BR.UTF-8|Portuguese, Brazil (Portugues)
pt|pt_PT.UTF-8|Portuguese, Portugal (Portugues)
it|it_IT.UTF-8|Italian (Italiano)
nl|nl_NL.UTF-8|Dutch (Nederlands)
pl|pl_PL.UTF-8|Polish (Polski)
cs|cs_CZ.UTF-8|Czech (Cestina)
sv|sv_SE.UTF-8|Swedish (Svenska)
tr|tr_TR.UTF-8|Turkish (Turkce)
ru|ru_RU.UTF-8|Russian
uk|uk_UA.UTF-8|Ukrainian
zh-cn|zh_CN.UTF-8|Chinese, Simplified
zh-tw|zh_TW.UTF-8|Chinese, Traditional
ja|ja_JP.UTF-8|Japanese
ko|ko_KR.UTF-8|Korean'

wiz_layout_keymap() { printf '%s\n' "$WIZ_LAYOUTS" | awk -F'|' -v k="$1" '$1 == k { print $2; exit }'; }
wiz_lang_locale()   { printf '%s\n' "$WIZ_LANGS" | awk -F'|' -v k="$1" '$1 == k { print $2; exit }'; }

# Input method that suits a language or a time zone
wiz_suggest_im() {
	case "$1" in
	vi|Asia/Ho_Chi_Minh|Asia/Saigon) echo vi ;;
	zh-cn|Asia/Shanghai|Asia/Chongqing|Asia/Urumqi) echo zh-cn ;;
	zh-tw|Asia/Taipei|Asia/Hong_Kong|Asia/Macau) echo zh-tw ;;
	ja|Asia/Tokyo) echo ja ;;
	ko|Asia/Seoul) echo ko ;;
	Asia/Bangkok|Asia/Kolkata|Asia/Calcutta|Asia/Dhaka|Asia/Kathmandu|Asia/Colombo) echo m17n ;;
	esac
}

# ---------------------------------------------------------------- questions ---

wiz_desktop() {
	_def=$DESKTOP
	[ "$_def" = auto ] && { [ "$HW_DESKTOP" = yes ] && _def=kde || _def=none; }
	_txt="Which desktop would you like?"
	[ "$HW_DESKTOP" = yes ] || _txt="$_txt

WARNING: $HW_DESKTOP_WHY.
A graphical desktop will not start on this machine."
	_a=$(ui_menu "Desktop" "$_txt" "$_def" \
		kde "KDE Plasma - familiar and complete (recommended)" \
		hyprland "Hyprland + Caelestia - modern tiling desktop (advanced)" \
		both "Both - choose at the login screen" \
		none "None - text console only") || return 1
	DESKTOP=$_a
}

wiz_extras() {
	_on() { is_yes "$1" && echo on || echo off; }
	_g=$INSTALL_GAMING
	[ "$_g" = auto ] && { [ "$HW_DESKTOP" = yes ] && [ "$HW_ARCH" = amd64 ] && _g=yes || _g=no; }
	_snap=$AUTO_SNAPSHOTS
	_sel=$(ui_check "Extras" "Choose what to install (Space toggles, Enter confirms):" \
		apps "Everyday apps: Firefox, LibreOffice, VLC, GIMP" "$(_on INSTALL_APPS)" \
		printing "Printers and scanners" "$(_on INSTALL_PRINTING)" \
		gaming "Gaming: Steam, Wine/Proton, MangoHud" "$(G=$_g; _on G)" \
		dev "Developer tools: VS Code, compilers" "$(_on INSTALL_DEVTOOLS)" \
		firewall "Firewall: block incoming connections" "$(_on FIREWALL)" \
		snapshots "Automatic ZFS snapshots (undo for files)" "$(S=$_snap; _on S)") || return 1
	INSTALL_APPS=no INSTALL_PRINTING=no INSTALL_GAMING=no INSTALL_DEVTOOLS=no FIREWALL=no AUTO_SNAPSHOTS=no
	for _x in $_sel; do
		case "$_x" in
		apps) INSTALL_APPS=yes ;; printing) INSTALL_PRINTING=yes ;; gaming) INSTALL_GAMING=yes ;;
		dev) INSTALL_DEVTOOLS=yes ;; firewall) FIREWALL=yes ;; snapshots) AUTO_SNAPSHOTS=yes ;;
		esac
	done
}

wiz_terminal() {
	_def=$TERMINAL_STYLE
	[ "$_def" = auto ] && _def=fish
	_a=$(ui_menu "Terminal" "How should the terminal behave and look?
Your login shell is not changed; this applies inside the terminal app." "$_def" \
		fish "Friendly: suggestions as you type, colours, git-aware prompt" \
		zsh "Zsh: the same, and closer to bash for copy-pasted commands" \
		bash "Bash with colours, history search and completion" \
		none "Plain, as FreeBSD ships it") || return 1
	TERMINAL_STYLE=$_a
}

wiz_input_methods() {
	_cur=" $INPUT_METHODS "
	if [ -z "$INPUT_METHODS" ]; then
		_s=$(wiz_suggest_im "${WIZ_LANG:-}"); [ -n "$_s" ] || _s=$(wiz_suggest_im "${TIMEZONE:-}")
		_cur=" $_s "
	fi
	_on() { case "$_cur" in *" $1 "*) echo on ;; *) echo off ;; esac; }
	_sel=$(ui_check "Typing in other languages" "Add input methods for typing non-Latin scripts (switch with Ctrl+Space):" \
		vi "Vietnamese (Telex, VNI)" "$(_on vi)" \
		zh-cn "Chinese - Pinyin" "$(_on zh-cn)" \
		zh-tw "Chinese - Zhuyin/Bopomofo" "$(_on zh-tw)" \
		ja "Japanese" "$(_on ja)" \
		ko "Korean" "$(_on ko)" \
		m17n "Thai, Hindi and other scripts (m17n)" "$(_on m17n)") || return 1
	INPUT_METHODS=$_sel
}

wiz_keyboard() {
	_def=${KEYBOARD_LAYOUT:-us}
	_args=$(printf '%s\n' "$WIZ_LAYOUTS" | awk -F'|' '{ printf "%s\n%s\n", $1, $3 }')
	_old_ifs=$IFS; IFS=$NL
	# shellcheck disable=SC2086
	_a=$(ui_menu "Keyboard" "Keyboard layout:" "$_def" $_args) || { IFS=$_old_ifs; return 1; }
	IFS=$_old_ifs
	KEYBOARD_LAYOUT=$_a
}

wiz_language() {
	_def=${WIZ_LANG:-en}
	_args=$(printf '%s\n' "$WIZ_LANGS" | awk -F'|' '{ printf "%s\n%s\n", $1, $3 }')
	_old_ifs=$IFS; IFS=$NL
	# shellcheck disable=SC2086
	_a=$(ui_menu "Language" "Language for the desktop:" "$_def" $_args) || { IFS=$_old_ifs; return 1; }
	IFS=$_old_ifs
	WIZ_LANG=$_a
	LOCALE=$(wiz_lang_locale "$_a")
	DESKTOP_LANGUAGE=$_a
}

# --------------------------------------------------------- auto -> concrete ---

resolve_config() {
	# The answers as given (before "auto" is resolved), for save_config: a
	# hardware choice saved as "auto" is decided again at every run.
	: "${_SAVE_GPU_DRIVERS:=${GPU_DRIVERS:-auto}}" "${_SAVE_NVIDIA_BRANCH:=${NVIDIA_BRANCH:-auto}}" "${_SAVE_ARC_MAX_GB:=${ARC_MAX_GB:-auto}}"
	[ "$DESKTOP" = auto ] && { [ "$HW_DESKTOP" = yes ] && DESKTOP=kde || DESKTOP=none; }
	case "$DESKTOP" in kde|hyprland|both|none) ;; *) die "DESKTOP must be kde, hyprland, both, none or auto (got '$DESKTOP')" ;; esac
	WANT_KDE=no WANT_HYPR=no
	case "$DESKTOP" in kde) WANT_KDE=yes ;; hyprland) WANT_HYPR=yes ;; both) WANT_KDE=yes WANT_HYPR=yes ;; esac
	if [ "$PKG_BRANCH" = auto ]; then
		PKG_BRANCH=quarterly; [ "$WANT_HYPR" = yes ] && PKG_BRANCH=latest
	fi
	# ly for both desktops: it starts a session on the console it shows,
	# which is what KWin needs to get the graphics card from ConsoleKit2
	# (FreeBSD has no logind). Plasma started by SDDM has no console and
	# stops at once ("Could not determine the active graphical session").
	if [ "$DISPLAY_MANAGER" = auto ]; then
		if [ "$WANT_KDE" = yes ] || [ "$WANT_HYPR" = yes ]; then DISPLAY_MANAGER=ly
		else DISPLAY_MANAGER=none; fi
	fi
	if [ "$INSTALL_GAMING" = auto ]; then
		INSTALL_GAMING=no
		[ "$HW_DESKTOP" = yes ] && [ "$HW_ARCH" = amd64 ] && [ "$DESKTOP" != none ] && INSTALL_GAMING=yes
	fi
	[ "$DESKTOP" = none ] && INSTALL_GAMING=no
	if [ "$GPU_DRIVERS" = auto ]; then
		GPU_DRIVERS=""
		[ -n "$HW_GPU_INTEL" ] && GPU_DRIVERS="$GPU_DRIVERS intel"
		[ -n "$HW_GPU_AMD" ] && GPU_DRIVERS="$GPU_DRIVERS amd"
		[ -n "$HW_GPU_NVIDIA" ] && GPU_DRIVERS="$GPU_DRIVERS nvidia"
		GPU_DRIVERS=$(echo $GPU_DRIVERS)
	fi
	[ "$NVIDIA_BRANCH" = auto ] && NVIDIA_BRANCH=${HW_NVIDIA_BRANCH:-none}
	if [ "${TERMINAL_STYLE:-auto}" = auto ]; then
		TERMINAL_STYLE=none; [ "$DESKTOP" != none ] && TERMINAL_STYLE=fish
	fi
	case "$TERMINAL_STYLE" in fish|zsh|bash|none) ;; *) die "TERMINAL_STYLE must be fish, zsh, bash, none or auto (got '$TERMINAL_STYLE')" ;; esac
	if [ "$ARC_MAX_GB" = auto ]; then
		ARC_MAX_GB=$(( HW_RAM_MB / 4096 ))
		[ "$ARC_MAX_GB" -lt 1 ] && ARC_MAX_GB=1
		[ "$ARC_MAX_GB" -gt 8 ] && ARC_MAX_GB=8
	fi
	return 0
}

# save_config file   store the answers so later runs ask nothing new
save_config() {
	mkdir -p "$(dirname "$1")"
	{
		echo "# Answers saved by FreeBSD-setup on $(date '+%Y-%m-%d %H:%M'). Edit and re-run"
		echo "# 'doas freebsd-setup --yes' to apply changes. See lib/defaults.conf for help."
		for _k in TARGET_USER DESKTOP INSTALL_CAELESTIA CAELESTIA_SHELL_REF CAELESTIA_CLI_REF \
			CAELESTIA_DOTS_REF PKG_BRANCH DISPLAY_MANAGER INSTALL_APPS INSTALL_PRINTING \
			INSTALL_GAMING INSTALL_DEVTOOLS FIREWALL AUTO_SNAPSHOTS INPUT_METHODS \
			KEYBOARD_LAYOUT LOCALE DESKTOP_LANGUAGE RUN_FREEBSD_UPDATE \
			TERMINAL_STYLE TERMINAL_GREETING; do
			eval "printf '%s=\"%s\"\n' $_k \"\${$_k:-}\""
		done
		printf 'GPU_DRIVERS="%s"\n' "${_SAVE_GPU_DRIVERS:-${GPU_DRIVERS:-auto}}"
		printf 'NVIDIA_BRANCH="%s"\n' "${_SAVE_NVIDIA_BRANCH:-${NVIDIA_BRANCH:-auto}}"
		printf 'ARC_MAX_GB="%s"\n' "${_SAVE_ARC_MAX_GB:-${ARC_MAX_GB:-auto}}"
	} > "$1"
}

wiz_summary_text() {
	_ims=${INPUT_METHODS:-none}
	cat <<EOF
Desktop:          $DESKTOP$( [ "$WANT_HYPR" = yes ] && is_yes INSTALL_CAELESTIA && echo " (Hyprland with Caelestia shell)")
Login screen:     $DISPLAY_MANAGER
Graphics drivers: ${GPU_DRIVERS:-none}$( [ -n "$HW_GPU_NVIDIA" ] && echo " (NVIDIA branch: $NVIDIA_BRANCH)")
Packages:         $PKG_BRANCH branch
Everyday apps:    $INSTALL_APPS
Printing:         $INSTALL_PRINTING
Gaming:           $INSTALL_GAMING
Developer tools:  $INSTALL_DEVTOOLS
Firewall:         $FIREWALL
Snapshots:        $AUTO_SNAPSHOTS
Terminal style:   $TERMINAL_STYLE
Input methods:    $_ims
Keyboard layout:  ${KEYBOARD_LAYOUT:-unchanged}
EOF
}

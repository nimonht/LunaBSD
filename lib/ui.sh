# lib/ui.sh - dialogs for the wizard. POSIX sh, sourced.
#
# Three modes, picked by ui_init:
#   dialog  full-screen menus with bsddialog(1) (part of FreeBSD since 14.0)
#   text    plain prompts (no bsddialog, or TERM=dumb)
#   auto    no questions at all: every dialog returns its default
#           (ASSUME_YES=yes, used for unattended runs and tests)
#
# Each function prints the answer on stdout and returns non-zero when the
# user cancels.

: "${UI_TITLE:=FreeBSD-setup}"

ui_init() {
	if is_yes ASSUME_YES; then UI_MODE=auto
	elif [ ! -t 0 ]; then UI_MODE=auto
	elif command -v bsddialog >/dev/null 2>&1 && [ "${TERM:-dumb}" != dumb ] && [ "${UI_MODE:-}" != text ]; then UI_MODE=dialog
	else UI_MODE=text; fi
}

# ui_restore_tty   turn terminal echo back on if a password prompt was
# interrupted (call it from the script's EXIT trap)
UI_ECHO_OFF=no
ui_restore_tty() {
	if [ "$UI_ECHO_OFF" = yes ]; then stty echo < /dev/tty 2>/dev/null || true; UI_ECHO_OFF=no; fi
}

# _bd args...   run bsddialog with the screen on the terminal and the answer
# on stdout
_bd() {
	local _out _rc
	_out=$(bsddialog --backtitle "$UI_TITLE" --cr-wrap --output-fd 4 "$@" 4>&1 1>/dev/tty 2>/dev/tty)
	_rc=$?
	printf '%s' "$_out"
	return $_rc
}

_text_wrap() { printf '\n== %s ==\n%s\n' "$1" "$2" > /dev/tty; }

# ui_msg title text
ui_msg() {
	case "$UI_MODE" in
	dialog) _bd --title "$1" --msgbox "$2" 0 0 >/dev/null ;;
	text)   _text_wrap "$1" "$2"; printf 'Press Enter to continue. ' > /dev/tty; read -r _ < /dev/tty ;;
	*)      printf '%s: %s\n' "$1" "$2" | head -3 >&2 ;;
	esac
	return 0
}

# ui_text title file   scrollable text (reports)
ui_text() {
	case "$UI_MODE" in
	dialog) _bd --title "$1" --textbox "$2" 0 0 >/dev/null ;;
	text)   printf '\n== %s ==\n' "$1" > /dev/tty; cat "$2" > /dev/tty
		printf 'Press Enter to continue. ' > /dev/tty; read -r _ < /dev/tty ;;
	*)      cat "$2" >&2 ;;
	esac
	return 0
}

# ui_yesno title text [yes|no]   -> status 0 for yes; default answer last
ui_yesno() {
	local _def _a
	_def=${3:-yes}
	case "$UI_MODE" in
	dialog)
		if [ "$_def" = no ]; then _bd --title "$1" --default-no --yesno "$2" 0 0 >/dev/null
		else _bd --title "$1" --yesno "$2" 0 0 >/dev/null; fi ;;
	text)
		_text_wrap "$1" "$2"
		while :; do
			if [ "$_def" = yes ]; then printf '[Y/n] ' > /dev/tty; else printf '[y/N] ' > /dev/tty; fi
			read -r _a < /dev/tty || return 1
			case "${_a:-$_def}" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
		done ;;
	*)	[ "$_def" = yes ] ;;
	esac
}

# ui_menu title text default tag description [tag description ...]
ui_menu() {
	_title=$1 _txt=$2 _def=$3; shift 3
	case "$UI_MODE" in
	dialog)
		_bd --title "$_title" --default-item "$_def" --menu "$_txt" 0 0 0 "$@" ;;
	text)
		_text_wrap "$_title" "$_txt"
		_i=0
		while [ $# -gt 1 ]; do
			_i=$((_i + 1)); eval "_tag$_i=\$1"
			_mark=" "; [ "$1" = "$_def" ] && _mark="*"
			printf ' %s%2d) %s\n' "$_mark" "$_i" "$2" > /dev/tty
			shift 2
		done
		while :; do
			printf 'Choice [Enter = *]: ' > /dev/tty
			read -r _a < /dev/tty || return 1
			[ -z "$_a" ] && { printf '%s' "$_def"; return 0; }
			case "$_a" in *[!0-9]*) continue ;; esac
			[ "$_a" -ge 1 ] && [ "$_a" -le "$_i" ] && { eval "printf '%s' \"\$_tag$_a\""; return 0; }
		done ;;
	*)	printf '%s' "$_def" ;;
	esac
}

# ui_check title text tag description on|off [...]   -> selected tags,
# space separated
ui_check() {
	_title=$1 _txt=$2; shift 2
	case "$UI_MODE" in
	dialog)
		# (not piped: Cancel must still return non-zero)
		_o=$(_bd --title "$_title" --separate-output --checklist "$_txt" 0 0 0 "$@") || return 1
		printf '%s' "$_o" | tr '\n' ' ' | sed 's/ $//' ;;
	text)
		_text_wrap "$_title" "$_txt"
		_sel=""
		while [ $# -gt 2 ]; do
			_d=n; [ "$3" = on ] && _d=y
			printf '  %s? ' "$2" > /dev/tty
			[ "$_d" = y ] && printf '[Y/n] ' > /dev/tty || printf '[y/N] ' > /dev/tty
			read -r _a < /dev/tty || return 1
			case "${_a:-$_d}" in [Yy]*) _sel="$_sel${_sel:+ }$1" ;; esac
			shift 3
		done
		printf '%s' "$_sel" ;;
	*)
		_sel=""
		while [ $# -gt 2 ]; do [ "$3" = on ] && _sel="$_sel${_sel:+ }$1"; shift 3; done
		printf '%s' "$_sel" ;;
	esac
}

# ui_input title text default
ui_input() {
	case "$UI_MODE" in
	dialog) _bd --title "$1" --inputbox "$2" 0 0 "$3" ;;
	text)   _text_wrap "$1" "$2"; printf '[%s] ' "$3" > /dev/tty; read -r _a < /dev/tty || return 1; printf '%s' "${_a:-$3}" ;;
	*)      printf '%s' "$3" ;;
	esac
}

# ui_password title text   (never has a default)
ui_password() {
	case "$UI_MODE" in
	dialog) _bd --title "$1" --insecure --passwordbox "$2" 0 0 ;;
	text)   _text_wrap "$1" "$2"
		# (runs in a $(...) subshell: restore echo here on Ctrl-C as well)
		trap 'stty echo < /dev/tty; exit 130' INT TERM
		stty -echo < /dev/tty; _rc=0; read -r _a < /dev/tty || _rc=$?; stty echo < /dev/tty
		trap - INT TERM
		echo > /dev/tty; printf '%s' "$_a"; return $_rc ;;
	*)      return 1 ;;
	esac
}

# ui_info title text   short notice that does not wait
ui_info() {
	case "$UI_MODE" in
	dialog) _bd --title "$1" --infobox "$2" 0 0 >/dev/null ;;
	*)      printf '%s\n' "$2" ;;
	esac
	return 0
}

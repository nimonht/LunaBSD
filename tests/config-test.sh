#!/bin/sh
# tests/config-test.sh - resolve_config (lib/wizard.sh): every desktop choice
# must switch on the right stages and login screen. Runs anywhere with a
# POSIX sh:   sh tests/config-test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FBS_LIB="$HERE/../lib"
LOG=/dev/null
. "$FBS_LIB/common.sh"
. "$FBS_LIB/hw.sh"
. "$FBS_LIB/ui.sh"
. "$FBS_LIB/wizard.sh"

pass=0 fail=0
# t DESKTOP HW_DESKTOP  "expected: WANT_KDE WANT_HYPR DISPLAY_MANAGER PKG_BRANCH INSTALL_GAMING DESKTOP"
t() {
	_got=$(
		. "$FBS_LIB/defaults.conf"
		DESKTOP=$1 HW_DESKTOP=$2 HW_ARCH=amd64 HW_RAM_MB=16384
		HW_GPU_INTEL=x HW_GPU_AMD="" HW_GPU_NVIDIA="" HW_NVIDIA_BRANCH=""
		resolve_config
		echo "$WANT_KDE $WANT_HYPR $DISPLAY_MANAGER $PKG_BRANCH $INSTALL_GAMING $DESKTOP"
	)
	if [ "$_got" = "$3" ]; then pass=$((pass + 1)); echo "ok   DESKTOP=$1 (desktop possible: $2)"
	else fail=$((fail + 1)); echo "FAIL DESKTOP=$1: got '$_got', want '$3'"; fi
}

t kde      yes "yes no ly quarterly yes kde"
t hyprland yes "no yes ly latest yes hyprland"
t both     yes "yes yes ly latest yes both"
t none     yes "no no none quarterly no none"
t auto     yes "yes no ly quarterly yes kde"
t auto     no  "no no none quarterly no none"

# Terminal style: auto is fish with a desktop and none without; an explicit
# choice is kept; anything else stops.
ts() { # ts DESKTOP TERMINAL_STYLE expected
	_got=$(
		. "$FBS_LIB/defaults.conf"
		DESKTOP=$1 TERMINAL_STYLE=$2 HW_DESKTOP=yes HW_ARCH=amd64 HW_RAM_MB=16384
		HW_GPU_INTEL=x HW_GPU_AMD="" HW_GPU_NVIDIA="" HW_NVIDIA_BRANCH=""
		resolve_config >/dev/null 2>&1
		echo "$TERMINAL_STYLE"
	) || _got=rejected
	if [ "$_got" = "$3" ]; then pass=$((pass + 1)); echo "ok   DESKTOP=$1 TERMINAL_STYLE=$2 -> $3"
	else fail=$((fail + 1)); echo "FAIL DESKTOP=$1 TERMINAL_STYLE=$2: got '$_got', want '$3'"; fi
}
ts kde      auto fish
ts hyprland auto fish
ts none     auto none
ts kde      zsh  zsh
ts both     bash bash
ts kde      none none
ts kde      tcsh rejected

# An invalid choice must stop, not fall through to some default.
if (. "$FBS_LIB/defaults.conf"; DESKTOP=gnome HW_DESKTOP=yes HW_ARCH=amd64 HW_RAM_MB=8192
	HW_GPU_INTEL="" HW_GPU_AMD="" HW_GPU_NVIDIA="" HW_NVIDIA_BRANCH=""; resolve_config) >/dev/null 2>&1; then
	fail=$((fail + 1)); echo "FAIL an unknown DESKTOP was accepted"
else
	pass=$((pass + 1)); echo "ok   unknown DESKTOP is rejected"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

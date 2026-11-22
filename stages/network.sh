# Stage: network - Wi-Fi regulatory domain and a graphical network manager.

# Wi-Fi channels and power limits differ per country: derive the country
# from the time zone, for any wlan configured in rc.conf.
_tz=$(cat /var/db/zoneinfo 2>/dev/null || true)
_cc=""
[ -n "$_tz" ] && _cc=$(awk -v tz="$_tz" '$1 !~ /^#/ && $3 == tz { split($1, c, ","); print c[1]; exit }' \
	/usr/share/zoneinfo/zone1970.tab 2>/dev/null)
for _w in $(sysrc -a 2>/dev/null | sed -n 's/^\(create_args_wlan[0-9]*\):.*/\1/p;s/^ifconfig_\(wlan[0-9]*\):.*/\1/p' | sort -u); do
	case "$_w" in create_args_*) continue ;; esac
	if [ -n "$_cc" ] && ! sysrc -n "create_args_$_w" 2>/dev/null | grep -q country; then
		_old=$(sysrc -n "create_args_$_w" 2>/dev/null || true)
		sysrc "create_args_$_w=${_old:+$_old }country $_cc" >/dev/null
		say "Wi-Fi $_w: regulatory domain $_cc (from time zone $_tz)"
	fi
done

# NetworkMgr: a tray applet to pick Wi-Fi networks, written for FreeBSD.
if [ "$WANT_KDE" = yes ]; then
	pkg_try networkmgr
fi

true   # (a stage must not end on a failed test: setup.sh runs under set -e)

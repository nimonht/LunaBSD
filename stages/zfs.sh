# Stage: zfs - boot environments, automatic snapshots, scrub, TRIM, ARC cap.

POOL=$(root_pool)
if [ -z "$POOL" ]; then
	say "the system is not installed on ZFS - snapshots and boot environments skipped"
	return 0
fi

say "pool '$POOL': autotrim on, monthly scrub, ARC capped at ${ARC_MAX_GB} GiB"
zpool set autotrim=on "$POOL" 2>/dev/null || true
ARC_BYTES=$(( ARC_MAX_GB * 1024 * 1024 * 1024 ))
loader_set vfs.zfs.arc.max "$ARC_BYTES"
if is_live; then
	sysctl vfs.zfs.arc.max="$ARC_BYTES" >/dev/null 2>&1 || sysctl vfs.zfs.arc_max="$ARC_BYTES" >/dev/null 2>&1 || true
fi

set_kv /etc/periodic.conf daily_scrub_zfs_enable '"YES"'
set_kv /etc/periodic.conf daily_scrub_zfs_default_threshold '"30"'   # days between scrubs
set_kv /etc/periodic.conf daily_status_zfs_enable '"YES"'
set_kv /etc/periodic.conf daily_trim_zfs_enable '"NO"'               # autotrim handles it

if is_yes AUTO_SNAPSHOTS; then
	pkg_install zfstools
	# Deleted files keep using space until the last snapshot holding them is
	# gone: two monthly snapshots keep that to about two months. A system
	# that already keeps more (older FreeBSD-setup versions kept 6) keeps its
	# number: lowering it would delete those older snapshots without asking.
	_monthly=$(awk '$7 == "zfs-auto-snapshot" && $8 == "monthly" { print $9 }' \
		/usr/local/etc/cron.d/zfs-auto-snapshot 2>/dev/null | head -1)
	case "$_monthly" in ''|*[!0-9]*) _monthly=2 ;; esac
	[ "$_monthly" -lt 2 ] && _monthly=2
	say "automatic snapshots: 4x15min, 24 hourly, 7 daily, 4 weekly, $_monthly monthly"
	_cron=$(mktemp)
	cat > "$_cron" <<CRON
# Rolling ZFS snapshots (zfstools). Written by FreeBSD-setup.
SHELL=/bin/sh
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
15,30,45 * * * * root zfs-auto-snapshot frequent  4
0        * * * * root zfs-auto-snapshot hourly   24
7        0 * * * root zfs-auto-snapshot daily     7
14       0 * * 7 root zfs-auto-snapshot weekly    4
28       0 1 * * root zfs-auto-snapshot monthly   $_monthly
CRON
	# Never replace a schedule the owner wrote themselves.
	sys_file "$_cron" /usr/local/etc/cron.d/zfs-auto-snapshot || true
	rm -f "$_cron"
	# Snapshot everything on the pool, except data that is pointless to keep.
	zfs set com.sun:auto-snapshot=true "$POOL"
	for ds in tmp var/tmp var/crash var/audit usr/obj usr/ports usr/src; do
		zfs list -H "$POOL/$ds" >/dev/null 2>&1 && zfs set com.sun:auto-snapshot=false "$POOL/$ds"
	done
	is_live && { service cron restart >> "$LOG" 2>&1 || true; }
fi

# sysup: update the whole system with a safety net (new boot environment).
install_file "$REPO_DIR/files/bin/sysup" /usr/local/sbin/sysup 755
install_file "$REPO_DIR/files/bin/snap" /usr/local/sbin/snap 755
install_file "$REPO_DIR/files/bin/secureboot" /usr/local/sbin/secureboot 755
pkg_try httm
say "installed 'sysup' (safe system upgrade) and 'snap' (manual snapshots/rollback)"

true   # (a stage must not end on a failed test: setup.sh runs under set -e)

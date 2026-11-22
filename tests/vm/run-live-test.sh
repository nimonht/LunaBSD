#!/bin/sh
#
# tests/vm/run-live-test.sh - boot the LunaBSD live ISO in QEMU and check
# that the live system starts: boot menu -> ramdisk -> system copied into
# memory -> reroot -> live session. A plain QEMU guest has no KMS graphics,
# so the expected session is the installer alone on a basic framebuffer
# (scfb on UEFI, vesa on BIOS); the test saves a picture of the screen.
#
#   sh tests/vm/run-live-test.sh iso/out/lunabsd-0.1-amd64.iso [uefi|bios]
#
# MEDIA=usb attaches the ISO as a USB stick (the hybrid GPT and its EFI
# partition, as when written with Rufus or dd) instead of a DVD.
#
# PLASMA=fallback (UEFI) makes the live system go the KDE Plasma way although
# QEMU has no graphics driver (luna.test_plasma): the live user is logged in
# on the first console, Plasma is tried and fails, and the installer must
# take over by itself (iso/live/luna-plasma, luna_live fallback).
#
# Needs qemu-system-x86_64, OVMF (for uefi), python3. Works without KVM
# (slow: several minutes). Result: tests/vm/live-work/serial.log and
# screen.png; exit status 0 when every check passed.
set -eu
ISO=$(realpath "${1:?usage: run-live-test.sh ISO [uefi|bios]}")
FW=${2:-uefi}
HERE=$(cd "$(dirname "$0")" && pwd)
W="${WORK:-$HERE/live-work}"
OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
ACCEL=tcg,thread=multi CPU=Westmere
[ -w /dev/kvm ] && ACCEL=kvm CPU=max

rm -rf "$W"; mkdir -p "$W"
W=$(cd "$W" && pwd)      # absolute: QEMU runs from / once daemonized
FWARGS=""
if [ "$FW" = uefi ]; then
	cp "$OVMF_VARS" "$W/vars.fd"
	FWARGS="-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE -drive if=pflash,format=raw,file=$W/vars.fd"
fi

# Checks run as root on the live system's serial console. (What the ramdisk
# and the start scripts print goes to the screen only, so the serial line
# is used from the login prompt on, and the checks look at the result.)
checks="printf 'CHECKS-%s\\n' BEGIN; printf 'session=%s\\n' \"\$(cat /var/run/luna-live/session)\"; \
printf 'reason=%s\\n' \"\$(cat /var/run/luna-live/reason)\"; mount -p | head -3; \
zpool list -H -o name,size,alloc lunalive; . /etc/os-release; echo \"\$PRETTY_NAME\"; \
sleep 150; pgrep -lf 'Xorg|sddm|luna-installer|openbox' | cut -c1-90; \
printf 'after=%s\\n' \"\$(cat /var/run/luna-live/session)\"; printf 'reason2=%s\\n' \"\$(cat /var/run/luna-live/reason)\"; \
grep -E -v 'dbus-daemon|qt.qpa.wayland' /var/run/luna-live/plasma.log 2>/dev/null | sed 's/^/plasma: /' | head -150; grep '^ttyv0' /etc/ttys; \
ls /usr/local/etc/sddm.conf.d /usr/local/etc/X11/xorg.conf.d; \
grep -h '(EE)' /var/log/Xorg.0.log 2>/dev/null | head -5; \
glabel status -s | awk '\$1 ~ /^iso9660\// { print \"media=\" \$3 }'; \
printf 'offered=%s\\n' \"\$(su -m luna -c 'doas /bin/sh /usr/local/share/freebsd-setup/install.sh --probe' | awk -F'\\t' '\$1 == \"disk\" { printf \"%s \", \$2 }')\"; \
printf 'CHECKS-%s\\n' DONE"
python3 - "$W/steps.json" "$FW" "$checks" "${PLASMA:-}" <<'PY'
import json, sys
out, fw, checks, plasma = sys.argv[1:5]
steps = []
if fw == "uefi":
    # the boot menu is on the serial line too (OVMF); send the kernel there
    steps += [[r"Escape to loader prompt", "3", 900],
              [r"OK", 'set console="comconsole,efi"\r', 300]]
    if plasma == "fallback":
        steps += [[r"OK", "set luna.test_plasma=1\r", 60]]
    steps += [[r"OK", "boot\r", 60]]
steps += [[r"login:", "root\r", 5400],
          [r"#\s*$", checks + "\r", 300],
          [r"CHECKS-DONE", "", 900]]
json.dump(steps, open(out, "w"))
PY

MEDIAARGS="-drive file=$ISO,media=cdrom,readonly=on -boot d"
if [ "${MEDIA:-dvd}" = usb ]; then
	# Writable, as a real stick: UEFI firmware writes the backup GPT that a
	# hybrid ISO lacks, and finds no partitions on a read-only one.
	qemu-img create -q -f qcow2 -b "$ISO" -F raw "$W/stick.qcow2"
	MEDIAARGS="-device qemu-xhci -drive if=none,id=stick,file=$W/stick.qcow2,format=qcow2 -device usb-storage,drive=stick,bootindex=0"
fi
# An empty disk to install on: the installer must offer it, and not the stick.
qemu-img create -q -f qcow2 "$W/target.qcow2" 40G
# shellcheck disable=SC2086
qemu-system-x86_64 -machine q35 -accel "$ACCEL" -cpu "$CPU" -smp 4 -m "${VM_MEM:-6G}" $FWARGS \
	$MEDIAARGS -drive file="$W/target.qcow2",format=qcow2,if=virtio \
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 -vga std \
	-display none -serial unix:"$W/ser.sock",server=on,wait=off \
	-monitor unix:"$W/mon.sock",server=on,wait=off -daemonize -pidfile "$W/qemu.pid"
# BIOS boots: the kernel's console is the screen; the serial line only gets a
# login prompt once the live system runs (ttyu0 is "onifconsole" -> not
# there). Then the test can only wait and take a picture.
rc=0
if [ "$FW" = uefi ]; then
	python3 "$HERE/drive.py" "$W/ser.sock" "$W/serial.log" "$W/steps.json" --stop || rc=$?
else
	sleep "${BIOS_WAIT:-900}"
fi
python3 - "$W/mon.sock" "$W/screen.ppm" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.5); s.recv(65536)
s.sendall(("screendump %s\n" % sys.argv[2]).encode()); time.sleep(2); s.sendall(b"quit\n"); time.sleep(1)
PY
python3 -c "
from PIL import Image; import sys
Image.open('$W/screen.ppm').save('$W/screen.png')" 2>/dev/null || cp "$W/screen.ppm" "$W/screen.png"
if [ "$FW" != uefi ]; then
	# no serial login on BIOS boots: there is no log to check, only the picture
	echo "screen: $W/screen.png (BIOS: look at it, nothing is checked)"
	exit 0
fi
[ "$rc" -eq 0 ] || { echo "FAIL: the live system did not get to the checks (see $W/serial.log)"; exit 1; }
log=$(tr -d '\r' < "$W/serial.log" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g')
fail=0
check() { if printf '%s\n' "$log" | grep -a -q -E "$2"; then echo "ok:   $1"; else echo "FAIL: $1"; fail=1; fi; }
check "rerooted into the system copied into memory" '^lunalive[[:space:]]+/[[:space:]]+zfs'
if [ "${PLASMA:-}" = fallback ]; then
	check "the live user was logged in on the first console, Plasma tried" '^plasma: == .*starting KDE Plasma .* on /dev/ttyv0 as luna'
	check "Plasma ran inside a ConsoleKit2 session" '^plasma: == ConsoleKit2 sessions'
	check "Plasma itself started (startplasma-wayland)" '^plasma: startplasma-wayland: Shutting down'
	check "Plasma's messages are kept" '^plasma: == .*Plasma ended'
	check "Plasma failed (no graphics driver): the installer took over" '^after=installer'
	check "the installer says why" '^reason2=KDE Plasma did not start'
	check "the first console has its normal login back" '^ttyv0[[:space:]]+"/usr/libexec/getty Pc"'
else
	check "installer session chosen (no KMS in QEMU)" '^session=installer'
fi
check "os-release names LunaBSD" '^LunaBSD [0-9.]+ \(FreeBSD 15'
check "X server running" '^[0-9]+ .*Xorg'
check "installer running" '^[0-9]+ .*luna-installer'
# The installer must never offer the stick it runs from (install.sh's
# disk_candidates; after the reroot nothing on the stick is mounted).
media=$(printf '%s\n' "$log" | sed -n 's/^media=\([a-z]*[0-9]*\).*/\1/p' | head -1)
offered=$(printf '%s\n' "$log" | sed -n 's/^offered=//p' | tail -1)
check "the empty disk is offered for installing" '^offered=.*vtbd0'
if [ -n "$media" ] && ! printf ' %s ' "$offered" | grep -q " $media "; then
	echo "ok:   the live media ($media) is not offered for installing (offered: ${offered:-none})"
else
	echo "FAIL: the live media (${media:-not found}) is offered for installing: $offered"; fail=1
fi
echo "screen: $W/screen.png"
exit "$fail"

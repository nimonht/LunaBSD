#!/bin/sh
#
# iso/build-in-vm.sh - build the LunaBSD ISO from Linux (or any system with
# QEMU): boots FreeBSD's official cloud image in a virtual machine, runs
# iso/build.sh in it, and copies the ISO back. CI uses this too.
#
#   sh iso/build-in-vm.sh
#
# Needs: qemu-system-x86_64, qemu-img, xz, curl, ssh/ssh-keygen and one of
# genisoimage, mkisofs or xorriso. With KVM (/dev/kvm) it takes about as long
# as a native build; without, several hours.
# Result: iso/out/ (as iso/build.sh). The VM's files: iso/vm/ (reused).
#
# Environment (besides iso/build.sh's, which are passed on):
#   VM_DIR=DIR        where the VM lives (default iso/vm)
#   VM_MEM=MB         memory of the VM (default 8192)
#   VM_CPUS=N         processors (default: all)
#   VM_SSH_PORT=N     port on 127.0.0.1 for SSH into the VM (default 2224)
#   VM_KEEP=yes       leave the VM running afterwards
#   BUILD_PROXY=URL   HTTPS proxy as seen from inside the VM (e.g.
#                     http://10.0.2.2:3128); its CA goes in EXTRA_CA
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$HERE")
. "$REPO_DIR/distro.conf"
REL=${FREEBSD_RELEASE}
D=${VM_DIR:-$HERE/vm}
OUT=${OUT:-$HERE/out}
PORT=${VM_SSH_PORT:-2224}
IMG_URL="https://download.freebsd.org/releases/VM-IMAGES/$REL/amd64/Latest"
IMG="FreeBSD-$REL-amd64-BASIC-CLOUDINIT-ufs.qcow2"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'build-in-vm.sh: %s\n' "$*" >&2; exit 1; }
for t in qemu-system-x86_64 qemu-img xz curl ssh ssh-keygen; do
	command -v "$t" >/dev/null 2>&1 || die "$t is missing"
done
mkiso=""
for t in genisoimage mkisofs xorrisofs; do command -v "$t" >/dev/null 2>&1 && { mkiso=$t; break; }; done
[ -n "$mkiso" ] || die "genisoimage, mkisofs or xorriso is needed (for the cloud-init disk)"
mkdir -p "$D" "$OUT"

SSH="ssh -i $D/ssh_key -p $PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20 -o ServerAliveInterval=30 root@127.0.0.1"
running() { [ -f "$D/qemu.pid" ] && kill -0 "$(cat "$D/qemu.pid")" 2>/dev/null; }

if ! running; then
	if [ ! -f "$D/disk.qcow2" ]; then
		log "Downloading FreeBSD $REL's VM image"
		curl -sfL -o "$D/CHECKSUM.SHA256" "$IMG_URL/CHECKSUM.SHA256" || die "could not download $IMG_URL/CHECKSUM.SHA256"
		[ -f "$D/$IMG.xz" ] || curl -fL -o "$D/$IMG.xz" "$IMG_URL/$IMG.xz"
		want=$(sed -n "s/^SHA256 ($IMG.xz) = //p" "$D/CHECKSUM.SHA256")
		have=$(sha256sum "$D/$IMG.xz" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$D/$IMG.xz" | cut -d' ' -f1)
		[ -n "$want" ] && [ "$want" = "$have" ] || die "$IMG.xz does not match its checksum"
		xz -dc "$D/$IMG.xz" > "$D/disk.qcow2"
		qemu-img resize -q "$D/disk.qcow2" 80G      # the image grows to fill it at first start
	fi
	[ -f "$D/ssh_key" ] || ssh-keygen -q -t ed25519 -N "" -C lunabsd-build-vm -f "$D/ssh_key"
	# cloud-init (FreeBSD's nuageinit): root may log in with this key only.
	rm -rf "$D/cidata"; mkdir -p "$D/cidata"
	printf 'instance-id: lunabsd-build\nlocal-hostname: lunabsd-build\n' > "$D/cidata/meta-data"
	{
		echo '#!/bin/sh'
		echo 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'
		echo "echo '$(cat "$D/ssh_key.pub")' > /root/.ssh/authorized_keys"
		echo 'chmod 600 /root/.ssh/authorized_keys'
		echo "printf 'PermitRootLogin prohibit-password\nUseDNS no\n' >> /etc/ssh/sshd_config"
		echo 'sysrc sshd_enable=YES; service sshd restart || service sshd start'
	} > "$D/cidata/user-data"
	case "$mkiso" in
	xorrisofs) xorrisofs -quiet -V cidata -J -r -o "$D/cidata.iso" "$D/cidata" ;;
	*) "$mkiso" -quiet -V cidata -J -r -o "$D/cidata.iso" "$D/cidata" ;;
	esac
	accel=tcg,thread=multi cpu=Westmere      # (FreeBSD 15 panics on QEMU's "max" CPU under TCG)
	[ -w /dev/kvm ] && accel=kvm cpu=host
	log "Starting the build VM ($accel)"
	qemu-system-x86_64 -machine q35 -accel "$accel" -cpu "$cpu" -smp "${VM_CPUS:-$(nproc 2>/dev/null || echo 2)}" \
		-m "${VM_MEM:-8192}" \
		-drive file="$D/disk.qcow2",format=qcow2,if=virtio,cache=unsafe,discard=unmap \
		-drive file="$D/cidata.iso",format=raw,if=virtio,readonly=on \
		-netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$PORT"-:22 -device virtio-net-pci,netdev=n0 \
		-display none -serial file:"$D/serial.log" -pidfile "$D/qemu.pid" -daemonize
fi

log "Waiting for the VM"
i=0
until $SSH true 2>/dev/null; do
	i=$((i + 1)); [ $i -lt 180 ] || die "no SSH after 15 minutes (see $D/serial.log)"
	sleep 5
done

log "Copying the repository into the VM"
$SSH 'rm -rf /root/luna && mkdir -p /root/luna'
(cd "$REPO_DIR" && tar -cf - --exclude ./.git --exclude ./iso/work --exclude ./iso/out --exclude ./iso/vm \
	--exclude ./tests/vm/work --exclude './tests/vm/live-work*' --exclude './tests/vm/sb-work*' .) | $SSH 'tar -xf - -C /root/luna'
if [ -n "${EXTRA_CA:-}" ]; then
	$SSH 'cat > /root/build-ca.pem' < "$EXTRA_CA"
fi

# iso/build.sh's settings, passed on when set here.
envs=""
for v in FREEBSD_RELEASE PKG_BRANCH PKG_SITE DIST_SITE PATCH_BASE ZSTD_LEVEL STEPS SECURE_BOOT; do
	eval "_v=\${$v:-}"
	# shellcheck disable=SC2154
	[ -n "$_v" ] && envs="$envs $v='$_v'"
done
[ -n "${EXTRA_CA:-}" ] && envs="$envs EXTRA_CA=/root/build-ca.pem SSL_CA_CERT_FILE=/root/build-ca.pem"
# The Secure Boot signing key goes in for the build and is removed after.
if [ -n "${SB_KEY:-}" ] && [ -n "${SB_CERT:-}" ]; then
	$SSH 'umask 077 && mkdir -p /root/sb && cat > /root/sb/key.pem' < "$SB_KEY"
	$SSH 'cat > /root/sb/cert.pem' < "$SB_CERT"
	envs="$envs SB_KEY=/root/sb/key.pem SB_CERT=/root/sb/cert.pem"
	# (also after a failed build: the VM's disk is reused)
	trap '$SSH "rm -rf /root/sb" 2>/dev/null || true' EXIT
fi
[ -n "${BUILD_PROXY:-}" ] && envs="$envs HTTPS_PROXY='$BUILD_PROXY' https_proxy='$BUILD_PROXY'"

log "Building (output follows)"
$SSH "cd /root/luna && env WORK=/build/work OUT=/build/out $envs sh iso/build.sh"
$SSH 'rm -rf /root/sb'

log "Copying the ISO out"
for f in $($SSH 'ls /build/out'); do
	$SSH "cat /build/out/$f" > "$OUT/$f"
done
(cd "$OUT" && sha256sum -c ./*.sha256 2>/dev/null | sed 's/: OK$/: checksum OK/' || true)
if [ "${VM_KEEP:-no}" != yes ]; then
	$SSH 'shutdown -p now' 2>/dev/null || true
fi
log "done: $OUT"

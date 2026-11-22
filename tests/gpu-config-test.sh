#!/bin/sh
# tests/gpu-config-test.sh - which X11 graphics configuration gpu-xorg-config
# writes for recorded machines, and that it follows a hardware change.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
D=$(mktemp -d); trap 'rm -rf "$D" "$D.mux"' EXIT
fail=0
t() { # fixture nvidia-x-driver expected-file|none [expected text]
	HW_FIXTURES="$HERE/fixtures/$1/" FBS_LIB="$HERE/../lib" FBS_XORG_DIR="$D" FBS_NVIDIA_X=$2 \
		sh "$HERE/../files/bin/gpu-xorg-config" || { echo "FAIL $1: script failed"; fail=1; return; }
	got=$(cd "$D" && ls | tr '\n' ' ')
	want="$3 "; [ "$3" = none ] && want=""
	if [ "$got" != "$want" ]; then echo "FAIL $1 (nvidia X driver: $2): files '$got', want '$want'"; fail=1
	elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "$D/$3"; then echo "FAIL $1: $3 lacks '$4'"; fail=1
	else echo "ok   $1 (nvidia X driver: $2) -> $3"; fi
}
# The same directory is reused on purpose: every run starts from the files
# the previous machine left behind, like a replaced card or a firmware switch.
t asus-gl553vd      yes 20-primary-gpu.conf 'BusID      "PCI:0:2:0"'
t nvidia-rtx3060    yes 20-nvidia.conf 'Driver     "nvidia"'
t amd-desktop       yes none
t legion-amd-nvidia yes 20-primary-gpu.conf 'BusID      "PCI:6:0:0"'
# The same laptop after switching the firmware to "discrete graphics": the
# NVIDIA card is now the one the firmware starts the screen on.
mkdir -p "$D.mux/fixtures/mux"; cp "$HERE"/fixtures/legion-amd-nvidia/* "$D.mux/fixtures/mux/"
sed -i.bak 's/^hw.pci.default_vgapci_unit=.*/hw.pci.default_vgapci_unit=0/' "$D.mux/fixtures/mux/sysctl.txt"
HW_FIXTURES="$D.mux/fixtures/mux/" FBS_LIB="$HERE/../lib" FBS_XORG_DIR="$D" FBS_NVIDIA_X=yes sh "$HERE/../files/bin/gpu-xorg-config"
if [ "$(cd "$D" && ls | tr '\n' ' ')" = "20-nvidia.conf " ]; then echo "ok   firmware switch to discrete -> 20-nvidia.conf"
else echo "FAIL firmware switch to discrete: $(ls "$D")"; fail=1; fi
t asus-gl553vd      no  none
t thinkpad-t480     no  none
# A file the user wrote is never removed.
echo '# mine' > "$D/20-nvidia.conf"
t amd-desktop       no  20-nvidia.conf '# mine'
# The GPU is found by its own vendor ID, not by the board maker's
# ("subvendor="): here an NVIDIA card made for an Intel board comes first.
_ids=$(. "$HERE/../lib/hw.sh"; _hw_pciconf() { printf '%s\n' \
	'vgapci0@pci0:1:0:0:	class=0x030200 rev=0xa1 hdr=0x00 vendor=0x10de device=0x1c8d subvendor=0x8086 subdevice=0x2068' \
	'vgapci1@pci0:0:2:0:	class=0x030000 rev=0x04 hdr=0x00 vendor=0x8086 device=0x591b subvendor=0x8086 subdevice=0x2068'; }
	echo "$(hw_gpu_busid intel) $(hw_gpu_busid nvidia)")
if [ "$_ids" = "PCI:0:2:0 PCI:1:0:0" ]; then echo "ok   GPU bus IDs by vendor, not subvendor"
else echo "FAIL GPU bus IDs by vendor: got '$_ids'"; fail=1; fi
exit $fail

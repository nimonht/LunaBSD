# lib/hw.sh - hardware detection for FreeBSD-setup. POSIX sh, sourced.
#
#   hw_detect      probe the machine and set the HW_* variables below
#   hw_report      print a human-readable compatibility report
#   hw_env         print the HW_* variables (for bug reports and scripts)
#
# Tests: set HW_FIXTURES=<dir> and every probe reads a file from that
# directory instead of the real system (see tests/):
#   pciconf.txt  output of `pciconf -lv`
#   usb.txt      output of `usbconfig dump_device_desc` + `dump_curr_config_desc`
#   sysctl.txt   name=value lines          kenv.txt   name="value" lines
#   sndstat.txt  contents of /dev/sndstat  dmesg.txt  /var/run/dmesg.boot
#   mount.txt    output of `mount -p`

: "${FBS_LIB:=$(dirname "$0")/lib}"
US=$(printf '\037')   # field separator for records (never in names, not IFS white space)
NL='
'

# ------------------------------------------------------------------ probes ---
_hw_file() { cat "$HW_FIXTURES/$1" 2>/dev/null || true; }
_hw_pciconf() { if [ -n "${HW_FIXTURES:-}" ]; then _hw_file pciconf.txt; else pciconf -lv 2>/dev/null; fi; }
_hw_usb() {
	if [ -n "${HW_FIXTURES:-}" ]; then _hw_file usb.txt; return; fi
	usbconfig dump_device_desc 2>/dev/null
	usbconfig dump_curr_config_desc 2>/dev/null
}
_hw_sysctl() {
	if [ -n "${HW_FIXTURES:-}" ]; then
		_hw_file sysctl.txt | awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }'
	else
		sysctl -n "$1" 2>/dev/null || true
	fi
}
_hw_kenv() {
	if [ -n "${HW_FIXTURES:-}" ]; then
		_hw_file kenv.txt | awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2); gsub(/^"|"$/, "", v); print v; exit }'
	else
		kenv -q "$1" 2>/dev/null || true
	fi
}
_hw_sndstat() { if [ -n "${HW_FIXTURES:-}" ]; then _hw_file sndstat.txt; else cat /dev/sndstat 2>/dev/null; fi; }
_hw_dmesg() { if [ -n "${HW_FIXTURES:-}" ]; then _hw_file dmesg.txt; else cat /var/run/dmesg.boot 2>/dev/null; fi; }
_hw_mount() { if [ -n "${HW_FIXTURES:-}" ]; then _hw_file mount.txt; else mount -p 2>/dev/null; fi; }

# hw_pci_records -> one line per PCI device:
#   unit US driver US class(6 hex) US vendor US device US vendor-name US device-name
# "unit" is the pciconf name (vgapci0, iwlwifi0, none3); "driver" is the unit
# without its number ("none" means no driver attached).
hw_pci_records() {
	_hw_pciconf | awk -v OFS="$US" -v q="'" '
	function flush() { if (unit != "") print unit, drv, cls, ven, dev, vname, dname; unit = "" }
	/^[A-Za-z_0-9]+@pci[0-9:]+/ {
		flush()
		split($1, a, "@"); unit = a[1]; drv = unit; sub(/[0-9]+$/, "", drv)
		cls = ""; ven = ""; dev = ""; vname = ""; dname = ""
		for (i = 2; i <= NF; i++) {
			n = split($i, kv, "=")
			if (kv[1] == "class") cls = substr(kv[2], 3)
			else if (kv[1] == "vendor") ven = substr(kv[2], 3)
			else if (kv[1] == "device") dev = substr(kv[2], 3)
			else if (kv[1] == "chip") { ven = substr(kv[2], 7, 4); dev = substr(kv[2], 3, 4) }
		}
		next
	}
	/^[ \t]+vendor[ \t]+=/ { v = $0; sub(/^[^=]*= */, "", v); gsub(q, "", v); vname = v; next }
	/^[ \t]+device[ \t]+=/ { v = $0; sub(/^[^=]*= */, "", v); gsub(q, "", v); dname = v; next }
	END { flush() }'
}

# hw_usb_records -> one line per USB device:
#   ugen US vendor US product US device-class US interface-classes US description
hw_usb_records() {
	_hw_usb | awk -v OFS="$US" '
	/^ugen[0-9]+\.[0-9]+:/ {
		u = $1; sub(/:$/, "", u)
		if (!(u in seen)) { seen[u] = 1; order[++n] = u }
		d = $0; sub(/^[^<]*</, "", d); sub(/>.*$/, "", d); desc[u] = d
		cur = u; next
	}
	/idVendor *=/        { ven[cur] = substr($3, 3) }
	/idProduct *=/       { prod[cur] = substr($3, 3) }
	/bDeviceClass *=/    { dcls[cur] = substr($3, 5, 2) }
	/bInterfaceClass *=/ { c = substr($3, 5, 2); if (index(" " icls[cur] " ", " " c " ") == 0) icls[cur] = icls[cur] (icls[cur] == "" ? "" : " ") c }
	END { for (i = 1; i <= n; i++) { u = order[i]; print u, ven[u], prod[u], dcls[u], icls[u], desc[u] } }'
}

# --------------------------------------------------------- classification ---

# hw_nvidia_branch device-id -> "current", "580", "470", "390", "340", "304",
# or an older branch number (unsupported on FreeBSD)
hw_nvidia_branch() {
	_b=$(awk -v id="$1" '$1 !~ /^#/ { for (i = 2; i <= NF; i++) if ($i == id) { print $1; exit } }' \
		"$FBS_LIB/nvidia-branches.txt" 2>/dev/null)
	echo "${_b:-current}"
}

# hw_amd_kmod device-id -> amdgpu or radeonkms (FreeBSD: amdgpu for GCN 1.2
# "Volcanic Islands" and newer, radeonkms for older cards incl. GCN 1.0/1.1)
hw_amd_kmod() {
	case "$1" in
	13fe|143f) echo amdgpu ;;
	13??|66[0-6]?|67[0-9a-b]?|68[0-5]?|68[8-9a-f]?|9[0-7]??|98[0-6]?|99??|9a??|9b??|9c??|9d??|9e??|9f??|[4-5]???|7[0-2]??)
		echo radeonkms ;;
	*)	echo amdgpu ;;
	esac
}

# hw_amd_gpu_note device-id -> empty, or a warning for GPUs newer than
# FreeBSD's amdgpu (based on Linux 6.12)
hw_amd_gpu_note() {
	case "$1" in
	75??) echo "RDNA 4 (RX 9000) is newer than FreeBSD's amdgpu driver; it may not work yet" ;;
	esac
}

# hw_intel_gpu_note device-id -> empty when i915kms supports it well,
# otherwise a short warning
hw_intel_gpu_note() {
	case "$1" in
	64??|e2??|b0??) echo "needs the newer Intel 'xe' driver, which FreeBSD does not have yet" ;;
	56??) echo "Intel Arc discrete GPU - support in FreeBSD's i915 is experimental" ;;
	esac
}

# hw_gpu_busid kind -> the Xorg BusID ("PCI:0:2:0") of the first GPU of that
# kind (intel, amd, nvidia), or nothing. pciconf prints "vgapci0@pci0:0:2:0:"
# as domain:bus:slot:function in decimal, which is what Xorg expects.
# (" vendor=", not "subvendor=": the board maker's ID can be a GPU maker's,
# e.g. an NVIDIA card in an Intel-made machine.)
hw_gpu_busid() {
	case "$1" in intel) _v=8086 ;; amd) _v=1002 ;; nvidia) _v=10de ;; *) return 0 ;; esac
	_hw_pciconf | awk -v ven="0x$_v" '
	/^[A-Za-z_0-9]+@pci[0-9:]+/ && /class=0x03/ && $0 ~ ("[ \t]vendor=" ven) {
		a = $1; sub(/^[^@]*@pci/, "", a); sub(/:$/, "", a)
		n = split(a, f, ":"); if (n != 4) next
		if (f[1] == 0) printf "PCI:%d:%d:%d\n", f[2], f[3], f[4]
		else printf "PCI:%d@%d:%d:%d\n", f[2], f[1], f[3], f[4]
		exit
	}'
}

# hw_vm -> none | virtualbox | vmware | qemu | hyperv | bhyve | xen | parallels | other
hw_vm() {
	_g=$(_hw_sysctl kern.vm_guest)
	_p="$(_hw_kenv smbios.system.maker) $(_hw_kenv smbios.system.product)"
	case "$_p" in
	*VirtualBox*|*innotek*) echo virtualbox; return ;;
	*VMware*)               echo vmware; return ;;
	*QEMU*|*"Standard PC"*|*KVM*) echo qemu; return ;;
	*"Microsoft Corporation Virtual Machine"*) echo hyperv; return ;;
	*BHYVE*)                echo bhyve; return ;;
	*Parallels*)            echo parallels; return ;;
	*Xen*|*HVM\ domU*)      echo xen; return ;;
	esac
	case "$_g" in
	""|none) echo none ;;
	kvm)     echo qemu ;;
	hv)      echo hyperv ;;
	vmware|bhyve|xen) echo "$_g" ;;
	*)       echo other ;;
	esac
}

# hw_acpi_kmod -> laptop vendor ACPI driver for hotkeys/backlight, or empty
hw_acpi_kmod() {
	_m=$(_hw_kenv smbios.system.maker)
	_f="$(_hw_kenv smbios.system.version) $(_hw_kenv smbios.system.family) $(_hw_kenv smbios.system.product)"
	case "$_m" in
	ASUS*|Asus*|asus*) echo acpi_asus_wmi ;;
	LENOVO*|Lenovo*) case "$_f" in *ThinkPad*) echo acpi_ibm ;; esac ;;
	HP|Hewlett*|HP\ *) echo acpi_hp ;;
	Sony*) echo acpi_sony ;;
	Panasonic*) echo acpi_panasonic ;;
	TOSHIBA*|Toshiba*|Dynabook*) echo acpi_toshiba ;;
	FUJITSU*|Fujitsu*) echo acpi_fujitsu ;;
	esac
}

_hw_is_laptop() {
	case "$(_hw_kenv smbios.chassis.type)" in
	Notebook|Laptop|Portable|"Sub Notebook"|"Hand Held"|Convertible|Detachable|Tablet) return 0 ;;
	esac
	_u=$(_hw_sysctl hw.acpi.battery.units)
	[ -n "$_u" ] && [ "$_u" -gt 0 ] 2>/dev/null
}

_hw_cpu_vendor() {
	_o=$(_hw_dmesg | sed -n 's/.*Origin="\([A-Za-z]*\)".*/\1/p' | head -1)
	case "$_o$(_hw_sysctl hw.model)" in
	*GenuineIntel*|*Intel*) echo intel ;;
	*AuthenticAMD*|*AMD*)   echo amd ;;
	*)                      echo other ;;
	esac
}

# ------------------------------------------------------------------ detect ---

# hw_detect_gpu -> only the graphics part of hw_detect (fast; used at boot)
hw_detect_gpu() {
	HW_VM=$(hw_vm)
	HW_PCI=$(hw_pci_records)
	_hw_detect_gpu
}

_hw_detect_gpu() {
	# ---- graphics -------------------------------------------------------
	# One line per GPU: kind US device-id US name US driver-plan US note
	HW_GPUS=""; HW_GPU_INTEL=""; HW_GPU_AMD=""; HW_GPU_NVIDIA=""; HW_GPU_VM=""
	HW_NVIDIA_BRANCH=""; HW_AMD_KMOD=""
	_boot_unit="vgapci$(_hw_sysctl hw.pci.default_vgapci_unit)"
	HW_GPU_PRIMARY=""
	while IFS="$US" read -r unit drv cls ven dev vname dname; do
		case "$cls" in 03*) ;; *) continue ;; esac
		name="${dname:-$vname}"; [ -n "$name" ] || name="PCI $ven:$dev"
		note=""
		case "$ven" in
		8086)	kind=intel; plan=i915kms; note=$(hw_intel_gpu_note "$dev")
			HW_GPU_INTEL="$name" ;;
		1002)	kind=amd; plan=$(hw_amd_kmod "$dev"); HW_AMD_KMOD=$plan
			note=$(hw_amd_gpu_note "$dev"); HW_GPU_AMD="$name" ;;
		10de)	kind=nvidia; br=$(hw_nvidia_branch "$dev"); HW_NVIDIA_BRANCH=$br
			HW_GPU_NVIDIA="$name"
			case "$br" in
			current) plan="nvidia-driver" ;;
			580)     plan="nvidia-driver-580"; note="legacy 580 driver, the last one for this GPU" ;;
			470|390|340|304) plan="nvidia-driver-$br"; note="legacy $br driver: X11 only, no Wayland" ;;
			*)       plan=""; note="needs NVIDIA driver $br, which FreeBSD no longer ships" ;;
			esac ;;
		15ad|80ee|1234|1af4|1b36|1414|1013|1a03|102b)
			kind=vm; plan=""; HW_GPU_VM="$name"
			case "$ven" in 1a03|102b) note="server management graphics" ;; *) note="virtual GPU" ;; esac ;;
		*)	kind=other; plan="" ;;
		esac
		HW_GPUS="${HW_GPUS}${kind}${US}${dev}${US}${name}${US}${plan}${US}${note}${NL}"
		[ "$unit" = "$_boot_unit" ] && HW_GPU_PRIMARY=$kind
	done <<EOF
$HW_PCI
EOF
	if [ -z "$HW_GPU_PRIMARY" ]; then
		if [ -n "$HW_GPU_INTEL" ]; then HW_GPU_PRIMARY=intel
		elif [ -n "$HW_GPU_AMD" ]; then HW_GPU_PRIMARY=amd
		elif [ -n "$HW_GPU_NVIDIA" ]; then HW_GPU_PRIMARY=nvidia
		elif [ -n "$HW_GPU_VM" ]; then HW_GPU_PRIMARY=vm
		else HW_GPU_PRIMARY=none; fi
	fi
	HW_GPU_HYBRID=no
	_n=$(printf '%s' "$HW_GPUS" | grep -cE "^(intel|amd|nvidia)$US" || true)
	[ "$_n" -ge 2 ] && HW_GPU_HYBRID=yes

	# Can a Wayland desktop (KDE Plasma 6, Hyprland) run? It needs a DRM/KMS
	# driver for the GPU that drives the screen.
	HW_DESKTOP=yes; HW_DESKTOP_WHY=""
	case "$HW_GPU_PRIMARY" in
	intel)	_note=$(printf '%s' "$HW_GPUS" | awk -F"$US" '$1 == "intel" { print $5; exit }')
		case "$_note" in needs*) HW_DESKTOP=no; HW_DESKTOP_WHY="Intel graphics: $_note" ;; esac ;;
	amd)	;;
	nvidia)	case "$HW_NVIDIA_BRANCH" in
		current|580) ;;
		*) HW_DESKTOP=no; HW_DESKTOP_WHY="this NVIDIA GPU only has an X11 driver on FreeBSD; KDE Plasma 6 and Hyprland need Wayland" ;;
		esac ;;
	vm)	HW_DESKTOP=no; HW_DESKTOP_WHY="virtual machines ($HW_VM) have no 3D/KMS graphics driver on FreeBSD; KDE Plasma 6 and Hyprland need one. Install on real hardware, or use PCI passthrough of a real GPU" ;;
	*)	HW_DESKTOP=no; HW_DESKTOP_WHY="no supported graphics card found" ;;
	esac
}

hw_detect() {
	HW_ARCH=$(uname -m 2>/dev/null)
	[ -n "${HW_FIXTURES:-}" ] && HW_ARCH=$(_hw_sysctl hw.machine)
	HW_OSREL=$(_hw_sysctl kern.osrelease)
	HW_BOOT=$(_hw_sysctl machdep.bootmethod)
	HW_VENDOR=$(_hw_kenv smbios.system.maker)
	HW_MODEL=$(_hw_kenv smbios.system.product)
	HW_VM=$(hw_vm)
	HW_CPU=$(_hw_sysctl hw.model)
	HW_CPU_VENDOR=$(_hw_cpu_vendor)
	HW_NCPU=$(_hw_sysctl hw.ncpu)
	_mem=$(_hw_sysctl hw.physmem)
	HW_RAM_MB=$(( ${_mem:-0} / 1048576 ))
	HW_LAPTOP=no; [ "$HW_VM" = none ] && _hw_is_laptop && HW_LAPTOP=yes
	HW_ACPI_KMOD=""; [ "$HW_VM" = none ] && HW_ACPI_KMOD=$(hw_acpi_kmod)
	HW_ROOTFS=$(_hw_mount | awk '$2 == "/" { print $3; exit }')
	HW_SLEEP=$(_hw_sysctl hw.acpi.supported_sleep_state)
	HW_PCI=$(hw_pci_records)
	HW_USB=$(hw_usb_records)

	_hw_detect_gpu

	# ---- networking -----------------------------------------------------
	# One line per device: unit US vendor US device US name US status
	HW_WIFI=""; HW_ETH=""
	while IFS="$US" read -r unit drv cls ven dev vname dname; do
		name="${vname:+$vname }${dname}"
		case "$cls:$ven" in
		0280*|0000??:14c3|ff00??:168c|ff00??:17cb)
			if [ "$drv" != none ]; then st=ok
			elif [ "$ven" = 14e4 ]; then st=unsupported
			else st=nodriver; fi
			HW_WIFI="${HW_WIFI}${unit}${US}${ven}${US}${dev}${US}${name}${US}${st}${NL}" ;;
		0200*)
			[ "$drv" != none ] && st=ok || st=nodriver
			HW_ETH="${HW_ETH}${unit}${US}${ven}${US}${dev}${US}${name}${US}${st}${NL}" ;;
		esac
	done <<EOF
$HW_PCI
EOF
	HW_WLAN_DEVICES=$(_hw_sysctl net.wlan.devices)

	# ---- audio, storage -------------------------------------------------
	HW_AUDIO_DEVS=$(printf '%s\n' "$HW_PCI" | awk -F"$US" '$3 ~ /^040[13]/ { print ($7 != "" ? $7 : $6) }')
	HW_PCM=$(_hw_sndstat | grep -E '^pcm[0-9]+:' || true)
	HW_RAID=$(printf '%s\n' "$HW_PCI" | awk -F"$US" '$3 ~ /^0104/ && $4 == "8086" { print $7; exit }')

	# ---- USB --------------------------------------------------------------
	HW_BT=""; HW_WEBCAM=""; HW_FPRINT=""
	while IFS="$US" read -r ugen ven prod dcls icls desc; do
		[ -n "$ugen" ] || continue
		case " $dcls $icls " in *" e0 "*) HW_BT="${HW_BT:+$HW_BT, }${desc:-$ven:$prod}" ;; esac
		case " $icls " in *" 0e "*) HW_WEBCAM="${HW_WEBCAM:+$HW_WEBCAM, }${desc:-$ven:$prod}" ;; esac
		case "$ven" in 06cb|27c6|138a|1c7a|10a5|2541|298d)
			case " $dcls $icls " in *" ff "*|*" 00 "*) HW_FPRINT="${HW_FPRINT:+$HW_FPRINT, }${desc:-$ven:$prod}" ;; esac ;;
		esac
	done <<EOF
$HW_USB
EOF
	return 0
}

# ------------------------------------------------------------------ report ---

_hw_line() { # status text
	case "$1" in
	OK)   printf '  [ OK ]  %s\n' "$2" ;;
	WARN) printf '  [WARN]  %s\n' "$2" ;;
	NO)   printf '  [ NO ]  %s\n' "$2" ;;
	*)    printf '  [INFO]  %s\n' "$2" ;;
	esac
}

hw_report() {
	_title="${HW_VENDOR:-Unknown maker} ${HW_MODEL:-}"
	printf 'Hardware check for %s\n\n' "$_title"

	case "$HW_ARCH" in
	amd64) _hw_line OK "Architecture: amd64" ;;
	aarch64|arm64) _hw_line WARN "Architecture: $HW_ARCH - desktop works on some boards; NVIDIA and Steam are amd64 only" ;;
	*) _hw_line NO "Architecture: $HW_ARCH - FreeBSD-setup supports amd64" ;;
	esac
	case "$HW_OSREL" in
	1[5-9].*) _hw_line OK "FreeBSD $HW_OSREL" ;;
	*) _hw_line NO "FreeBSD ${HW_OSREL:-unknown} - FreeBSD-setup needs FreeBSD 15 or newer" ;;
	esac
	[ "$HW_VM" != none ] && _hw_line INFO "Virtual machine: $HW_VM"
	_hw_line OK "CPU: ${HW_CPU:-unknown} (${HW_NCPU:-?} threads)"
	_gb=$(( (HW_RAM_MB + 512) / 1024 ))
	if [ "$HW_RAM_MB" -ge 7000 ]; then _hw_line OK "Memory: ${_gb} GB"
	elif [ "$HW_RAM_MB" -ge 3500 ]; then _hw_line WARN "Memory: ${_gb} GB - enough, but 8 GB or more makes a desktop much smoother"
	else _hw_line NO "Memory: ${_gb} GB - a graphical desktop needs at least 4 GB"; fi
	case "$HW_BOOT" in
	UEFI) _hw_line OK "Firmware: UEFI (installing next to Windows/Linux is possible)" ;;
	BIOS) _hw_line WARN "Firmware: legacy BIOS - only whole-disk installs; dual boot needs UEFI" ;;
	esac
	[ -n "$HW_RAID" ] && _hw_line WARN "Storage controller in Intel RST/RAID mode ($HW_RAID): switch it to AHCI in the firmware setup or disks may be invisible"

	# Graphics
	if [ -z "$HW_GPUS" ]; then
		_hw_line NO "Graphics: no graphics card found"
	else
		printf '%s' "$HW_GPUS" | while IFS="$US" read -r kind dev name plan note; do
			[ -n "$kind" ] || continue
			_role=""; [ "$kind" = "$HW_GPU_PRIMARY" ] && [ "$HW_GPU_HYBRID" = yes ] && _role=" - drives the screen"
			[ "$kind" != "$HW_GPU_PRIMARY" ] && [ "$HW_GPU_HYBRID" = yes ] && _role=" - extra GPU for games, run programs on it with 'gpu-run'"
			case "$kind:$note" in
			intel:|amd:) _hw_line OK "Graphics: $name ($plan)$_role" ;;
			nvidia:*legacy\ 580*) _hw_line OK "Graphics: $name ($note)$_role" ;;
			nvidia:) _hw_line OK "Graphics: $name (NVIDIA driver)$_role" ;;
			vm:*) _hw_line WARN "Graphics: $name ($note)" ;;
			*:) _hw_line WARN "Graphics: $name (no FreeBSD driver known)" ;;
			*) _hw_line WARN "Graphics: $name - $note" ;;
			esac
		done
	fi
	if [ "$HW_DESKTOP" = yes ]; then
		_hw_line OK "Desktop: KDE Plasma and Hyprland can run on this machine"
	else
		_hw_line NO "Desktop: KDE Plasma / Hyprland cannot run - $HW_DESKTOP_WHY"
	fi

	# Network
	if [ -z "$HW_WIFI" ] && [ -z "$HW_ETH" ] && [ -z "$HW_WLAN_DEVICES" ]; then
		_hw_line NO "Network: no network adapter found - use a USB Ethernet adapter or phone USB tethering"
	fi
	printf '%s' "$HW_ETH" | while IFS="$US" read -r unit ven dev name st; do
		[ -n "$unit" ] || continue
		if [ "$st" = ok ]; then _hw_line OK "Ethernet: $name ($unit)"
		elif [ "$ven" = 10ec ]; then _hw_line WARN "Ethernet: $name - no driver yet; the realtek-re-kmod package usually fixes it"
		else _hw_line WARN "Ethernet: $name - no driver attached"; fi
	done
	printf '%s' "$HW_WIFI" | while IFS="$US" read -r unit ven dev name st; do
		[ -n "$unit" ] || continue
		case "$st" in
		ok) _hw_line OK "Wi-Fi: $name ($unit)" ;;
		unsupported) _hw_line NO "Wi-Fi: $name - Broadcom Wi-Fi is not supported; use a USB Wi-Fi adapter, Ethernet, or wifibox" ;;
		*) case "$ven" in
		   8086|10ec|14c3|168c|17cb) _hw_line WARN "Wi-Fi: $name - driver needs a firmware package; it is installed automatically (fwget)" ;;
		   *) _hw_line NO "Wi-Fi: $name - no FreeBSD driver; use Ethernet, a USB adapter, or wifibox" ;;
		   esac ;;
		esac
	done
	if [ -z "$HW_WIFI" ] && [ -n "$HW_WLAN_DEVICES" ]; then _hw_line OK "Wi-Fi: $HW_WLAN_DEVICES"; fi

	# Audio
	if [ -n "$HW_PCM" ]; then
		_hw_line OK "Audio: $(printf '%s\n' "$HW_PCM" | head -1 | sed 's/^pcm[0-9]*: <\([^>]*\)>.*/\1/')"
	elif [ -n "$HW_AUDIO_DEVS" ]; then
		_hw_line WARN "Audio: $(printf '%s\n' "$HW_AUDIO_DEVS" | head -1) has no driver (Intel 'Smart Sound'/SOF audio is not supported) - HDMI and USB audio still work"
	elif [ "$HW_VM" = none ]; then
		_hw_line WARN "Audio: no sound device found"
	fi

	# Laptop bits and USB devices
	if [ "$HW_LAPTOP" = yes ]; then
		_hw_line OK "Laptop: battery and power management${HW_ACPI_KMOD:+, hotkeys ($HW_ACPI_KMOD)}"
		case " $HW_SLEEP " in
		*" S3 "*) _hw_line INFO "Sleep: suspend to RAM (S3) is available - test it once before relying on it" ;;
		*) _hw_line WARN "Sleep: this laptop has no S3 suspend (modern standby only); closing the lid will not suspend" ;;
		esac
	fi
	[ -n "$HW_WEBCAM" ] && _hw_line OK "Webcam: $HW_WEBCAM (webcamd)"
	[ -n "$HW_BT" ] && _hw_line WARN "Bluetooth: $HW_BT - keyboards and mice can be paired by hand; Bluetooth audio is not supported"
	[ -n "$HW_FPRINT" ] && _hw_line NO "Fingerprint reader: $HW_FPRINT - not supported"
	return 0
}

hw_env() {
	for _v in HW_ARCH HW_OSREL HW_BOOT HW_VENDOR HW_MODEL HW_VM HW_CPU HW_CPU_VENDOR HW_NCPU \
		HW_RAM_MB HW_LAPTOP HW_ACPI_KMOD HW_ROOTFS HW_SLEEP HW_GPU_PRIMARY HW_GPU_HYBRID \
		HW_NVIDIA_BRANCH HW_AMD_KMOD HW_DESKTOP HW_DESKTOP_WHY HW_WLAN_DEVICES; do
		eval "printf '%s=\"%s\"\n' $_v \"\$$_v\""
	done
	printf 'HW_GPUS:\n%s' "$HW_GPUS"
	printf 'HW_WIFI:\n%s' "$HW_WIFI"
	printf 'HW_ETH:\n%s' "$HW_ETH"
	printf 'HW_BT="%s"\nHW_WEBCAM="%s"\nHW_FPRINT="%s"\n' "$HW_BT" "$HW_WEBCAM" "$HW_FPRINT"
}

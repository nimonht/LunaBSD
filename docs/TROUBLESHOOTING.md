# Troubleshooting

Start here:

- **The log**: `/var/log/freebsd-setup.log` (setup) and
  `/var/log/freebsd-install.log` (installer). While the installer runs, or
  if it stopped part-way, its log is `/tmp/freebsd-install.log` in the USB
  stick's Live System; it is lost when that restarts.
- **The hardware report**: `freebsd-setup --report` says what was detected and
  what is known not to work.
- **A text console** is always available with `Ctrl+Alt+F3` (or F4, F5...).
  The `ly` login screen and the desktop come back with `Ctrl+Alt+F2` (on the
  live USB stick, KDE Plasma is on `Ctrl+Alt+F1`; the installer alone, which
  SDDM starts, on `Ctrl+Alt+F9`).
- **Undo**: `sysup` makes a boot environment named `pre-upgrade-...` before
  every update. In FreeBSD's boot menu press **8** (*Boot Environments*) and
  pick the newest one, or run `doas bectl activate <name>` and restart. That
  rolls the whole system back; your files in `/home` are not affected. If you
  ran `freebsd-setup` on a FreeBSD you installed yourself, `pre-setup-...` is
  the state before its first run. A system made with the FreeBSD-setup
  installer has no `pre-setup-...`; the state right after the install is the
  snapshot `zroot/ROOT/default@installed`
  (`doas bectl create -e default@installed after-install` makes a boot
  environment from it).
- **Re-run** a part: `doas freebsd-setup <stage>` (`freebsd-setup --list`).

## The LunaBSD USB stick

- **The stick does not appear in the boot menu, or "no bootable device".**
  Write the ISO again with Rufus in *DD image* mode or with balenaEtcher (ISO
  mode in Rufus copies files and loses the boot code).
- **A blue screen: "Verification failed: (0x1A) Security Violation".** Secure
  Boot is on and this computer does not know the stick's key yet: press OK,
  then any key, and enroll `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` from the stick
  ([SECUREBOOT.md](SECUREBOOT.md), *What you see*). Each new LunaBSD ISO has
  its own key and asks once.
- **"LunaBSD could not start: the USB stick or DVD was not found".** The
  kernel did not see the stick: try another USB port (a USB 2 port, or one
  directly on the computer instead of a hub).
- **"...needs at least ... MB" of memory.** The live system runs from memory
  and needs 4 GB. On a computer with less, use the text installer from
  FreeBSD's own install media instead (README, *Without the ISO*).
- **Black screen or a freeze where KDE Plasma should appear.** Restart, press
  **T** in the LunaBSD boot menu and choose *basic graphics*: the graphics
  driver is skipped and the installer starts on a simple framebuffer. The
  installed system decides its driver again; if its desktop does not start
  either, see [The desktop does not start](#the-desktop-does-not-start).
- **Only the installer appears, no desktop.** On purpose: its first page
  says why (a virtual machine, a graphics card FreeBSD has no driver for, an
  NVIDIA card older than the driver on the stick). The installation is the
  same. For the record: `cat /var/run/luna-live/reason`.
- **No graphics at all.** *Troubleshooting* > *text-mode installer* runs the
  text version of the same installer on the console.
- **The Wi-Fi list stays empty.** The card may have no FreeBSD driver (see
  the installer's *Your computer* page). Plug in a cable or use a phone's USB
  tethering, then choose *Check again*.

## Installer

**"doas: not found" after the first start**: the desktop setup stopped
before it could install doas (usually the internet connection dropped). Log
in, type `su -` and the administrator password (your own password, unless you
chose another one for root), check the connection, then type `freebsd-setup`.

**"No internet"**: run
`env BSDINSTALL_CONFIGCURRENT=yes bsdinstall netconfig` from the Live System
shell, or choose *Connect* in the installer. (Plain `bsdinstall netconfig`
fails there with *"Wireless cannot be configured without making changes to the
local system!"*: it only saves settings unless told to apply them now.) Wired networks need only DHCP. If the Wi-Fi
card is not listed, use Ethernet, a USB Ethernet adapter, or USB tethering from
a phone (`kldload if_urndis; dhclient ue0` for Android).

If the network works and the installer still says "No internet", check the
computer's clock in the firmware setup (a wrong date breaks secure downloads;
in the Live System `date YYYYMMDDhhmm`, for example `date 202611181200`, sets
it). Also make sure the install stick is a current FreeBSD release: old
releases are removed from the download server. Get the newest from
<https://www.freebsd.org/where/>.

**The disk I want is not in the list**: the USB stick and disks that are in use
are hidden. NVMe drives are called `nda0`, SATA drives `ada0`, USB drives `da0`.
If an NVMe drive is missing on a laptop, switch the storage mode from
*Intel RST/RAID* to *AHCI* in the firmware setup (Windows must be prepared for
that change first: search "switch RST to AHCI Windows").

**"Cannot install next to the existing systems"**: the message says why.
Usually there is not enough *unallocated* space (shrink a partition first), the
disk uses MBR instead of GPT, or the USB stick was started in legacy BIOS mode:
start it again and pick the entry marked "UEFI" in the boot menu.

**Download failed / checksum mismatch**: the network dropped. Run the installer
again. When an install stops half-way the installer cleans up after itself:
it unmounts everything, releases the disk, and for side-by-side installs
removes the partitions it had just created, so the free space is whole again.
If a partition was left behind anyway (power cut), delete it with
`gpart delete -i N <disk>` (`gpart show -l <disk>` lists them: `fbsd-zfs`,
`fbsd-swap`).

**Company network with a TLS-inspecting proxy**:
`export SSL_CA_CERT_FILE=/path/to/proxy-ca.pem` before starting the installer.

## Starting the computer

The commands below use the usual names `zroot` (the pool) and `fbsd-zfs` (the
partition). If another FreeBSD was on this computer they may be `zroot1` and
`fbsd-zfs1`: `zpool list` and `gpart show -l` show yours, and at the loader
prompt `lsdev` lists them.

**FreeBSD stopped starting** ("Secure Boot violation", "image verification
failed", or the firmware skips FreeBSD) after a firmware update, a reset of
the firmware settings, or after Secure Boot was switched on for Windows 11:
the system was installed with Secure Boot off, so its boot loader is not
signed. Start it with Secure Boot off once, run `doas secureboot enable`,
restart and confirm the key with the code it shows; then Secure Boot can stay
on ([SECUREBOOT.md](SECUREBOOT.md)). A blue screen asking to enroll a key at
every start means the key was never confirmed: the same command gives a new
code. If Windows uses BitLocker, switching Secure Boot off makes it ask for
its recovery key once; see [DUAL-BOOT.md](DUAL-BOOT.md#windows).

**Limine stops with "CHECKSUM MISMATCH FOR CONFIG FILE"** (installed with an
older FreeBSD-setup, next to CachyOS or another Linux whose Limine checks its
menu file against an enrolled checksum): the installer added FreeBSD to
`limine.conf`, which no longer matches. Nothing is lost, and no live USB is
needed:

1. Open the firmware boot menu at power-on (F12/F8/F11/Esc, depending on the
   maker) and pick **FreeBSD**.
2. Log in and put the original menu file back (the installer kept an exact
   copy; on FreeBSD the EFI partition is `/boot/efi`):
   `doas cp /boot/efi/limine.conf.before-freebsd /boot/efi/limine.conf`
   (if your `limine.conf` is in a sub-folder such as `EFI/limine/`, use that
   folder in both paths).
3. Restart: Limine starts again. To get FreeBSD into its menu, run this in
   CachyOS:
   `sudo limine-entry-tool --add-efi FreeBSD /boot/EFI/freebsd/loader.efi --comment FreeBSD --overwrite`.
   It prints `Updated: ...limine.conf` when it worked. If it prints nothing,
   your EFI partition is not at `/boot`: `findmnt -t vfat` shows where it is;
   use that folder instead of `/boot`.

**FreeBSD does not appear in Limine / systemd-boot**: check the EFI partition
from the other system: `EFI/freebsd/loader.efi` must exist, and the entry must
be in the configuration file the boot manager actually reads. Limine: if the
installer said your Limine menu was not changed because it is protected by a
checksum, add FreeBSD from Linux with the `limine-entry-tool` command above;
otherwise the installer added it to `limine.conf` and kept the previous file as
`limine.conf.before-freebsd`. If your EFI partition has more than one
`limine.conf`, make sure the entry is in the one Limine reads (the one next to
the Limine program comes first). You can always start FreeBSD from the firmware
boot menu (F12/F8/F11/Esc at power-on), entry "FreeBSD".

**Windows or Linux no longer starts by default**: the firmware boot order
changed (some Windows updates do this too). Pick the system once in the firmware
boot menu and fix the order there, or from FreeBSD:
`doas efibootmgr` lists the entries, `doas efibootmgr -o 0001,0000,...` sets the order.

**"Start ..." (key L) in FreeBSD's menu does nothing**: the loader looks for
the other system's boot file on disks 0-3. At the loader prompt (`3` in the
menu), `lsdev` lists the disks and `chain disk0p1:/EFI/Microsoft/Boot/bootmgfw.efi`
starts it by hand. The path is in `/boot/loader.conf` (`fbs_chain_path`).

**The loader stops at `OK` and cannot find the system**:

```
lszfs zroot/ROOT
set currdev=zfs:zroot/ROOT/default:
boot
```

If that works, `EFI/freebsd/loader.env` on the EFI partition is missing or
names another pool. Fix it from FreeBSD:
`echo 'rootdev=zfs:zroot/ROOT/default:' | doas tee /boot/efi/EFI/freebsd/loader.env`.

**Encrypted disk: the passphrase is not accepted**: the boot loader always
uses the US keyboard layout, whatever layout you chose (on a German keyboard,
`z` and `y` are swapped, for example). There is no way around a forgotten
passphrase: that is the point of encryption. If the passphrase is right but
the partition reports damaged metadata, restore it from the backup on the EFI
partition (from the USB stick's Live System):
`mount -t msdosfs /dev/<efi-partition> /mnt && geli restore /mnt/EFI/freebsd/fbsd-zfs.eli.backup /dev/gpt/fbsd-zfs`.
Change the passphrase from a running system with
`doas geli setkey -n 0 /dev/gpt/fbsd-zfs` (and keep it for the backup with
`doas geli backup /dev/gpt/fbsd-zfs /boot/efi/EFI/freebsd/fbsd-zfs.eli.backup`).

**Clock wrong in Windows after using FreeBSD (or the reverse)**: they disagree
about the hardware clock. Local time (what Windows uses):
`doas touch /etc/wall_cmos_clock`; UTC: `doas rm /etc/wall_cmos_clock`; then
restart.

## The desktop does not start

From a text console:

```sh
freebsd-setup --report          # is the graphics card supported?
kldstat | grep -E 'i915|amdgpu|radeon|nvidia'
ls -l /dev/dri                  # card0, renderD128... must exist
id                              # you must be in the "video" group
cat /var/log/Xorg.0.log | tail  # SDDM's login screen runs on X11
cat $XDG_RUNTIME_DIR/hypr-session.log   # Hyprland
```

- **No `/dev/dri`**: the graphics driver did not load. `doas dmesg | tail -40`
  shows why. Missing firmware: `doas fwget`. Then `doas freebsd-setup drivers`.
- **In a virtual machine**: expected. KDE Plasma 6 and Hyprland need a 3D
  graphics driver that FreeBSD does not have for VirtualBox, VMware or QEMU.
- **NVIDIA desktop, black screen**: check that `nvidia-driver*`,
  `nvidia-kmod*` and `nvidia-drm*` are the same version (`pkg info | grep nvidia`)
  and that `hw.nvidiadrm.modeset="1"` is in `/boot/loader.conf`.
- **Laptop with NVIDIA, black screen**: the desktop must run on the Intel/AMD
  GPU. The login screen is pinned to it in
  `/usr/local/etc/X11/xorg.conf.d/20-primary-gpu.conf`, which
  `gpu-xorg-config` rewrites at every start; run `doas gpu-xorg-config` and
  restart if it is missing.
  For Hyprland, force it in `~/.config/hypr-session.env`:
  `export AQ_DRM_DEVICES=/dev/dri/card0`. To leave the NVIDIA card without a
  driver, set `GPU_DRIVERS="intel"` (or `amd`) in
  `/usr/local/etc/freebsd-setup.conf`, run
  `doas sysrc kld_list-="nvidia-modeset nvidia-drm"`, and restart.
- **Black screen after switching the laptop between hybrid and discrete
  graphics in the firmware setup, or after replacing the graphics card**: the
  login screen's configuration follows the hardware by itself at every start,
  but a driver that was never installed cannot: log in on a text console
  (`Ctrl+Alt+F3`) and run `doas freebsd-setup drivers` (needs internet), then
  restart. A laptop installed in discrete mode has no driver for the
  integrated GPU until you do this.
- **Back at the login screen right after logging in**: the session crashed.
  KDE: `cat ~/.local/share/sddm/wayland-session.log` (SDDM) or, from ly,
  run `ck-launch-session dbus-run-session startplasma-wayland` on a text
  console to see its messages. KDE Plasma does not start from SDDM on
  FreeBSD (KWin gets no graphics card without logind): the login screen for
  KDE is ly. On the live USB stick: `/var/run/luna-live/plasma.log`.
  Hyprland: `cat $XDG_RUNTIME_DIR/hypr-session.log`.
- **KDE could not be installed**: the installer's last screen (and
  `/var/log/freebsd-setup.warnings`) says why. If it says *"could not be
  downloaded completely"*, the connection or a download server failed: check
  the internet connection and run `doas freebsd-setup kde` now. If it says
  *"cannot be installed from the '...' package branch right now"*, FreeBSD is
  rebuilding its packages: run `doas freebsd-setup kde` again in a few days.
  Until then the login screen offers no Plasma session; log in on a text
  console with `Ctrl+Alt+F3`.
- **The setup said it could not switch ttyv1 to ly**: your `/etc/ttys` was
  changed. Open it with `doas nano /etc/ttys`, change the `ttyv1` line to
  `ttyv1 "/usr/libexec/getty Ly" xterm on secure`, then restart. The ly login
  screen appears on `Ctrl+Alt+F2`.

## Hardware

**Wi-Fi**: `sysctl net.wlan.devices` lists working cards. Empty? The report
says whether the card needs firmware (`doas fwget` installs it) or is not
supported. Unsupported cards (Broadcom, some new chips) can work through
[wifibox](https://github.com/pgj/freebsd-wifibox) (`doas pkg install wifibox`),
which runs the Linux driver in a tiny virtual machine.

To connect: in KDE, use the NetworkMgr tray icon. Without it (Hyprland), add a
network to `/etc/wpa_supplicant.conf` and restart the network:

```sh
wpa_passphrase "NetworkName" "password" | doas tee -a /etc/wpa_supplicant.conf
doas service netif restart
```

If the card was never set up (no `wlans_` line in `/etc/rc.conf`), first run
`doas sysrc wlans_iwlwifi0=wlan0 ifconfig_wlan0="WPA SYNCDHCP"`, using the
card name from `sysctl net.wlan.devices`.

**Ethernet (Realtek) drops or is missing**: `doas pkg install realtek-re-kmod`
and follow its message.

**No sound**: `cat /dev/sndstat` lists devices; the one marked `default` plays.
Try another: `doas sysctl hw.snd.default_unit=1`, make it permanent in
`/etc/sysctl.conf`. Check PipeWire runs: `pgrep -l pipewire wireplumber`;
start it with `start-pipewire`. Laptops with Intel "Smart Sound"/SOF audio have
no FreeBSD driver: use HDMI, USB or a USB headset.

**Touchpad does not work, or no tap/scroll**: `doas dmesg | grep -iE 'hmt|hms|psm|iichid'`.
I2C touchpads need `ig4_load="YES"` and `iichid_load="YES"` in
`/boot/loader.conf` (the setup adds them on laptops) and a restart.

**Brightness keys**: try `brightnessctl set 50%`. If `backlight` reports no
device, add `acpi_video_load="YES"` to `/boot/loader.conf` and restart.

**Suspend does not resume**: common with NVIDIA drivers and on laptops without
S3. The setup makes the lid suspend only on laptops whose firmware offers S3
and that have no NVIDIA driver installed, and sets the screen to lock before every
suspend. To turn lid suspend off: `doas sysctl hw.acpi.lid_switch_state=NONE`,
and to keep it off,
`echo hw.acpi.lid_switch_state=NONE | doas tee -a /etc/sysctl.conf.local`
(running `freebsd-setup` again sets it back in `/etc/sysctl.conf`, but
`sysctl.conf.local` is applied after that file at every start).

**Bluetooth mouse/keyboard**: `doas bluetooth-config scan` and follow it.
Bluetooth audio is not supported.

**Printer not found**: network printers are found through mDNS, so the router
must allow it and `avahi_daemon` must run (`service avahi-daemon status`). Add
printers at <http://localhost:631> (log in with your user) or in KDE's printer
settings. USB printers: unplug and plug in again after the setup.

**Webcam**: `webcamd` must run (`service webcamd status`) and you must be in
the `webcamd` group (log out and in after the setup).

**Another account cannot start Hyprland, change brightness or use the
webcam**: accounts made with `adduser` after the setup get the right groups
automatically (unless you already had your own `/etc/adduser.conf`); for an
older one, run
`doas pw groupmod video -m NAME; doas pw groupmod webcamd -m NAME; doas pw groupmod games -m NAME`
and log out and in. (Mounting USB drives needs no group.)

## Hyprland + Caelestia

Fixes to FreeBSD-setup reach an installed system only through the install
one-liner: `doas freebsd-setup` runs the copy that was installed with it. Where
an entry below says "update FreeBSD-setup", run (as your user, in a terminal):
`fetch -qo- https://raw.githubusercontent.com/nimonht/LunaBSD/main/bootstrap.sh | sh -s -- hyprland caelestia finish`

- **The lock screen refuses your password** (installed before 2026-11-18):
  the lock screen checked passwords in a way that cannot work on FreeBSD.
  To get back in without restarting: press Ctrl+Alt+F3, log in, run
  `pkill -f quickshell` and then `hyprctl -i 0 dispatch exec hyprlock`. Go
  back to the desktop (Ctrl+Alt+F2 with the text login screen; Ctrl+Alt+F9,
  or F8/F10, with SDDM) and unlock with hyprlock. If `hyprctl` says it cannot
  find Hyprland, run `pkill -x Hyprland` on the console instead (unsaved work
  in that session is lost) and log in again. Then update FreeBSD-setup
  (above).
- **Sleep from the launcher, the session menu or the sleep gesture does
  nothing** (installed before 2026-11-18): update FreeBSD-setup (above). That
  fixes `~/.config/caelestia/shell.json` and `hypr-vars.lua` only if you never
  changed them (changing a setting in Caelestia's own settings also rewrites
  `shell.json`). Otherwise, in `shell.json` replace `"doas","zzz"` with
  `"doas","-n","/usr/sbin/zzz"`, and in `hypr-vars.lua` set
  `sleepGestureCmd = "doas -n /usr/sbin/zzz"`.
- **Updating Caelestia**: it is built from source here, so `pkg upgrade` and
  `sysup` do not update it. `doas freebsd-setup caelestia` (10 to 30 minutes)
  fetches the newest release of the shell and CLI, rebuilds them, and
  refreshes the settings files (dotfiles) from Caelestia's main branch. Your
  own settings in `~/.config/caelestia/` (`hypr-user.lua`, `hypr-vars.lua`,
  `shell.json`) and your colour scheme are kept; edits made directly inside
  the managed folders (`~/.config/hypr`, `fish`, `foot`, `fastfetch`, `btop`,
  `micro`, `Thunar`) are overwritten. When a package update changes Qt,
  Quickshell or a library Caelestia was built against, `sysup` says so: run
  the same command then, or the bar may not start. If the rebuild fails, the
  previous Caelestia stays installed.
- **The Caelestia build failed**: the reason is at the end of
  `/var/log/freebsd-setup.log`; build details are in
  `/var/tmp/caelestia-build/*.log`. A new Caelestia release may need a newer
  Quickshell than FreeBSD has yet, or may have changed its lock screen (the
  build then stops on purpose, so you are never locked out). Pin the last
  release that worked in `/usr/local/etc/freebsd-setup.conf`
  (`CAELESTIA_SHELL_REF="v2.5.0"`) and run `doas freebsd-setup caelestia`.
- **No bar after login**: run `caelestia shell` in a terminal (`Super+T`) to
  see the error.
- **Icons are boxes**: the Material Symbols font is missing:
  `ls /usr/local/share/fonts/material-symbols/`, then `doas freebsd-setup caelestia`.
- **CPU/memory show 0**: `doas service linux start` (Caelestia reads Linux-style
  `/proc` files from `/compat/linux/proc`).
- **Network/Bluetooth panels empty**: expected; they need Linux services.

## Steam and games

- Run `steam-setup` as your user from a terminal inside the desktop, once.
- **Steam does not start**: `doas service linux start`; check
  `mount | grep compat` lists linprocfs, linsysfs, devfs, fdescfs and tmpfs.
- **NVIDIA: "glXChooseVisual failed" or black window**: `linux-nvidia-libs*`
  must be the same version as `nvidia-driver*`.
- **A game does not start**: try another Proton version in its properties; search
  the game in the [linuxulator-steam-utils issues](https://github.com/shkhln/linuxulator-steam-utils/issues).
  Games with kernel anti-cheat do not run.

## Disk space and snapshots

**Deleting files does not free space**: automatic snapshots still hold the
deleted files (up to about two months for the monthly ones). The USEDSNAP
column shows how much they hold; `zfs destroy -nv` shows what removing a range
of snapshots would free, without removing anything:

```sh
zfs list -o space                      # where the space went (USEDSNAP: held by snapshots)
zfs list -t snapshot -o name,used -s used | tail
doas zfs destroy -nv zroot/home@first%last   # how much a range would free (dry run)
doas zfs destroy zroot/home@<snapshot> # remove one snapshot
bectl list                             # old boot environments hold space too
doas bectl destroy -o pre-upgrade-...
```

Two kinds of snapshots are never removed automatically: `@installed` (the
system as the installer left it) and one `@setup-<date>` for every run of
`freebsd-setup`. Both include `/home`. Once you no longer need them as a way
back, remove them: `zfs list -t snapshot | grep -E '@(installed|setup-)'` lists
them, and `doas zfs destroy -r zroot@installed` (or `zroot@setup-<date>`)
removes one.

## Reporting a problem

Open an issue at <https://github.com/nimonht/LunaBSD/issues> with: what
you did, what happened, `freebsd-setup --report`, and the end of
`/var/log/freebsd-setup.log`. For a desktop problem, also run
`sh /usr/local/share/freebsd-setup/tests/desktop-probe.sh` in a terminal inside
the desktop and attach the file it writes (addresses and serial numbers are
removed).

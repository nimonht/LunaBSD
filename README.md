<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="branding/lunabsd-lockup-reverse.svg">
    <img src="branding/lunabsd-lockup.svg" width="420" alt="LunaBSD">
  </picture>
</p>

# LunaBSD

**FreeBSD, ready for your desktop.** LunaBSD is a desktop distribution of
FreeBSD 15: a live USB stick that starts KDE Plasma so you can try it, a
graphical installer in the style of CachyOS's or Windows Setup, and a
desktop that is set up for your hardware when it arrives.

- **Try before installing.** The USB stick starts a complete KDE Plasma
  desktop with Firefox. A *Welcome* window offers *Try* or *Install*.
- **An installer for non-experts.** Language and keyboard, Wi-Fi, a check of
  what works on your computer, whole disk or next to Windows/Linux, optional
  encryption, your account, desktop and apps, one summary, one click. It
  never writes anything before that click.
- **Drivers picked automatically**, on the live stick and in the installed
  system: Intel, AMD and NVIDIA graphics (each NVIDIA card gets the driver
  branch NVIDIA lists for it), firmware for GPUs and Wi-Fi, CPU microcode,
  laptop touchpads, hotkeys and power saving. Graphics cards without a
  FreeBSD driver, and virtual machines, still get the installer, on a basic
  framebuffer, with an explanation.
- **KDE Plasma** (recommended), **Hyprland with the Caelestia shell** (a
  modern tiling desktop, for the adventurous), or both.
- **ZFS with automatic snapshots and boot environments**: your files have
  hourly and daily versions to go back to, and every update can be undone
  with one reboot.
- Sound (PipeWire), printers and scanners, USB drives and phones, input
  methods for Vietnamese, Chinese, Japanese and Korean, a firewall; optional
  everyday apps, gaming (Steam, Wine/Proton) and developer tools.
- **Always current.** The installer downloads the newest FreeBSD packages
  while it installs, so a new system is up to date from its first start.

LunaBSD is stock FreeBSD underneath: FreeBSD's kernel, base system, package
repositories and security updates, with no patches of its own. What it adds
is the live system, the installer, the setup that turns FreeBSD into a
desktop (`setup.sh` and `stages/`) and small compatibility services for
things the desktops expect from Linux.

| | |
|---|---|
| ![The installer on the live USB](docs/images/live-vm-installer.png) | ![Installing next to Windows](docs/images/installer-disk.png) |
| The live ISO, started in a virtual machine (QEMU): FreeBSD has no graphics driver there, so the installer runs alone | Installing next to Windows, with a size slider (demo data) |
| ![Desktop, apps and updates](docs/images/installer-desktop.png) | ![Installing](docs/images/installer-progress.png) |
| Desktop, apps and updates | While it installs |
| ![The boot menu](docs/images/boot-menu.png) | ![The wallpaper](branding/lunabsd-wallpaper-preview.jpg) |
| The boot menu | The wallpaper (a night version goes with dark mode) |

The look is LunaBSD's own: parchment, ink and a measuring grid, with menus
whose interaction is inspired by NieR:Automata's. Logo, colours, type and
where each piece is used: [docs/BRANDING.md](docs/BRANDING.md).

> **Status: 0.1 "Crescent", a preview.** What installs the system and sets up
> the desktop is FreeBSD-setup's tested code. The live ISO and the graphical
> installer are new: the ISO has been built and started in a virtual machine
> (UEFI, as a DVD and as a USB stick), where it loaded into memory and
> brought up the installer on the basic framebuffer; its hardware and disk
> check ran there and offered the empty disk, never the stick itself. Secure
> Boot ran there too, on the VM's UEFI firmware: with Microsoft's keys
> (shim, the key confirmed in MokManager) and in Setup Mode. Not tried yet: the live
> KDE session (it needs a real graphics card, which virtual machines do not
> have on FreeBSD), an installation started from the ISO, and anything on
> real hardware. Please report what happens on yours.

## Is LunaBSD right for you?

Read this before you install. FreeBSD is not a drop-in replacement for Linux,
Windows or macOS on a desktop or laptop: it supports less hardware and runs
less software, and no distribution can change that.

| | Linux (e.g. CachyOS) | Windows / macOS | LunaBSD |
|---|---|---|---|
| KDE Plasma / Hyprland desktop | Yes | No | Yes, needs a real GPU (below) |
| Intel / AMD graphics | Yes | Yes | Yes (not yet: Intel Lunar Lake/Battlemage; AMD Radeon RX 9000 may not work yet) |
| NVIDIA graphics | Yes | Yes | Yes for GTX 750 / 900 series and newer; older cards: no Wayland desktop |
| Laptop hybrid graphics | Yes, GPU powers off | Yes | Partly: games on the fast GPU with `gpu-run`; it cannot power off, so battery life suffers |
| Wi-Fi | Yes | Yes | Mostly: Intel and Realtek work, newer MediaTek/Qualcomm chips are recent additions, Broadcom does not work. Often slower than on Linux |
| Bluetooth | Yes | Yes | Barely: keyboards/mice paired by hand; no Bluetooth headphones |
| Sleep (suspend) | Yes | Yes | Sometimes: works on many Intel laptops (S3). Closing the lid does nothing on laptops with an NVIDIA driver and on "modern standby" laptops. No hibernate |
| Sound | Yes | Yes | Yes, except laptops with Intel "Smart Sound"/SOF audio |
| Webcam, printers, scanners, USB drives | Yes | Yes | Yes (most webcams; driverless network printers) |
| Fingerprint / face login | Mostly | Yes | No |
| Running in VirtualBox / VMware | Yes | Yes | Console only: these desktops need a 3D graphics driver that VMs don't have on FreeBSD |
| Browsers | Chrome, Firefox | All | Firefox, Chromium (no official Chrome) |
| Office | LibreOffice, OnlyOffice | MS Office | LibreOffice |
| Netflix/Spotify/Discord/Zoom/Teams apps | Yes (Flatpak) | Yes | Web versions only; no Flatpak/Snap/AppImage |
| Steam games | Yes (Proton) | Yes | Some: the Linux Steam client through a compatibility layer; many games run, anti-cheat games don't, things break more often |
| Snapshots and undo | Yes (Btrfs) | System Restore / Time Machine | Yes: ZFS snapshots and boot environments |
| Disk encryption | Yes | BitLocker / FileVault | Yes, optional: FreeBSD's whole partition (GELI, AES-256); the passphrase is typed at every start |
| Secure Boot | Yes (signed shim) | Yes | Yes, stays on: Fedora's Microsoft-signed shim and the computer's own key, confirmed once on a blue screen; or the computer's own keys from Setup Mode ([docs/SECUREBOOT.md](docs/SECUREBOOT.md)). Tested in a VM's firmware only. FreeBSD's loader does not check the kernel |

LunaBSD suits you if you like its design and ZFS, your hardware is in the
supported range, and you mostly use open-source software and web apps. It does
not suit you if you need specific commercial apps, competitive online games,
long battery life on a gaming laptop, or Bluetooth audio. Dual boot keeps your
other system for those.

## What you need

- A 64-bit PC (amd64) with 8 GB RAM (4 GB minimum: the live system runs from
  memory) and 40 GB of free disk space (30 GB minimum)
- A real graphics card for the desktop: Intel HD/UHD/Iris/Arc integrated
  graphics, an AMD Radeon, or an NVIDIA GeForce GTX 750 or newer
- UEFI firmware to install next to Windows/Linux (legacy BIOS: whole disk only)
- Secure Boot can stay on: the stick and the installed system each ask
  once, on a blue screen, to trust their key
  ([docs/SECUREBOOT.md](docs/SECUREBOOT.md); tested on a virtual machine's
  UEFI firmware, not yet on a real PC). Switching it off works too
- An internet connection during installation (Ethernet, Wi-Fi with a
  supported card, or a phone's USB tethering)
- A USB stick of 4 GB or more

Not sure? Start the USB stick: its installer shows a hardware report before
anything else, and nothing is written before the very last confirmation.

## Install

### 1. Back up

Back up everything you cannot lose. If you keep Windows, switch off Fast
Startup (Control Panel → Power Options → "Choose what the power buttons do")
and save the BitLocker recovery key (<https://aka.ms/myrecoverykey>):
Windows asks for it if Secure Boot gets switched off (LunaBSD does not need
that) and may ask when started from LunaBSD's own menu. See
[docs/DUAL-BOOT.md](docs/DUAL-BOOT.md#windows) for how to avoid the prompt.

### 2. Make room (only when keeping another system)

FreeBSD needs unallocated space on the disk; the installer creates its
partitions there and never touches existing ones.

- From Windows: *Disk Management* → right-click your largest partition →
  *Shrink Volume*. Leave the freed space "Unallocated".
- From Linux: boot a live USB and shrink a partition with GParted or KDE
  Partition Manager.

### 3. Write the USB stick

Download `lunabsd-0.1-amd64.iso` and its `.sha256` file from the
[Releases page](https://github.com/nimonht/LunaBSD/releases) (or build
it yourself: [docs/BUILDING.md](docs/BUILDING.md)), then write it to the
stick. This erases the stick.

- Windows: [Rufus](https://rufus.ie) (when it asks, choose *DD image* mode)
  or [balenaEtcher](https://etcher.balena.io)
- macOS / Linux: balenaEtcher, or
  `sudo dd if=lunabsd-0.1-amd64.iso of=/dev/<stick> bs=1M status=progress`

Check the download first if you can: `sha256sum -c lunabsd-0.1-amd64.iso.sha256`
(Windows: `certutil -hashfile lunabsd-0.1-amd64.iso SHA256` and compare).
To check that the ISO was built by this project's own build machine, and
not changed after: `gh attestation verify lunabsd-0.1-amd64.iso -R nimonht/LunaBSD`
(needs GitHub's [`gh`](https://cli.github.com) tool).

### 4. Start from the stick

Restart with the stick plugged in and open the boot menu (usually F12, F8,
F11 or Esc right after power-on; on Macs hold Option). Pick the USB stick.
With Secure Boot on, the first start from a stick shows a blue screen once
(*Verification failed*, then *Shim UEFI key management*): press OK, then any
key, choose **Enroll key from disk**, the stick (*EFISYS*),
**ENROLL_THIS_KEY_IN_MOKMANAGER.cer**, **Continue**, **Yes** and **Reboot**,
and start from the stick again ([docs/SECUREBOOT.md](docs/SECUREBOOT.md)).

LunaBSD's boot menu starts by itself after 5 seconds. It copies the system
into memory (a minute or two; afterwards the stick could be removed), then:

- **KDE Plasma starts**, with a *Welcome* window: *Try LunaBSD* to look
  around (the *Install LunaBSD* icon stays on the desktop), or *Install*.
- **Or only the installer appears, full screen**: on graphics cards FreeBSD
  has no driver for, older NVIDIA cards, and in virtual machines. The first
  page says why. Installing works the same.

If the screen stays black or freezes, start again and press **T**
(*Troubleshooting*) in the boot menu: *basic graphics* skips the graphics
driver, *text-mode installer* uses no graphics at all.

### 5. Install

The installer asks, one page at a time: language and keyboard (used right
away, so your passwords are typed as they will be at the login screen),
the internet connection (pick your Wi-Fi network there), shows what works
on your computer, then asks for the disk (*next to what is on it*, with a
size slider, or *erase*; optional encryption), time zone, your account,
desktop, apps and updates (FreeBSD's newest packages by default, or the
steadier quarterly ones), and shows a summary. Nothing is written before *Install
now*. The installation then takes 30 to 90 minutes, mostly downloading; the
live desktop stays usable meanwhile. At the end, remove the stick and
restart.

### 6. First start

- Whole disk: FreeBSD starts directly. If another disk in the computer has
  Windows or Linux and you kept that system as the one that starts first,
  pick *FreeBSD* in the firmware boot menu (F12/F8/Esc).
- Next to other systems: FreeBSD is added to the Limine or systemd-boot menu
  when it finds one (a Limine that protects its menu with a checksum, as
  CachyOS's does, is left alone: the installer shows the one command to run
  in Linux), rEFInd finds it by itself, and it normally appears as *FreeBSD*
  in the firmware boot menu (F12/F8/Esc). If the installer's last screen says
  it could not add a firmware boot entry, FreeBSD starts only from the Limine,
  systemd-boot or rEFInd menu, if you have one; otherwise add an entry for
  `\EFI\freebsd\loader.efi` in the firmware setup's boot options. If you chose
  FreeBSD's menu as the default, press L in that menu to start Windows or
  Limine; with disk encryption the passphrase is asked before that menu
  appears, so use the firmware boot menu to skip it. GRUB users: see
  [docs/DUAL-BOOT.md](docs/DUAL-BOOT.md).

At the login screen pick *Plasma (Wayland)* or *Hyprland (Caelestia)* and log
in (not the plain "Hyprland" entry a package update may add: it lacks the
settings FreeBSD needs). With Hyprland only, the login screen is a simple text
screen: choose the session with the arrow keys, then type your name and
password.

## Without the ISO: stock FreeBSD plus one command

LunaBSD's installer also runs from FreeBSD's own install media: download
`FreeBSD-15.1-RELEASE-amd64-memstick.img` from
[download.freebsd.org](https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/15.1/),
write it to a stick, start it and choose *Live System*, log in as `root` (no
password; run `kbdmap` first for a non-US keyboard), connect with
`env BSDINSTALL_CONFIGCURRENT=yes bsdinstall netconfig`, then run:

```sh
fetch -qo- https://raw.githubusercontent.com/nimonht/LunaBSD/main/bootstrap.sh | sh
```

This is the text-mode version of the same installer, with the same result.

### Already have FreeBSD 15?

Run the same one-liner on an installed FreeBSD. It starts the setup wizard
instead of the installer:

```sh
fetch -qo- https://raw.githubusercontent.com/nimonht/LunaBSD/main/bootstrap.sh | sh
```

It asks for the root password through `doas`, `sudo` or `su`. On a fresh
FreeBSD, `su` only works for members of the `wheel` group; if it answers
*Sorry*, log in as `root` on a text console and run the same command there.
To use git instead, as root: `pkg install git`, then
`git clone https://github.com/nimonht/LunaBSD && sh LunaBSD/setup.sh`.
The first time it runs, it creates a ZFS boot environment `pre-setup-<date>`:
choosing it in the boot menu brings the system (not your home folder) back to
how it was before. Later runs do not make a new one; run `sysup` or
`doas bectl create <name>` first if you want one.

## Everyday use

| Task | How |
|---|---|
| Update packages and the base system safely | `sysup` (creates a boot environment first) |
| Update Caelestia (Hyprland) | `doas freebsd-setup caelestia` (see [below](#the-desktops)) |
| Get the newest FreeBSD-setup fixes | Run the install one-liner again (above): it refreshes the copy in `/usr/local/share/freebsd-setup`, which `freebsd-setup` uses |
| Undo a bad update | Boot menu → 8 *Boot Environments* → pick the previous one; or `doas bectl activate <name>` and restart |
| Get an old version of a file | `snap files <file or folder>` shows where its read-only old copies are (for your home folder: `/home/.zfs/snapshot/<time>/<your name>/...`); `snap` lists the snapshots |
| Install software | `doas pkg install <name>`; search with `pkg search <word>` or browse [FreshPorts](https://www.freshports.org) |
| Run a game on the fast GPU (laptops) | `gpu-run <program>`; Steam does it by itself |
| Steam | Run `steam-setup` once from a terminal, then start Steam from the menu |
| Wi-Fi networks | KDE: the NetworkMgr icon in the panel. Hyprland has no Wi-Fi window yet: see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#hardware) |
| Add to your choices (another desktop, extras...) | `doas freebsd-setup`. It installs what you add but does not remove what you untick: remove programs with `doas pkg delete <name>`, turn the firewall off with `doas sysrc pf_enable=NO` |
| Hardware report | `freebsd-setup --report` |
| Sound output | `pavucontrol`, or `cat /dev/sndstat` and `doas sysctl hw.snd.default_unit=N` |
| Windows/Linux partitions | Dolphin shows them; NTFS, exFAT and ext4 can be opened |
| Firewall: open a port | Add a rule to `/etc/pf.local.conf` (yours, never replaced), then `doas service pf reload` |
| Terminal: turn the ready-made setup off for you | `terminal-style off` (or `terminal-style greeting-off` for just the system summary); `terminal-style on` undoes it |

Snapshots cover your home folder too, so a deleted file keeps using disk space
until its last snapshot expires (up to about two months). See
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#disk-space-and-snapshots).

### The terminal

The installer asks for a terminal style: fish (the default), zsh, bash or
plain. The first three give the terminal (Konsole, foot) colours, completion,
history search on the Up arrow (fish and zsh also suggest as you type), a
prompt that shows the git branch ([starship](https://starship.rs)), the
JetBrainsMono Nerd Font and a system summary (fastfetch) in every new shell,
similar to CachyOS. Short extra commands: `ll`, `la`, `lt` (listings), `z DIR`
(jump to a folder you used before), `update` (`sysup`), `cleanup`, `psmem`.
Standard commands such as `ls`, `cat` and `cd` are left as they are, so guides
and scripts keep working.

Your login shell stays `sh`: the style only applies inside the terminal app,
so a broken shell setup can never stop you from logging in. To change the
style for everyone, set `TERMINAL_STYLE` to `fish`, `zsh`, `bash` or `none`
(plain) in `/usr/local/etc/freebsd-setup.conf` and run
`doas freebsd-setup terminal`. Your own `~/.config/fish/config.fish`,
`~/.zshrc` or `~/.bashrc` always run after ours. With Caelestia, fish uses
Caelestia's own setup.

### The desktops

KDE Plasma is a complete, Windows-like desktop with its own settings app, file
manager (Dolphin), terminal (Konsole) and screenshot tool. Most of it works on
FreeBSD as on Linux. The Wi-Fi and Bluetooth settings do not (they need
Linux-only services; use the NetworkMgr tray icon for networks), and neither
does System Monitor's Applications page. Date & Time and the battery applet's
power-profile switch are served by small services this setup adds; they are
new and have been tested in a virtual machine, not yet on real hardware. If
Date & Time cannot change the time zone, use `doas tzsetup`.

Hyprland + Caelestia is a tiling Wayland desktop with an animated shell. It is
built from source on FreeBSD with small compatibility shims. Its Wi-Fi, VPN,
Bluetooth, GPU-usage and fingerprint panels rely on Linux services and do not
work. The power-profile switch comes from the same new service as in KDE, on
computers whose CPU allows it (elsewhere it is hidden); it has not yet been
tried on real hardware. The bar, launcher,
dashboard, notifications, media controls, lock screen, wallpapers and colour
schemes work. `Super` opens the launcher, `Super+T` a terminal, `Super+Q`
closes a window
([all keys](https://github.com/caelestia-dots/caelestia#default-keybinds)).
Hyprland uses FreeBSD's newest ("latest") package branch for the whole
computer, KDE included, which updates faster and breaks more often. Once a
computer is on "latest" it stays there, even if you remove Hyprland later.

Caelestia is not a FreeBSD package, so `pkg upgrade` and `sysup` do not update
it. The installer builds the newest Caelestia release of that day; to move to
a newer one, run `doas freebsd-setup caelestia` (10 to 30 minutes). `sysup`
tells you when a package update needs this rebuild. Your own settings in
`~/.config/caelestia/` are kept; see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#hyprland--caelestia) for what
is replaced.

## What exactly gets changed

**Installer, whole disk:** a new GPT table with an EFI partition, a BIOS boot
partition (so the disk boots in UEFI and legacy mode), swap, and a ZFS pool
`zroot` with the standard FreeBSD dataset layout.

**Encryption (optional, both modes):** the ZFS partition is encrypted with
GELI (AES-XTS, 256-bit key); FreeBSD's boot loader asks for the passphrase,
always with the US keyboard layout. Swap gets a new random key at every start.
A backup of the encryption metadata (useless without the passphrase) is kept
in `EFI/freebsd/fbsd-zfs.eli.backup` on the EFI partition.

**Installer, next to other systems:** two new partitions (ZFS and swap) in the
largest free space; `EFI/freebsd/` added to the existing EFI partition; one
entry appended to Limine's `limine.conf` (backup saved next to it; never when
Limine checks that file against an enrolled checksum) or one file added to
systemd-boot's `loader/entries/`; a firmware boot entry *FreeBSD* (added at
the end of the boot order unless you chose FreeBSD to start first). Nothing
else on the disk is modified. Do not install next to another FreeBSD on the
same disk: the new one takes over the shared `EFI/freebsd/` folder, and the
old one no longer starts from any menu.

**Setup:** packages; settings added to `/etc/rc.conf`, `/boot/loader.conf`
and `/etc/sysctl.conf`; `/etc/devfs.rules` and `/etc/pf.conf` replaced at
every run (your previous versions are saved once as `*.before-freebsd-setup`;
put your own firewall rules in `/etc/pf.local.conf`, which is never
replaced); the login screen; who may run admin commands
(`/usr/local/etc/doas.conf` when you have none,
`/usr/local/etc/sudoers.d/00-freebsd-setup`, and polkit rules so that you can
mount drives, shut down, set the time and switch power profiles without a
password); with SDDM (not the default), its PAM file
`/usr/local/etc/pam.d/sddm` while it is still the package's own (so the
wallet opens with your login password);
`/etc/fstab` (`/proc`, `/dev/fd`, and `/dev/shm` for Steam);
`/etc/nsswitch.conf` (network printers); `/etc/ttys` and `/etc/gettytab`
(the ly login screen); your groups (wheel, operator, video, webcamd, games, cups) and the
groups new accounts get (`/etc/adduser.conf`, when you have none); the
package branch; the terminal style (system-wide files in `/usr/local/etc` and
`/usr/local/share`, only where you have none of your own); KDE defaults in
`/usr/local/etc/xdg` (dark Breeze theme, file indexing off) and
`/etc/xdg/arkrc`; the LunaBSD look (boot menu name and logo via
`loader_brand`/`loader_logo`, wallpaper, login screen background,
`/etc/xdg/kcm-about-distrorc`, and an rc script that writes
`/var/run/os-release` as LunaBSD with `ID_LIKE=freebsd`; turn it off with
`doas sysrc lunabsd_osrelease_enable=NO`); Firefox privacy defaults in
`/etc/firefox/policies/policies.json` (no telemetry, studies or sponsored
content); automatic snapshots and a monthly scrub. In your home folder it adds
settings you don't have yet, with two exceptions: `~/.login_conf` is
rewritten with the chosen language at every run, and Caelestia moves your
existing `~/.config/hypr`, `fish`, `foot`, `fastfetch`, `btop`, `micro` and
`Thunar` folders aside (renamed `*.before-caelestia.*`) and keeps those
folders up to date with Caelestia's own files. The full log is
`/var/log/freebsd-setup.log`; your answers are saved in
`/usr/local/etc/freebsd-setup.conf`.

**Removing FreeBSD (dual boot):** delete the `fbsd-zfs` and `fbsd-swap`
partitions (the names end in a number, e.g. `fbsd-zfs1`, when another disk in
the computer already used them) from the other system, remove `EFI/freebsd`
from the EFI partition, the FreeBSD block from `limine.conf` (or
`loader/entries/A-freebsd.conf`), and the firmware entry (`efibootmgr` on
Linux). Details: [docs/DUAL-BOOT.md](docs/DUAL-BOOT.md#removing-freebsd).

## Advanced

To build the ISO yourself (on FreeBSD, or on Linux through a FreeBSD virtual
machine), change what is on it, or test it: [docs/BUILDING.md](docs/BUILDING.md).
What LunaBSD takes from Ubuntu, Mint, Fedora and CachyOS, and what is
planned: [docs/DISTRO.md](docs/DISTRO.md).

```sh
./setup.sh --report              # hardware compatibility report
./setup.sh --list                # the setup stages
doas ./setup.sh drivers desktop  # run only some stages
doas ./setup.sh --yes --config my.conf   # unattended, answers from a file
sh install.sh --dry-run          # in the USB stick's Live System, as root: the installer's questions and plan, no changes
```

The desktop setup's answers and their defaults are documented in
[`lib/defaults.conf`](lib/defaults.conf); the installer's answers (disk,
account, encryption, time zone...) are shown in the unattended examples in
[`tests/`](tests) (`install-*.conf`). Behind a company proxy that intercepts
TLS, export `SSL_CA_CERT_FILE=/path/to/ca.pem` before running the installer;
it is copied into the new system.

Problems? See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). Which hardware
works, and why: [docs/HARDWARE.md](docs/HARDWARE.md).

## License

BSD 2-Clause, see [LICENSE](LICENSE). Caelestia is © its authors under its own
license and is downloaded from its upstream repositories at install time.

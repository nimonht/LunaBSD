# Building LunaBSD

How the LunaBSD ISO is made, how the live system starts, and how to change
and test it. Users do not need any of this: they download the ISO.

## Build the ISO

### On FreeBSD 15

```sh
git clone https://github.com/nimonht/LunaBSD && cd LunaBSD
doas sh iso/build.sh
```

Needs root, the `zfs` kernel module, about 40 GB free, 8 GB of memory and an
internet connection. The result is in `iso/out/`: the ISO, its `.sha256`, and
the list of packages on it. A run takes 20 to 60 minutes on real hardware,
mostly downloading. Settings (all optional) are listed at the top of
[`iso/build.sh`](../iso/build.sh): `FREEBSD_RELEASE`, `PKG_BRANCH`,
`PKG_SITE`, `PATCH_BASE=no`, `ZSTD_LEVEL`, `EXTRA_CA` for a proxy that
intercepts TLS, and `STEPS` to repeat single steps while developing:

```sh
doas env STEPS="configure trim image ramdisk iso" sh iso/build.sh   # after editing iso/live/
```

The ISO starts with UEFI Secure Boot on ([SECUREBOOT.md](SECUREBOOT.md);
`SECURE_BOOT=no` builds one with FreeBSD's loader alone): the fetch step downloads Fedora's
Microsoft-signed shim (checked by SHA-256), the iso step puts it on the EFI
image as `BOOTX64.EFI`, with FreeBSD's loader (with an `.sbat` section)
signed as `grubx64.efi`, MokManager and `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`.
There is no key to create or guard: each build makes a key for itself,
signs the loader and deletes the private half (also when the build fails),
so nothing else can ever be signed with it. Every new ISO therefore asks to
enroll its certificate once. To keep one key across releases instead (no
new enrollment per ISO, but a secret to keep: every computer that enrolled
it starts whatever it signs), pass `SB_KEY` and `SB_CERT` (PEM files;
`build-in-vm.sh` copies them into the build VM and removes them afterwards).

### On Linux (or in CI)

```sh
sh iso/build-in-vm.sh
```

This downloads FreeBSD's official cloud image of the release in
`distro.conf`, starts it in QEMU (with KVM when `/dev/kvm` is usable),
copies the repository in, runs `iso/build.sh` there and copies `iso/out/`
back. It needs `qemu-system-x86_64`, `qemu-img`, `xz`, `curl`, `ssh` and
`genisoimage` (or `xorriso`). Without KVM it works but takes hours. The VM
stays in `iso/vm/` and is reused by the next run.

GitHub Actions does the same: the *ISO* workflow
([`.github/workflows/iso.yml`](../.github/workflows/iso.yml)) runs on demand
(*Actions > ISO > Run workflow*), boots the result once in QEMU, and keeps
the ISO as a download. Pushing a tag such as `v0.1` also publishes it as a
release. GitHub limits a release file to 2 GiB (2048 MiB). The ISO is
currently over that: 2107 MiB with NVIDIA's driver (the workflow's run of
November 2026). A local build came out at 1850 MiB only because its NVIDIA
download had failed (`build.sh: WARNING: no consistent NVIDIA driver`), so
read the build log, not just the size. `python3 iso/size.py` estimates the
ISO from the package catalogue; check it when adding packages.

An ISO that passed the workflow's boot tests also gets a build attestation
([`actions/attest`](https://github.com/actions/attest)): a Sigstore
signature, made without any key to keep, saying which workflow run and
commit produced exactly these bytes. Check one with GitHub's CLI:

```sh
gh attestation verify lunabsd-0.1-amd64.iso -R nimonht/LunaBSD
```

The `.sha256` file next to the ISO only shows that a download is not broken
(whoever can replace the ISO can replace it too); the attestation shows who
built it. The Secure Boot signature on the loader is a third, separate thing
([SECUREBOOT.md](SECUREBOOT.md)). The attestation step has not run yet: it
is set up, and the first run of the workflow on `main` will show whether it
works.

### New FreeBSD release

Change `FREEBSD_RELEASE` in [`distro.conf`](../distro.conf) (e.g.
`15.2-RELEASE` in December 2026) and build. Kernel modules (graphics, Wi-Fi)
come from the `FreeBSD-ports-kmods` repository for that minor release; right
after a release it can take a few days until all of them are built.

## What is on the ISO

| Path on the ISO | What it is |
|---|---|
| `boot/` | FreeBSD's boot loader (BIOS and UEFI), the kernel and `zfs.ko`, the LunaBSD boot menu ([`iso/boot/`](../iso/boot), [`branding/loader/`](../branding/loader)) |
| `luna/ramdisk.ufs.gz` | a small ramdisk: FreeBSD's `/rescue` tools and [`iso/ramdisk/init.sh`](../iso/ramdisk/init.sh) |
| `luna/system.zfs` | the whole live system as a compressed ZFS stream (`zfs send`) |

The ISO is a hybrid image: written to a USB stick it is a GPT disk with a
BIOS boot partition and an EFI partition (as FreeBSD's own ISOs); burnt or
attached as a CD it boots through El Torito, BIOS and UEFI.

### How the live system starts

1. FreeBSD's loader shows the LunaBSD menu and loads the kernel, `zfs.ko`
   and the ramdisk as the root file system (`iso/boot/loader.conf`).
2. `init(8)` runs the ramdisk's `init.sh` (`init_script`): it finds the
   media by its label (`/dev/iso9660/LUNABSD`), checks that there is enough
   memory, creates a swap-backed memory disk with a ZFS pool `lunalive`,
   and receives `luna/system.zfs` into it.
3. The ramdisk's `/etc/rc` exports the pool and re-roots into it
   (`reboot -r` with `vfs.root.mountfrom=zfs:lunalive`). `init` starts
   again, on the live system.

The system is copied into memory because `reboot -r` unmounts everything
but its own copy of `init`, the media included: a system read from the
stick would vanish at that moment. GhostBSD's live media work the same way.
The cost is memory: about the size of `system.zfs`, which is why the live
system needs 4 GB. The gain: the live system is writable (settings,
downloads, even `pkg install`), and the stick can be removed.

4. On the live system, [`iso/live/luna_live`](../iso/live/luna_live) runs
   early: it reads the hardware with `lib/hw.sh` (the installer's own
   detection), loads the graphics driver (`i915kms`, `amdgpu`/`radeonkms`,
   or NVIDIA's `nvidia-drm` for the current driver branch), and waits for a
   display. With a display, the live user is logged in on the first
   console and `~/.profile` starts KDE Plasma (Wayland) there
   ([`iso/live/luna-plasma`](../iso/live/luna-plasma)). Not through SDDM:
   KWin gets the graphics card from ConsoleKit2 (FreeBSD has no logind),
   which gives devices only to the session of the console on screen, and a
   session SDDM starts has none, so Plasma stopped at once on a real laptop.
   If Plasma does not come up within a minute, the installer session starts
   instead (`luna_live fallback`; Plasma's messages in
   `/var/run/luna-live/plasma.log`). Without a display, SDDM starts the
   *LunaBSD Installer* session:
   X11 on the firmware framebuffer (`scfb` on UEFI, `vesa` on BIOS), a light
   window manager and the installer full screen. The decision and its reason
   are in `/var/run/luna-live/`; the installer shows the reason.
5. The boot menu's *Troubleshooting* submenu (key T) sets
   `luna.basic_graphics` (skip the graphics driver) or
   `luna.text_installer` (no graphics; `/etc/rc.local` runs `install.sh`
   on the console).

The live user is `luna`, without password, allowed to use `doas` without
one; `root` has no password either, as on FreeBSD's own install media.

### What the build does

[`iso/build.sh`](../iso/build.sh), step by step (`STEPS` names):

| Step | What |
|---|---|
| `fetch` | `base.txz`, `kernel.txz` and `MANIFEST` of the release, checked against the MANIFEST |
| `root` | a ZFS pool in a file (`iso/work/root.img`, compression zstd), the base system unpacked into it, `freebsd-update` patches |
| `packages` | the packages in [`iso/packages.txt`](../iso/packages.txt), installed with `pkg -c` (the image's own ABI, repositories and install scripts). `drm-kmod` and `nvidia-drm-kmod` are pinned to one DRM version first |
| `configure` | this repository as `/usr/local/share/freebsd-setup` (as on installed systems), branding (`lib/branding.sh`), the installer, the live session files from [`iso/live/`](../iso/live), the live user, the release's `MANIFEST` (the installer checks the base system it downloads against it) |
| `trim` | compilers, headers, static libraries, documentation, manual pages and Python test suites removed: nobody compiles on a live system, and installations download their own packages |
| `image` | every block recompressed once at zstd-19 (`ZSTD_LEVEL`) in a second pool, then `zfs send -c` into `luna/system.zfs`. Packages are installed with fast zstd, so only this step is slow |
| `ramdisk` | the ramdisk with `/rescue` |
| `iso` | boot files, the EFI image, `makefs -t cd9660`, the hybrid GPT (`mkimg`, as FreeBSD's `mkisoimages.sh`) |

### Installation from the live system

The graphical installer collects the answers and runs the same
[`install.sh`](../install.sh) as the text installer, unattended
(`--config answers --yes`): partitions, ZFS, optional GELI, the base system
downloaded from download.freebsd.org (checked against the `MANIFEST` on the
ISO), boot entries, then `setup.sh` in the new system for drivers, desktop
and the rest. So a new system gets the newest packages, not the live image's.
The installer itself (`installer/`) only asks: `install.sh --probe` tells it
the disks, what is on them, whether installing next to them is possible and
why not, the boot managers found, and the hardware report.

## Change things

| To change | Edit |
|---|---|
| Name, version, FreeBSD release, package branch | [`distro.conf`](../distro.conf) |
| Logo, wallpaper, boot menu art | [`branding/`](../branding) (keep the file names, or change `lib/branding.sh`) |
| Packages on the live system | [`iso/packages.txt`](../iso/packages.txt), then check the size: `python3 iso/size.py` |
| Live session behaviour | [`iso/live/`](../iso/live) |
| Boot menu entries | [`iso/boot/local.lua`](../iso/boot/local.lua) |
| Installer pages | [`installer/qml/`](../installer/qml); logic in [`installer/luna_installer/`](../installer/luna_installer) |
| What an installation sets up | `setup.sh` and `stages/`, as before |

The name "FreeBSD" belongs to the FreeBSD Foundation; a derived system must
not present itself as FreeBSD. That is why the distribution has its own name,
while technical names that are FreeBSD's own stay (the `FreeBSD` firmware
boot entry starts FreeBSD's loader, `/EFI/freebsd`, `freebsd-update`).

## Test

```sh
python3 tests/installer-test.py        # installer logic (any OS, no Qt)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  python3 installer/luna-installer --screenshots /tmp/shots   # every page, fails on QML warnings (needs PyQt6)
python3 installer/luna-installer --demo                       # click through it (nothing is changed)
sh tests/vm/run-live-test.sh iso/out/lunabsd-*.iso uefi        # boot the ISO in QEMU
sh tests/vm/run-secureboot-test.sh iso/out/lunabsd-*.iso setup # Secure Boot, Setup Mode (OVMF)
sh tests/vm/run-secureboot-test.sh iso/out/lunabsd-*.iso mok   # Secure Boot with shim and MokManager (needs tesseract)
```

`run-live-test.sh` boots the ISO in QEMU (UEFI by default, `bios` as second
argument; `MEDIA=usb` attaches it as a USB stick instead of a DVD, which
tests the hybrid GPT and its EFI partition), checks that the system was copied into memory, re-rooted, chose
the installer session (QEMU has no KMS graphics) and started X and the
installer, and saves a picture of the screen as
`tests/vm/live-work/screen.png`. What it cannot test: the KDE Plasma live
session and the graphics drivers, which need a real graphics card. Try those
on real hardware, and run `tests/desktop-probe.sh` in the live session.

To try an installation from the live system without a USB stick, start the
ISO in a VM with a second, empty disk (`qemu-img create -f qcow2 disk.qcow2
40G`) and install onto it with *Desktop: None* for speed, or use
`tests/vm/run-iso-test.sh` for the unattended text installer.

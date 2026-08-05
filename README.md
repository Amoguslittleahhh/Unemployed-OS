# Unemployed OS

> *"Arch under the hood, hired the moment you boot it."*

This is Unemployed OS, where I literally create a working OS from scratch using nothing but a bunch of AI.

An Arch Linux–based distro aimed at a Zorin-OS-level polished desktop:
zero-terminal daily use, full Windows-app compatibility, and rock-solid
hardware support. The full design/spec doc lives at
[`docs/build-plan.md`](docs/build-plan.md) — that's the source of truth for
architecture decisions, driver strategy, compliance mapping, and the release
gate. This README only tracks *build status*.

## Status

**Milestones 1–4 (live medium, GNOME desktop, taskbar, Calamares installer)
are built, booted, and logged in -- fully verified.** `scripts/build-iso.sh`
produces a real 2.2GB `unemployed-os-<date>-x86_64.iso` via Docker +
`mkarchiso` + `xorriso` with the full package set (GNOME, PipeWire,
Calamares, ~910 packages installed). Booting it in QEMU (screendump-verified,
since this dev sandbox has no display) confirmed the whole chain: the
rebranded SYSLINUX menu, `linux-zen` kernel/initramfs loading, archiso's boot
hooks succeeding (squashfs mounted), a full systemd boot, a working GDM
greeter, and -- logged in as `liveuser` -- a rendered GNOME Shell desktop
with the dash-to-panel taskbar showing the configured pinned apps
(Nautilus/Terminal/Settings/Show-Applications) and NetworkManager running --
see [`docs/screenshots/gnome-desktop-boot-verify-2026-08-05.png`](docs/screenshots/gnome-desktop-boot-verify-2026-08-05.png).
That whole boot took roughly 40 minutes end to end purely because this dev
sandbox has no KVM (no `/dev/kvm`, no nested virtualization) -- QEMU falls
back to full software CPU emulation (TCG), so a systemd+GNOME boot that's
~10-20s on real hardware or under KVM stretches out enormously. Getting here
exercised (and found real bugs in) the kernel/initramfs swap, the Calamares
config, and the extension-install pipeline -- see the commit history for
what broke and got fixed along the way, including a build-blocking
dconf-corruption bug and a real security issue (the live-session's
passwordless `liveuser` account surviving onto installed systems, now
stripped by Calamares before the target system boots).

Not yet exercised: an actual Calamares install-to-disk run (only the live
session has been verified, not the installer's own execution). See "Known
gaps" below for what's still explicitly unfinished scope (not a build
concern).

- [x] **Milestone 1 — boots to a live session.** `archiso/` forked from the
      official [`releng`](https://github.com/archlinux/archiso/tree/master/configs/releng)
      profile, rebranded (ISO label/name, hostname, motd, boot menu titles).
- [x] **Milestone 2 — desktop shell.** `packages.x86_64` pulls in GNOME
      shell + GDM + NetworkManager + PipeWire + Mesa/VA-API (Intel+AMD only
      for now) + Calamares, on top of the rescue-toolkit base releng ships.
      Kernel switched from `linux` to `linux-zen` per Part I (all boot-menu
      configs — syslinux/GRUB/systemd-boot — and the mkinitcpio preset were
      updated to match the new `vmlinuz-linux-zen` filename).
- [x] **Milestone 3 — taskbar + start menu.** `archiso/airootfs/root/customize_airootfs.sh`
      (an mkarchiso build-time chroot hook) fetches
      [dash-to-panel](https://github.com/home-sweet-gnome/dash-to-panel) (pinned `v73`)
      and [ArcMenu](https://github.com/jordimas/gnome-shell-extension-arcmenu) (pinned `v49-Stable`)
      at ISO-build time, installs them via each project's own `make install`,
      and enables them by UUID. `archiso/airootfs/etc/dconf/db/local.d/00-unemployed-os-desktop`
      sets a Windows-style default (bottom taskbar, ArcMenu "Redmond" layout,
      dark theme) — this is a fixed default, not yet the runtime Desktop
      Layout Switcher Part II describes.
- [x] **Milestone 4 — installer.** `archiso/airootfs/root/calamares-config/`
      (staged there, then applied to `/etc/calamares` by `customize_airootfs.sh`
      *after* packages install — see "Known gaps" for why) is a full Calamares
      config (settings.conf + module confs + branding), adapted from upstream
      Calamares' own current defaults and EndeavourOS' as a structural
      reference. Partitioning defaults to Btrfs with `@` `@home` `@var`
      `@snapshots` subvolumes (Part I), GDM-only displaymanager config,
      GNOME/NetworkManager service enablement, and a shellprocess step that
      swaps the live image's archiso-only mkinitcpio preset for a normal
      installed-system one before initramfs generation runs.
- [x] `scripts/build-iso.sh` / `scripts/run-qemu.sh` — build and boot-test
      scripts (Docker-based build, with a fallback to native `mkarchiso`;
      QEMU with KVM/OVMF if available).

## Known gaps (read before trusting a build)

- **`calamares` isn't in official Arch repos.** It's AUR-only upstream,
  and mkarchiso's package install step is plain pacman with no AUR-build
  capability. `archiso/pacman.conf` bootstraps it from CachyOS's binary
  repo with `SigLevel = Never` on that repo only — a real trust shortcut
  (an external mirror's packages install unsigned into the build), not a
  real answer. Building and signing our own `calamares` package is
  tracked here as follow-up; this should go away once that exists.
- **The Docker build runs `--privileged`.** `mkarchiso` needs loopback/squashfs
  mount capabilities that an unprivileged container can't get; `--privileged`
  is the common pattern for containerized archiso builds, but it does mean
  the container gets real host-level capabilities. Only run this against
  a tree you trust.
- **`linux-lts` isn't bundled.** Part I wants zen-default/LTS-fallback; only
  `linux-zen` is in `packages.x86_64` right now because archiso's multi-kernel
  boot-menu wiring needs verifying on a real build before committing to it
  blind. Installing `linux-lts` post-install (`pacman -S linux-lts`) works
  today; baking it into the live medium is follow-up work.
- **No custom branding assets.** `archiso/airootfs/root/calamares-config/branding/unemployedos/branding.desc`
  has no logo/wallpaper/slideshow images yet — Calamares runs fine without
  them (stock look), but Part II's in-house GTK4/libadwaita theme + icon pack
  is still entirely unstarted.
- **The "Desktop Layout Switcher" is a fixed dconf default, not a switcher.**
  Windows-style taskbar/menu settings apply on first login; swapping to a
  macOS-style or Ubuntu-style layout at runtime (Part II's actual
  requirement) isn't built.
- **LUKS disk encryption isn't wired into the installer** despite being a
  Part IX MUST for the long-term bar — `partition.conf` only offers
  Btrfs/ext4 today. Tracked, not silently dropped.
- **Nvidia/driver auto-detection (Part III), Windows compatibility layer
  (Part IV), virtualization (Part V)** are all untouched — deliberately,
  per the plan's own ordering (Part XV milestone 5: those need real/varied
  hardware and would stall everything else if tackled before the desktop
  shell is solid).

## CI

`.github/workflows/ci.yml` runs `scripts/validate.sh` on every push/PR --
the "package/config unit tests" item from Part XI of the plan. It's fast,
no-network sanity checking (shell syntax, shellcheck, Calamares module YAML,
duplicate packages, required `profiledef.sh` fields), not a full ISO
build+boot -- that's still a manual step (`scripts/build-iso.sh` +
`scripts/run-qemu.sh`) since it needs privileged Docker and takes 20-30+
minutes. A real ISO-build-and-boot CI job is tracked as follow-up.

## Building

Requires Docker (or a native Arch host with `archiso` installed):

```sh
scripts/build-iso.sh
```

ISO output lands in `out/` (named `unemployed-os-<date>-x86_64.iso`), build
scratch space in `work/` (both gitignored).

## Testing in QEMU

Requires `qemu-system-x86_64` (`qemu-full` on Arch, `qemu-system-x86` on
Debian/Ubuntu). It auto-picks the newest ISO under `out/`:

```sh
scripts/run-qemu.sh
```

## Roadmap

Milestones, per Part XV of the plan:

1. Boots to a plain Arch live session in QEMU — **built and boot-verified.**
2. Swap in GNOME + a first-party theme package — **built and boot-verified**
   (no custom theme assets yet).
3. Taskbar/layout-switcher extension loading on boot — **built and
   boot-verified** (dash-to-panel confirmed rendering with the configured
   pinned apps; fixed default, not a runtime switcher yet).
4. Wire in a Calamares installer config — **built**; the live session it
   installs from is boot-verified, but an actual install-to-disk run through
   Calamares itself hasn't been exercised yet.
5. **Next real step: run an actual Calamares install to disk** (not just
   boot the live session) and confirm the installed system boots. Only
   after that holds up: drivers (Part III) and virtualization (Part V).

Later phases (Windows compatibility layer, full driver matrix, apps,
accessibility/compliance, full QA per Part XI) are scoped in Parts III–XI of
the plan document and start after the desktop shell + installer milestones
above are confirmed working on real hardware.

## Repo layout

```text
archiso/                      archiso profile (ISO build definition)
  packages.x86_64             package list (rescue tools + GNOME desktop + Calamares)
  profiledef.sh                ISO metadata (name/label/kernel boot entries)
  airootfs/                   files overlaid onto the live filesystem
    root/customize_airootfs.sh   build-time chroot hook (users, services, extensions)
    root/calamares-config/       installer config, applied to /etc/calamares post-install
    root/postinstall-assets/     files Calamares copies onto the target during install
    etc/dconf/db/local.d/        default desktop settings (dconf)
scripts/                      build-iso.sh, run-qemu.sh
docs/build-plan.md            full spec: architecture, compliance mapping, testing framework
```

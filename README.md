# Unemployed OS

> *"Arch under the hood, hired the moment you boot it."*

This is Unemployed OS, where i literally create an working OS from scratch using nothing but a bunch of AI.

An Arch Linux–based distro aimed at a Zorin-OS-level polished desktop:
zero-terminal daily use, full Windows-app compatibility, and rock-solid
hardware support. The full design/spec doc lives at
[`docs/build-plan.md`](docs/build-plan.md) — that's the source of truth for
architecture decisions, driver strategy, compliance mapping, and the release
gate. This README only tracks *build status*.

## Status: milestones 1–4 written, still unbuilt/unbooted

Per the plan's Part XV ("Getting Started"), milestone 1 was just a plain
bootable `archiso`. That's done, and milestones 2–4 (desktop shell, taskbar,
installer) are now written too — but **nothing here has actually been built
or booted yet**. See "Known gaps" below before trusting any of it.

- [x] **Milestone 1 — boots to a live session.** `archiso/` forked from the
      official [`releng`](https://github.com/archlinux/archiso/tree/master/configs/releng)
      profile, rebranded (ISO label/name, hostname, motd, boot menu titles).
- [x] **Milestone 2 — desktop shell.** `packages.x86_64` now pulls in GNOME
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
- [x] **Milestone 4 — installer.** `archiso/airootfs/etc/calamares/` is a full
      Calamares config (settings.conf + module confs + branding), adapted
      from upstream Calamares' own defaults and EndeavourOS' as a structural
      reference. Partitioning defaults to Btrfs with `@` `@home` `@var`
      `@snapshots` subvolumes (Part I), GDM-only displaymanager config,
      GNOME/NetworkManager service enablement, kernel-agnostic
      `mkinitcpio`/bootloader steps (works with whatever kernels end up
      installed).
- [x] `scripts/build-iso.sh` / `scripts/run-qemu.sh` — build and boot-test
      scripts (Docker-based build, since this dev container has neither
      pacman nor archiso; QEMU with KVM/OVMF if available).

## Known gaps (read before building)

- **Milestone 1 (plain live medium) has now actually been built and boot-verified.**
  With network access opened up, `scripts/build-iso.sh` ran for real: it
  pulled `archlinux:latest`, resolved a TLS-intercepting-proxy trust issue
  (fixed in the script itself), and produced a real 1.5GB bootable ISO via
  Docker + `mkarchiso` + `xorriso`, no errors. Booting it in QEMU (TCG, no
  KVM in this sandbox) showed the SYSLINUX menu correctly rebranded
  ("Unemployed OS install medium (x86_64, BIOS)") and the kernel/initramfs
  loading; the VM ran for several minutes afterward without crashing, though
  full console output wasn't captured (no `console=ttyS0` on the boot
  cmdline, no display capture in this headless sandbox) so reaching a login
  prompt wasn't directly confirmed.
- **Milestones 2–4 (GNOME + taskbar + Calamares) are still unbuilt.** The one
  build that ran used a stale on-disk snapshot of the repo (from mid-session,
  before a local git-state issue was caught and fixed — see commit history
  around `bb0bea5`) that predates the GNOME/Calamares work, so it only
  exercised the milestone-1 rescue-toolkit ISO. The milestone 2–4 config
  (packages.x86_64 GNOME additions, customize_airootfs.sh, Calamares) is
  correctly on this branch but has never itself gone through a real build.
  That's the next concrete step — rerun `scripts/build-iso.sh` against the
  current tree.
- **`linux-lts` isn't bundled.** Part I wants zen-default/LTS-fallback; only
  `linux-zen` is in `packages.x86_64` right now because archiso's multi-kernel
  boot-menu wiring needs verifying on a real build before committing to it
  blind. Installing `linux-lts` post-install (`pacman -S linux-lts`) works
  today; baking it into the live medium is follow-up work.
- **No custom branding assets.** `calamares/branding/unemployedos/branding.desc`
  has no logo/wallpaper/slideshow images yet — Calamares runs fine without
  them (stock look), but Part II's in-house GTK4/libadwaita theme + icon pack
  is still entirely unstarted.
- **The "Desktop Layout Switcher" is a fixed dconf default, not a switcher.**
  Windows-style taskbar/menu settings apply on first login; swapping to a
  macOS-style or Ubuntu-style layout at runtime (Part II's actual
  requirement) isn't built.
- **Nvidia/driver auto-detection (Part III), Windows compatibility layer
  (Part IV), virtualization (Part V), and disk encryption by default
  (Part IX)** are all untouched — deliberately, per the plan's own ordering
  (Part XV milestone 5: those need real/varied hardware and would stall
  everything else if tackled before the desktop shell is solid).

## Building

Requires Docker (or a native Arch host with `archiso` installed):

```sh
scripts/build-iso.sh
```

ISO output lands in `out/`, build scratch space in `work/` (both gitignored).

## Testing in QEMU

Requires `qemu-system-x86_64` (`qemu-full` on Arch, `qemu-system-x86` on
Debian/Ubuntu):

```sh
scripts/run-qemu.sh
```

## Roadmap

Milestones, per Part XV of the plan:

1. ~~Boots to a plain Arch live session in QEMU~~ — written, unverified.
2. ~~Swap in GNOME + a first-party theme package~~ — written (no custom
   theme assets yet), unverified.
3. ~~Taskbar/layout-switcher extension loading on boot~~ — written (fixed
   default, not a runtime switcher yet), unverified.
4. ~~Wire in a Calamares installer config~~ — written, unverified.
5. **Next real step: get 1–4 actually building and booting** on a machine
   with working internet, then iterate on whatever breaks. Only after that
   holds up: drivers (Part III) and virtualization (Part V).

Later phases (Windows compatibility layer, full driver matrix, apps,
accessibility/compliance, full QA per Part XI) are scoped in Parts III–XI of
the plan document and start after the desktop shell + installer milestones
above are confirmed working on real hardware.

## Repo layout

```
archiso/                      archiso profile (ISO build definition)
  packages.x86_64             package list (rescue tools + GNOME desktop + Calamares)
  profiledef.sh                ISO metadata (name/label/kernel boot entries)
  airootfs/                   files overlaid onto the live filesystem
    root/customize_airootfs.sh   build-time chroot hook (users, services, extensions)
    etc/dconf/db/local.d/        default desktop settings (dconf)
    etc/calamares/                installer config (settings.conf, modules/, branding/)
scripts/                      build-iso.sh, run-qemu.sh
docs/build-plan.md            full spec: architecture, compliance mapping, testing framework
```

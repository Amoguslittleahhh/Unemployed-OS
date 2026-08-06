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

**Milestones 1-3 (live medium, GNOME desktop, taskbar) are built, booted, and
logged in -- fully verified. Milestone 4 (Calamares installer) is built and
included on the live medium, but an actual install-to-disk run through
Calamares -- and boot-testing the resulting installed system -- has not been
exercised yet.** `scripts/build-iso.sh`
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
- [x] **Milestone 3 — taskbar + start menu; [x] 12-layout switcher, boot-verified.**
      `archiso/airootfs/root/customize_airootfs.sh`
      (an mkarchiso build-time chroot hook) fetches
      [dash-to-panel](https://github.com/home-sweet-gnome/dash-to-panel) (pinned `v73`),
      [ArcMenu](https://github.com/jordimas/gnome-shell-extension-arcmenu) (pinned `v49-Stable`),
      and [dash-to-dock](https://github.com/micheleg/dash-to-dock) (pinned to a
      specific reviewed commit, not the floating `master` branch — see
      `customize_airootfs.sh` for why) at ISO-build time, installs them via
      each project's own `make install`, and enables the panel+menu pair by
      default via UUID.
      `archiso/airootfs/etc/dconf/db/local.d/00-unemployed-os-desktop` sets
      the Windows 11-style default (bottom taskbar, ArcMenu "Redmond" layout,
      dark theme).
      `usr/local/bin/uos-layout-switcher` (run it with a layout name, no
      args to list them) is a real runtime switcher covering 12 presets —
      `windows11`, `windows`, `windows-classic`, `windows-list`,
      `compact-panel`, `touch`, `chromeos`, `cinnamon`, `gnome-shell` (stock,
      no panel/dock extension), `macos`, `ubuntu`, `elementary` (the last
      three use dash-to-dock instead of dash-to-panel).
      **Boot-verified**: a full QEMU/TCG boot reached GDM, logged into the
      default Windows-style taskbar layout, and `uos-layout-switcher macos`
      (run as the normal user — **not** `sudo`, which breaks dconf's D-Bus
      session access and fails outright) switched live to a working
      dash-to-dock bottom dock + top menu bar after a re-login, confirmed via
      `gnome-extensions list` showing `dash-to-dock@micxgx.gmail.com`
      actually installed. Getting there required a real fix along the way:
      dash-to-dock's `make install` depends on `sassc` (for its
      `stylesheet.css`), which wasn't in `packages.x86_64` — without it, the
      recursive `make` failed but the *outer* `make install` still returned
      0, so the extension silently never got copied into
      `/usr/share/gnome-shell/extensions` despite `customize_airootfs.sh`
      reporting success. Fixed by adding `sassc` to `packages.x86_64` and
      hardening `install_extension()` to verify the extension directory
      actually exists post-install rather than trusting the exit code alone.
      **All 12 layouts have now been run for real** (`for l in ...; do
      uos-layout-switcher $l; done`, checked via exit code + a live
      re-login for `macos`, `ubuntu`, and `elementary`), which caught three
      more real bugs, all now fixed:
      - `taskbar-position` isn't a real dash-to-panel key (confirmed
        against the actual `schemas/*.gschema.xml` in the v73 tag) —
        `dconf write` silently accepted and ignored it. The intended
        Windows-11-style *centered* taskbar (used by the default layout,
        `windows11`, `compact-panel`, `touch`, `chromeos`) needs
        `panel-element-positions` instead, a per-monitor JSON array of
        `{element, visible, position}` entries (element names and valid
        `position` values taken from dash-to-panel's own
        `src/panelPositions.js`). The left-aligned layouts (`windows`,
        `windows-classic`, `windows-list`, `cinnamon`) needed no fix at
        all, since dash-to-panel's real default already puts the taskbar
        left-aligned — the bogus key was just dead weight there.
      - ArcMenu's dconf key is `menu-button-icon`, not
        `menu-button-icon-type` (verified against ArcMenu's real
        `org.gnome.shell.extensions.arc-menu.gschema.xml`) — every one of
        the 12 layouts had this wrong, so ArcMenu was silently using its
        default icon instead of the distro icon everywhere.
      - `uos-layout-switcher`'s `none` mode (stock GNOME Shell, no
        panel/dock extension — the `gnome-shell` layout) called
        `dconf write /org/gnome/shell/enabled-extensions "[]"`, which
        GVariant can't parse (`error: unable to infer type` — an empty
        array literal has no element type without an explicit
        annotation). Fixed to `"@as []"` (empty array of strings).
      ArcMenu's own per-layout "start menu style" isn't varied beyond the
      one enum value (`Redmond`) confirmed working — the other 11 layouts
      differentiate themselves through panel/dock position, size, and icon
      spacing rather than guessed ArcMenu enum strings that could be
      silently wrong.
- [ ] **Milestone 4 — installer (built, not install-tested).**
      `archiso/airootfs/root/calamares-config/` (staged there, then applied
      to `/etc/calamares` by `customize_airootfs.sh` *after* packages
      install — see "Known gaps" for why) is a full Calamares config
      (settings.conf + module confs + branding), adapted from upstream
      Calamares' own current defaults and EndeavourOS' as a structural
      reference. Partitioning defaults to Btrfs with `@` `@home` `@var`
      `@snapshots` subvolumes (Part I), GDM-only displaymanager config,
      GNOME/NetworkManager service enablement, and a shellprocess step that
      swaps the live image's archiso-only mkinitcpio preset for a normal
      installed-system one before initramfs generation runs. None of this
      has been exercised by an actual install-to-disk run yet — only that
      the config is present on the booted live image.
- [x] `scripts/build-iso.sh` / `scripts/run-qemu.sh` — build and boot-test
      scripts (Docker-based build, with a fallback to native `mkarchiso`;
      QEMU with KVM/OVMF if available). `run-qemu.sh`'s TCG fallback now
      requests 4 emulated cores (up from 2) with multi-threaded TCG
      explicitly enabled, for a faster/less-variable software-emulation
      boot on hosts with spare cores — doesn't touch KVM path or fix
      host-level instability (container restarts/suspension), just uses
      the CPU-emulation cores QEMU gets more fully.
- [ ] **Windows compatibility layer (Part IV) — packages added; runtime
      and GUI verification pending.** `packages.x86_64` adds `wine`,
      `winetricks`, and `vkd3d`, and `pacman.conf` now enables
      `[multilib]` (required for 32-bit Windows app/game support —
      without it, wine only covers 64-bit apps). `dxvk-bin` was tried and
      removed: it's AUR-only, not available in any repo this profile
      enables, so `winetricks dxvk` is the practical workaround for D3D9
      -11 translation until a real DXVK package source is added. Not
      install- or boot-tested this round.
- [ ] **Creative suite (Part VIII) — unverified.** `packages.x86_64` adds
      GIMP, Krita, Inkscape, Scribus, Kdenlive, Blender, Audacity,
      OBS Studio, and darktable. Not install- or boot-tested this round.

## Known gaps (read before trusting a build)

- **`calamares` isn't in official Arch repos (Unemployed OS issue #5).**
  It's AUR-only upstream, and mkarchiso's package install step is plain
  pacman with no AUR-build capability. `archiso/pacman.conf` bootstraps it
  from CachyOS's binary repo with `SigLevel = Never` on that repo only — a
  real trust shortcut (an external mirror's packages install unsigned into
  the build), not a real answer. CachyOS does publish a real
  `cachyos-keyring` package (verified via their `CachyOS-PKGBUILDS` repo),
  so the actual fix is bootstrapping that keyring (pinned by checksum,
  since we can't verify its signature before we have it) before the rest
  of `[cachyos]` switches to `SigLevel = Required` — not done here, since
  getting that bootstrap wrong would silently break every build, and it
  needs a real build+verify cycle this pass didn't include. Building and
  signing our own `calamares` package remains the cleaner long-term fix.
- **The Docker build runs `--privileged` (Unemployed OS issue #7).**
  `mkarchiso` needs loopback/squashfs mount capabilities that an
  unprivileged container can't get; `--privileged` is the common pattern
  for containerized archiso builds, but it does mean the container gets
  real host-level capabilities, and `customize_airootfs.sh`/other
  repo-tree hooks run with them. `scripts/build-iso.sh` now stops and
  requires an explicit `y` confirmation before running privileged in an
  interactive session (set `UOS_SKIP_PRIVILEGED_CONFIRM=1` for CI/scripted
  use) — real informed-consent friction, not a security boundary. A
  reduced `--cap-add` allowlist replacing `--privileged` entirely would be
  the real fix, but needs mkarchiso's actual mount/loopback requirements
  re-verified against it, which risks silently breaking every build if
  gotten wrong — not attempted blind in this pass.
- **`linux-lts` isn't bundled.** Part I wants zen-default/LTS-fallback; only
  `linux-zen` is in `packages.x86_64` right now because archiso's multi-kernel
  boot-menu wiring needs verifying on a real build before committing to it
  blind. Installing `linux-lts` post-install (`pacman -S linux-lts`) works
  today; baking it into the live medium is follow-up work.
- **No custom branding assets.** `archiso/airootfs/root/calamares-config/branding/unemployedos/branding.desc`
  has no logo/wallpaper/slideshow images yet — Calamares runs fine without
  them (stock look), but Part II's in-house GTK4/libadwaita theme + icon pack
  is still entirely unstarted.
- **The Desktop Layout Switcher (`uos-layout-switcher`, 12 presets) has
  had all 12 presets applied for real in a live boot** — see Milestone 3
  above for the three real bugs that surfaced doing this (wrong
  dash-to-panel/ArcMenu dconf key names, an empty-array GVariant literal
  dconf couldn't parse) and how they were fixed. Visually confirmed via a
  live re-login for the `windows` (default), `macos`, `ubuntu`, and
  `elementary` presets specifically (taskbar/dock actually rendered where
  expected); the remaining 8 were confirmed to apply without error but
  weren't each individually eyeballed post-re-login.
- **LUKS disk encryption is wired but not install-verified yet.** Calamares'
  partition module exposes its normal "Encrypt system" flow (`cryptsetup` is
  in `packages.x86_64`), and `shellprocess_wire_luks.conf` patches in the
  mkinitcpio `encrypt` hook and `GRUB_ENABLE_CRYPTODISK=y` that Calamares'
  own declarative modules can't express. Untested by an actual encrypted
  install-to-disk run (see the Milestone 4 install-verification gap above).
- **PXE/NBD/NFS/HTTP netboot (`archiso/syslinux/archiso_pxe-linux.cfg`) has
  no authentication for the kernel/initramfs payloads.** This is inherent to
  unauthenticated network boot (`cms_verify=y` only covers the rootfs, not
  the pre-root LINUX/INITRD transfer) and isn't specific to our config --
  real fix needs UEFI Secure Boot + a signed shim/kernel chain, out of scope
  for now. Documented in the config file itself: only serve these paths on
  a trusted, isolated network.
- **Nvidia/driver auto-detection (Part III) and virtualization (Part V)**
  are untouched — deliberately, per the plan's own ordering (Part XV
  milestone 5: those need real/varied hardware and would stall everything
  else if tackled before the desktop shell is solid). The Windows
  compatibility layer (Part IV) has packages added (see above) but is
  still unverified by any real boot/GUI test.

## CI

`.github/workflows/ci.yml` runs `scripts/validate.sh` on every push/PR --
the "package/config unit tests" item from Part XI of the plan. It's fast,
no-network sanity checking (shell syntax, shellcheck, Calamares module YAML,
duplicate packages, required `profiledef.sh` fields), not a full ISO
build+boot -- that's still a manual step (`scripts/build-iso.sh` +
`scripts/run-qemu.sh`) since it requires Docker with privileged mode and
takes 20-30+ minutes. A real ISO-build-and-boot CI job is tracked as follow-up.

## Building

Requires Docker (or a native Arch host with `archiso` installed):

```sh
scripts/build-iso.sh
```

ISO output lands in `out/` (named `unemployed-os-<date>-x86_64.iso`), build
scratch space in `work/` (both gitignored).

By default `core`/`extra`/`multilib` resolve against whatever the live Arch
mirrors have right now (the point of a rolling-release ISO) -- the
digest-pinned builder image (`UOS_BUILDER_IMAGE`, see `scripts/build-iso.sh`)
only pins the build *tooling*, not package versions. For a reproducible
build from a given commit, pin package inputs to an Arch Linux Archive
snapshot date instead (Unemployed OS issue #8; doesn't cover the unsigned
`[cachyos]` bootstrap repo -- see "Known gaps"):

```sh
UOS_PACMAN_SNAPSHOT_DATE=2026/08/01 scripts/build-iso.sh
```

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

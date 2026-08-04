# Unemployed OS

> *"Arch under the hood, hired the moment you boot it."*

This is Unemployed OS, where i literally create an working OS from scratch using nothing but a bunch of AI.

An Arch Linux–based distro aimed at a Zorin-OS-level polished desktop:
zero-terminal daily use, full Windows-app compatibility, and rock-solid
hardware support. The full design/spec doc lives at
[`docs/build-plan.md`](docs/build-plan.md) — that's the source of truth for
architecture decisions, driver strategy, compliance mapping, and the release
gate. This README only tracks *build status*.

## Status: Milestone 1 — plain bootable ISO

Per the plan's Part XV ("Getting Started"), the first milestone is just a
custom `archiso` build that boots in QEMU — everything else (theme,
taskbar/layout switcher, installer, drivers) comes after that's solid.

- [x] `archiso/` — forked from the official [`releng`](https://github.com/archlinux/archiso/tree/master/configs/releng)
      profile, rebranded (ISO label/name, hostname, motd, boot menu titles).
      Package list is still the stock live-environment set — no DE yet.
- [x] `scripts/build-iso.sh` — builds the ISO. Uses native `mkarchiso` if
      present, otherwise drives an `archlinux` Docker container (this repo's
      dev container is Ubuntu-based and has neither pacman nor archiso
      installed, so the Docker path is what most contributors will use).
- [x] `scripts/run-qemu.sh` — boots the newest built ISO in QEMU (KVM-accelerated
      if `/dev/kvm` is available, UEFI via OVMF if installed) for the fast
      inner loop the plan describes.
- [ ] **Not yet verified end-to-end** — this dev container has neither a
      running Docker daemon nor QEMU/KVM available, so the build has not
      actually been run here. Do that first on a machine with Docker (or a
      native Arch host) before trusting this layout.

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

Milestones, in order (Part XV of the plan):

1. **Boots to a plain Arch live session in QEMU** — done, pending a real
   build/boot run to confirm the pipeline actually works.
2. Swap in the chosen DE (GNOME shell, per Part II Option A) + a first-party
   theme package into the profile.
3. Get the taskbar/layout-switcher extension loading on boot.
4. Wire in a Calamares installer config — install-to-disk, not just live-boot.
5. Only once 1–4 are solid: drivers (Part III) and virtualization (Part V),
   since those need real/varied hardware and would otherwise stall everything
   else.

Later phases (drivers, Windows compatibility layer, virtualization, apps,
accessibility/compliance, full QA) are scoped in Parts III–XI of the plan
document and only start after the desktop shell milestone above is solid.

## Repo layout

```
archiso/         forked+rebranded releng archiso profile (ISO build definition)
scripts/         build-iso.sh, run-qemu.sh
docs/build-plan.md   full spec: architecture, compliance mapping, testing framework
```

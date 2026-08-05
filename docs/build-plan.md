# Unemployed OS — Master Build Plan
### Codename: `unemployed-os` | Base: Arch Linux (rolling) | Targets: `x86_64` (primary), `aarch64` (Qualcomm-scoped spin)
> *"Arch under the hood, hired the moment you boot it."*

---

## PART 0 — SCOPE & METHODOLOGY NOTE

This plan stays **Arch Linux–based** (Linux kernel, systemd, Mesa/proprietary drivers, Wayland/X11, existing filesystem drivers). A companion "from-scratch OS" document was reviewed and its **format** is adopted here — strict MUST/SHOULD/MAY tagging, a numbered PART structure, a compliance mapping table, and a dedicated testing framework — but not its architecture. Writing a kernel, display server, GUI toolkit, filesystem, and network stack from zero is a multi-year, large-team undertaking; nothing in this document assumes that path.

On "every international standard in the world": that's not a coherent target — most of the ~24,000 published ISO standards (bolt thread sizes, coffee testing, etc.) have nothing to do with an operating system. What follows is every standard that is **actually applicable** to an OS, grouped by category, each with a strict pass/fail bar. That is a stricter and more honest deliverable than a list padded with irrelevant standards.

**Requirement tags (unchanged from before):**
- **MUST** — release blocker, no exceptions.
- **SHOULD** — required for the flagship x86_64 build; may slip on the ARM64 spin with a public tracking issue.
- **MAY** — backlog, never blocks a release.

---

## PART I — VISION & BASE ARCHITECTURE

**Unemployed OS** pairs Arch's rolling-release flexibility and package depth (pacman + AUR) with a polished, beginner-friendly desktop comparable to Zorin OS, for professionals who want zero-terminal daily use, full Windows-app compatibility, and rock-solid hardware support.

| Layer | Choice | Rationale |
|---|---|---|
| Base | Arch Linux (rolling) | Bleeding-edge packages, huge AUR ecosystem, minimal bloat baseline |
| Kernel | `linux-zen` default, `linux-lts` fallback/recovery | Zen for desktop responsiveness; LTS as the safety net for driver regressions |
| Init | systemd | Standard, best driver/power tooling support |
| Package manager | pacman + paru (AUR) behind a GUI Software Center | Keeps Arch's depth accessible without a terminal |
| Installer | Custom Calamares-based, guided partitioning, driver auto-detect, live "Try before install" | Arch's manual installer is the #1 reason it isn't beginner friendly today |
| Filesystem default | Btrfs, subvolumes `@` `@home` `@var` `@snapshots` | Enables rollback (below), compression, easy resizing |
| Updates | `timeshift`-driven Btrfs snapshot before every system update | Rolling release without rollback is a support disaster for non-experts — non-negotiable |

**Strict acceptance bar:**
- MUST: fresh install → usable desktop in ≤15 minutes on reference hardware (NVMe SSD, 8GB RAM min-spec).
- MUST: an interrupted `pacman -Syu` (power loss, disk full) never leaves the system unbootable — snapshot rollback restores boot with zero manual `chroot`, verified in CI on every ISO build.
- MUST: Secure Boot works end-to-end (shim + `sbctl` signing) with no manual key-enrollment steps in the default path.
- MUST: live session boots to a fully functional desktop (network, browser, driver detection) in under 60 seconds on reference hardware.
- SHOULD: automatic snapshot pruning (age + count) shipped by default.

---

## PART II — DESKTOP ENVIRONMENT / UI-UX

Two realistic paths — one flagship, one official spin:

**Option A (recommended): custom GNOME shell** — most polished compositor/animation stack; shell extensions replicate a traditional taskbar + start menu (GNOME's dock-only default is the #1 thing that scares Windows/macOS switchers); own GTK4/libadwaita theme + icon pack designed in-house, not a reskin; built-in Desktop Layout Switcher (Windows-style / macOS-style / Ubuntu-style) for onboarding.

**Option B: custom KDE Plasma spin** — closer to a Windows-style taskbar by default, deeply customizable, but needs heavier theming work to avoid the "generic default KDE" look.

**Strict acceptance bar:**
- MUST: consistent design tokens (spacing, radius, elevation, motion) enforced across every first-party app via a written design-system doc, checked at code review — no app ships with ad hoc styling.
- MUST: fractional scaling + HiDPI correctness verified on real 4K/5K panels, not emulated.
- MUST: zero visible flicker/tearing/compositor crash across a 4-hour continuous-use soak test (50+ window open/close cycles, monitor drag, sleep/wake).
- MUST: layout switcher applies with zero logout/re-login.
- MUST: full keyboard navigability (tab order, focus rings, screen-reader labels) on every first-party app and system dialog — this doubles as an accessibility requirement (see Part IX).
- SHOULD: blind usability test vs. Windows 11/macOS, target >80% task completion without assistance across 10 standard tasks.

---

## PART III — DRIVER SUBSYSTEM

Treated as its own owned subsystem, not an afterthought — this is the hardest engineering problem in the project.

**Intel** — Mesa graphics pre-integrated, `intel-media-driver` for VA-API hardware decode out of the box; Thunderbolt/USB4 via `bolt`; `thermald` + `power-profiles-daemon` pre-tuned for battery parity with Windows.

**AMD** — Mesa RADV/RadeonSI, `amdgpu` default kernel driver (no manual switching); ROCm offered at install if a supported GPU is detected; AMD P-State enabled by default on supported CPUs.

**Nvidia** — the one that kills most "beginner Arch" projects:
- installer auto-detects and installs `nvidia-dkms` (or `nvidia-open` on Turing+) with matching kernel headers, zero manual DKMS management
- hybrid/Optimus laptops get a GUI GPU-switcher applet in the taskbar (`optimus-manager`/`supergfxctl` backend)
- Wayland validated against the specific detected driver version; auto-falls back to X11 if unsupported
- Secure Boot: driver auto-signed via `sbctl` at install/update so a kernel update never silently breaks Nvidia boot — currently one of the most common Arch+Nvidia breakage vectors

**Qualcomm (ARM / Snapdragon X Elite class)** — scoped honestly: as of 2026, upstream GPU (Adreno), USB4, and firmware support for Snapdragon X Elite is still incomplete industry-wide (TUXEDO canceled a Snapdragon X1 Elite Linux laptop over exactly BIOS/fan-control/KVM/USB4/video-decode/battery gaps). v1 ships an ARM64 build scoped to specific community-verified device-tree-supported models only, sourced from Linaro/qcom upstreaming + `linux-firmware.git`. No device is marketed "supported" unless every feature is verified per-device (see HCL requirement below).

**Strict acceptance bar:**
- MUST: a maintained, versioned Hardware Compatibility List published with every release — every "supported" claim maps to a specific tested device/GPU/chipset, never a vendor-family generalization.
- MUST (Intel/AMD): zero manual driver steps for any GPU from the prior 5 years; hardware video decode verified via automated playback test in CI/QA, not just "driver present."
- MUST (Nvidia): unattended driver install + Secure Boot signing succeeds on 100% of CI-tested reference hardware; a kernel update is tested against Nvidia before promotion to the stable channel, never discovered by users.
- MUST NOT (Qualcomm/ARM64): label a device "supported" unless GPU accel, suspend/resume, and audio are individually confirmed — partial support is labeled per-feature in the HCL.
- SHOULD: full driver matrix re-run in CI against every new kernel/mesa/nvidia-driver package before promotion out of staging.

Cross-cutting: a first-party **Driver Manager** GUI (Windows Device Manager–style) showing detected hardware, active driver, alternatives, one-click switching.

---

## PART IV — WINDOWS COMPATIBILITY LAYER

1. **Native Wine (bundled, pre-tuned)** — curated build (or `wine-ge-custom`) with common DLL overrides pre-set, not vanilla Wine
2. **Bottles** as the first-party GUI front-end — isolated prefixes, sandboxing, a built-in known-working app catalog
3. **Proton/Proton-GE** wired into a first-party Steam/Lutris setup for gaming with no manual version hunting
4. **Winlator-style ARM translation** (FEX-Emu/box64/box86) for the Qualcomm/ARM64 spin, since x86 Windows binaries need an extra translation layer there
5. First-party **"Run with Windows Compatibility"** right-click action on `.exe`/`.msi` — auto-picks Wine vs. Bottles vs. Proton, no manual prefix setup
6. **GPU-passthrough Windows VM template** (`virt-manager`/QEMU + `looking-glass`, built on the Virtualization subsystem in Part V) as the "nuclear option" for the software Wine genuinely can't run

**Strict acceptance bar:**
- MUST: a curated, versioned compatibility database (own DB, seeded from ProtonDB/WineHQ AppDB patterns but maintained in-house) drives the compatibility heuristic — every entry maps to a verified-working config, never a guess.
- MUST: top-100 most-requested Windows productivity/creative apps (by tracked user survey) tested and their compatibility tier published before launch.
- MUST NOT: fail with a raw Wine error — every failure surfaces a specific, actionable message.
- SHOULD: one-click fallback from a failed Wine/Bottles attempt straight into the GPU-passthrough VM template.

---

## PART V — VIRTUALIZATION / HYPERVISOR SUPPORT

**QEMU/KVM (primary, first-party)** — `qemu-kvm` + `libvirt` + `virt-manager` pre-installed; KVM modules auto-load on any VT-x/AMD-V CPU; polished VM Manager GUI (OS auto-detect from ISO, sane defaults, virtio pre-selected) so no raw XML editing; virtio drivers + SPICE by default; VFIO/GPU-passthrough tooled with one-click IOMMU/GRUB config; snapshot/clone exposed in-GUI; nested virtualization on by default where supported.

**VMware Workstation/Player** — VMware ships proprietary kernel modules that historically break on kernel updates on Arch-family systems; an in-house maintained DKMS-integrated compatibility shim (community `vmware-host-modules`–style patching, maintained by the project, not left to the user) keeps it alive across routine kernel updates; verified on every LTS **and** zen kernel release before promotion to stable; a "Fix VMware after kernel update" one-click recovery action in the Driver Manager as the fallback if a regression slips through.

**VirtualBox** — `virtualbox` + host DKMS package through the first-party Software Center, auto-rebuilding on every kernel update; Guest Additions ISO bundled offline; kernel modules auto-signed through the same `sbctl` pipeline as Nvidia, or Secure Boot is clearly flagged as needing to be disabled, never a silent failure.

**Cross-cutting:** running any one of the three MUST NOT silently conflict with the others at the kernel-module level — real mutual-exclusion constraints between KVM/VirtualBox/VMware are surfaced in the VM Manager UI before a cryptic module-load error; a single "Virtualization Status" panel shows active hypervisor modules, VT-x/AMD-V state, IOMMU state, and detected conflicts.

**Strict acceptance bar:**
- MUST: all three hypervisors tested **in combination**, not just individually — the "supports all three" claim is false in practice if a power user running two of them hits an untested conflict.
- MUST: VMware/VirtualBox kernel modules rebuild and load successfully on the very next boot after any kernel package update, verified in CI, not discovered by users.
- SHOULD: bridged and NAT networking both selectable per-VM from the GUI, no hand-edited libvirt/vendor config.
- MAY: container/lightweight-VM tooling (`distrobox`, `podman`) offered as a secondary option in the same VM Manager.

---

## PART VI — FILE SYSTEM / FILE MANAGER

Nautilus (GNOME path) or Dolphin (KDE path), themed to the design system: tabs, split-pane, SMB/NFS network shares, cloud-drive integration (`rclone` GUI front-end), quick-preview for common file types. Full read/write for exFAT, NTFS via the `ntfs3` kernel driver (not FUSE `ntfs-3g`), native ext4/Btrfs. Built-in 7z/rar/zip archive support pre-installed. Search indexing (Tracker/Baloo) tuned for instant results. Trash/undo-delete/recovery hooks at the file-manager level.

**Strict acceptance bar:**
- MUST: NTFS read/write throughput within 90% of native ext4/Btrfs on the same disk, benchmarked.
- MUST: a 10,000-file/50GB mixed-size tree copies over SMB and locally with zero silently-dropped/corrupted files, checksum-verified in QA.
- MUST: file search returns results in under 1 second on a fully indexed 500GB home directory.
- MUST NOT: require a terminal for mounting a network share, extracting a password-protected archive, or recovering a trashed file.

---

## PART VII — TASKBAR & DISPLAYS

**Taskbar:** persistent panel (not dock-only) with Start menu, pinned apps, window previews on hover, tray, clock/calendar, quick-settings (Wi-Fi, Bluetooth, volume, brightness, GPU switch, DND); multi-monitor–aware (per-monitor taskbar option); Windows-style search-as-you-type across apps/files/settings; repositionable/restyleable via the layout switcher, no extensions or terminal config.

**Displays:** Wayland-first (with the Nvidia-aware fallback from Part III) for correct fractional/per-monitor scaling and HDR groundwork; GUI display settings with drag-and-drop arrangement, mixed-DPI correctness, saved profiles ("docked" vs. "laptop-only") auto-applied on hotplug; ICC color-profile support for creative work; eGPU hot-plug tested specifically.

**Strict acceptance bar:**
- MUST: taskbar search returns results within 300ms of first keystroke; zero taskbar crashes across a 4-hour soak test with hotplug events.
- MUST: mixed-DPI multi-monitor renders correctly on both displays simultaneously, tested on real hardware.
- MUST: dock/undock applies the saved arrangement within 3 seconds, zero manual reconfiguration.
- MUST NOT: require logout/re-login to apply a resolution or arrangement change.

---

## PART VIII — MEDIA & DAILY-USE APPS

Music player (library-based, MP3/FLAC/AAC out of the box, no `gst-plugins-ugly` hunting), MPV-based video player with hardware-accelerated decode wired to Part III's driver stack, a first-party Personalization hub (dynamic wallpapers, cross-toolkit accent-color theming — GTK/Qt consistency is engineered, not assumed), LibreOffice + OnlyOffice, a Chromium/Firefox default browser, screenshot/screen-record, PDF viewer/annotator, calculator, calendar, email client, and a unified pacman+AUR+Flatpak Software Center.

**Strict acceptance bar:**
- MUST: full common codec set (MP3, FLAC, AAC, H.264, H.265, VP9, WebM, MKV) with zero post-boot codec installs.
- MUST: accent-color/theme changes apply consistently across GTK and Qt apps in the same session.
- MUST: Software Center search-to-install for a common package in under 5 clicks, no terminal, verified in usability testing.
- MUST NOT: crash on a corrupted/unsupported file — always a clear error.

---

## PART IX — ACCESSIBILITY, SECURITY & ENTERPRISE BASICS

Screen reader, high-contrast mode, magnifier at GNOME/Zorin parity. Firewall GUI (`ufw` front-end) on by default; automatic security-update channel separate from the rolling package channel so patches don't wait on a full system update. VPN client GUI (OpenVPN/WireGuard), domain/AD-adjacent auth where feasible, LUKS disk encryption offered by default at install. Bluetooth/Wi-Fi tuned out of the box, printer/scanner via CUPS auto-discovery. Battery/suspend-resume reliability treated as a hard requirement, tested on every supported vendor platform. Telemetry/crash reporting **opt-in only**, clearly disclosed.

---

## PART X — COMPLIANCE MAPPING (APPLICABLE INTERNATIONAL STANDARDS)

Grouped by category. Each entry states how the OS meets it and is tagged for release-blocking strictness. This list is scoped to standards that genuinely apply to a desktop OS — not padded with unrelated ISO standards to inflate the count.

### Security
| Standard | How it's met | Tag |
|---|---|---|
| ISO/IEC 27001 | Audit logging, access controls, disk encryption at rest, documented ISMS practices for the project itself | SHOULD |
| ISO/IEC 15408 (Common Criteria) | Formal security target doc for the DAC/MAC/firewall model; targeting practical EAL-equivalent rigor, not formal certification (certification is costly and typically pursued only if enterprise/government customers require it) | MAY |
| NIST SP 800-53 / SP 800-171 | Control-family mapping (AC, AU, IA, SC, SI) documented for the default hardened profile, relevant to any enterprise/government deployment | SHOULD |
| FIPS 140-3 | Optional "FIPS mode" toggle switching to FIPS-validated crypto modules (OpenSSL FIPS provider) for regulated environments; **not** default, since it restricts algorithm choice | SHOULD |
| NIST SP 800-63 / FIDO2 / WebAuthn | Login supports FIDO2/WebAuthn hardware keys and TOTP as a second factor, per current NIST digital-identity guidance | MUST |
| CVE / NVD compatibility | Security-update channel tracks CVEs against shipped package versions with a public advisory feed | MUST |
| ISO/IEC 29147 / 30111 | Documented, public vulnerability disclosure and handling process | SHOULD |

### Privacy
| Standard | How it's met | Tag |
|---|---|---|
| GDPR (EU) | No telemetry by default (opt-in only, per Part IX); user-facing data export/deletion tools for any first-party app that stores personal data | MUST |
| ISO/IEC 27701 | Privacy-information-management practices documented alongside the 27001 mapping | MAY |

### Accessibility
| Standard | How it's met | Tag |
|---|---|---|
| WCAG 2.2 AA | All first-party GUI apps: 4.5:1 minimum contrast, full keyboard nav, screen-reader labels (Part II) | MUST |
| ISO 9241 (ergonomics of human-system interaction) | Design-system doc (Part II) follows ISO 9241-110 dialogue principles (suitability for the task, self-descriptiveness, controllability) | SHOULD |
| EN 301 549 (EU) / Section 508 (US) | Accessibility conformance statement published per release, mapped from the WCAG 2.2 AA testing above | SHOULD |

### Quality & Process
| Standard | How it's met | Tag |
|---|---|---|
| ISO/IEC 25010 | Quality model tracked explicitly: reliability (Btrfs journaling/snapshot), security (Part IX), usability (Part II), performance (benchmarks in Part XI) | MUST |
| ISO/IEC 12207 | Software lifecycle process (the Phase structure in Part XII) documented against this reference model | MAY |
| ISO 9001 | Project-level process discipline (release checklist, defined roles) — not pursued as a formal certification, since that's an organizational cert, not an OS feature | MAY |

### Interoperability & Filesystem Standards
| Standard | How it's met | Tag |
|---|---|---|
| POSIX.1-2017 | Inherited from the Linux kernel + glibc — this is one of the practical advantages of staying Arch-based rather than from-scratch | MUST |
| FHS 3.0 (Filesystem Hierarchy Standard) | Default install layout conforms; installer and packages enforce standard paths | MUST |
| LSB (Linux Standard Base) | LSB is formally discontinued (retired ~2015) — noted here for accuracy rather than claimed as "met"; ELF64 ABI and standard packaging conventions are followed regardless | N/A (historical) |
| UEFI Specification | Installer targets UEFI as primary boot path, BIOS/CSM as documented legacy fallback (Part I) | MUST |
| ACPI Specification | Standard kernel ACPI support (power states, thermal, battery) — inherited from upstream Linux | MUST |

### Networking (IETF/IEEE)
| Standard | How it's met | Tag |
|---|---|---|
| RFC 791/8200 (IPv4/IPv6), RFC 2131 (DHCP), RFC 1035 (DNS), RFC 8446 (TLS 1.3) | Inherited from the Linux kernel network stack and system libraries — again a practical benefit of the Arch-based approach vs. writing a stack from scratch | MUST |
| IEEE 802.11 (Wi-Fi), IEEE 802.3 (Ethernet) | Driver support inherited from upstream kernel + `iwd`/NetworkManager | MUST |
| PCI-DSS v4.0 | Relevant only if the OS is deployed in a payment-processing context; TLS 1.3–only option, audit logs, and MFA support (above) give deployers what they'd need, not a claim the OS itself is "PCI compliant" (that's a deployment-level certification) | MAY |

### Internationalization
| Standard | How it's met | Tag |
|---|---|---|
| Unicode / ISO/IEC 10646 | Full UTF-8 default locale, Unicode-aware text rendering and input methods (ibus) | MUST |
| Unicode Bidirectional Algorithm (UAX #9) | Inherited from the text-rendering stack (HarfBuzz/Pango) for RTL language support | MUST |
| ISO 8601 | Date/time formatting in system settings and first-party apps follows ISO 8601 as a selectable format, alongside locale-specific defaults | SHOULD |

**Honest framing, restated:** several rows above are marked MAY or N/A on purpose — claiming formal certification (Common Criteria EAL, ISO 9001, PCI-DSS) for an OS project is either not applicable at the OS layer or requires a paid, external audit process most open-source distro projects never pursue (Ubuntu and RHEL are the rare exceptions, and even they scope it to specific certified builds/versions). Listing a standard as "met" without that caveat would be a spec defect under Part 0's own rules.

---

## PART XI — TESTING FRAMEWORK

Adapted for an Arch-based distro (not a from-scratch kernel), but the same rigor:

1. **Package/config unit tests** — every first-party app and packaging script has an automated test; run in CI on every commit.
2. **ISO integration tests (QEMU)** — every ISO build boots headless in QEMU; scripted checks confirm: boot completes, network comes up, filesystem mounts, display manager reaches login. Run before any ISO is published.
3. **Hardware-in-the-loop tests** — the driver matrix from Part III (Intel/AMD/Nvidia/Qualcomm) and the hypervisor matrix from Part V are re-run on **real reference hardware**, not just QEMU, since GPU/driver/Secure Boot bugs frequently don't reproduce in a VM.
4. **Accessibility conformance tests** — automated WCAG 2.2 AA contrast/keyboard-nav checks plus a manual screen-reader pass per release.
5. **Security tests** — firewall default-deny verification, Secure Boot chain validation, privilege-escalation attempts (must fail), FIDO2/TOTP login flow tests.
6. **Performance benchmarks** — boot time (power-on to login), app launch latency, filesystem throughput (sequential + random), network throughput, suspend/resume time — tracked release-over-release so regressions are caught, not just felt.

**Strict acceptance bar:**
- MUST: no ISO is published unless every automated integration test and the full driver/hypervisor hardware matrix passes.
- MUST: any MUST-tagged item from Parts I–X that regresses blocks the release, per the Part 0 definition — there is no "ship now, patch later" for a MUST.

---

## PART XII — BUILD PHASES

1. **Phase 0 — Foundation:** base Arch image, kernel choices, Btrfs+snapshot pipeline, Calamares installer skeleton
2. **Phase 1 — Desktop Shell:** DE selection, taskbar/layout-switcher, design system, first-party theme
3. **Phase 2 — Driver Subsystem:** Intel/AMD baseline, Nvidia auto-detect/DKMS/Secure Boot, Driver Manager GUI, scoped Qualcomm ARM64 spin
4. **Phase 3 — Compatibility Layer:** Wine/Bottles, Proton/Steam, "Run with Windows Compatibility," ARM Winlator path
5. **Phase 3a — Virtualization:** QEMU/KVM + VM Manager GUI, VMware DKMS shim, VirtualBox DKMS + Secure Boot signing, Virtualization Status panel, GPU-passthrough template
6. **Phase 4 — Apps & Personalization:** music/video players, personalization hub, office suite, software center
7. **Phase 5 — Compliance & Accessibility:** WCAG conformance pass, security-control mapping (Part X), accessibility conformance statement
8. **Phase 6 — Polish & QA:** full testing framework (Part XI) executed end-to-end, public beta

---

## PART XIII — OPEN RISKS

- Nvidia + Wayland + Secure Boot remains the most fragile three-way intersection on Linux — budget disproportionate QA time here.
- Qualcomm/Snapdragon X Elite Linux support is a moving, occasionally-regressing target industry-wide (TUXEDO's cancellation is the cautionary example) — keep the ARM spin scoped conservatively and communicate per-device support tiers honestly.
- Cross-toolkit (GTK/Qt) visual consistency is a chronic Linux weak point that directly undermines "looks professional" — needs a dedicated owner, not a one-time skin.
- VMware/VirtualBox proprietary kernel modules are a permanent maintenance burden against a rolling kernel, not a one-time integration.
- Multi-hypervisor coexistence (KVM + VirtualBox + VMware together) must be tested in combination, not individually, or the "supports all three" claim is false in practice.
- Formal compliance certification (Common Criteria, ISO 9001, PCI-DSS) is explicitly out of scope for v1 per Part X — don't let release messaging overstate this later.

---

## PART XIV — DEFINITION OF "DONE"

A release candidate is not promoted to stable unless every MUST-tagged bar across Parts I–XI passes on the full reference hardware matrix (Intel/AMD/Nvidia desktop + laptop, one hybrid-Optimus laptop, and the scoped Qualcomm ARM64 device list). A single failing MUST is a release blocker by definition — there is no exception. SHOULD items may ship with a public tracking issue and a committed timeline; MAY items are backlog only and never referenced in release messaging as if shipped.

*(Since this is currently a personal experiment rather than a shipping target, treat Part XIV as the long-term bar, not a gate on your day-one progress — Part XV below is the actual starting point.)*

---

## PART XV — GETTING STARTED (PERSONAL BUILD ENVIRONMENT)

Since this is an experiment rather than a release target, skip Parts X/XIV's release-gate bureaucracy for now and start here. The goal for a first working build is small: **a custom `archiso` that boots into your themed desktop with the taskbar/layout switcher working.** Everything else in this doc is the long-term target, not the first milestone.

**Toolchain you actually need on day one:**
- `archiso` — the official Arch tool for building custom bootable ISOs; this is the foundation everything else sits on
- A `releng` profile copy (`/usr/share/archiso/configs/releng/`) as your starting point — don't build the ISO config from scratch, fork the official one
- QEMU for the fast inner loop (`scripts/run-qemu.sh`, which auto-picks the newest ISO under `out/` and uses KVM/OVMF when available) — boots your ISO in seconds instead of burning a USB every test
- A real machine (or at least a spare partition) for the Nvidia/driver-specific testing once you're past the basic desktop stage, since GPU driver bugs routinely don't reproduce in QEMU

**Suggested first milestones, in order:**
1. `archiso` builds and boots to a plain Arch live session in QEMU — confirms your build pipeline works at all
2. Swap in your chosen DE (GNOME or KDE) + your theme package into the `releng` profile — confirms packaging/theming works
3. Get the taskbar/layout-switcher extension loading correctly on boot — confirms the UX layer you actually care about
4. Wire in the Calamares installer config — confirms install-to-disk works, not just live-boot
5. Only after 1–4 are solid: start on Part III (drivers) and Part V (virtualization), since those need real/varied hardware to test properly and will otherwise stall the whole experiment

**Reference projects worth reading the source of, not reinventing:**
- **EndeavourOS** — cleanest example of a minimal-changes Calamares + Arch install pipeline
- **CachyOS** — best current reference for kernel/driver tuning choices (their `linux-cachyos` kernel packaging is a good model for the zen/lts split in Part I)
- **Garuda Linux** — good reference for aggressive out-of-the-box theming/personalization done coherently across GTK+Qt, relevant to Part VIII's cross-toolkit theming problem
- **Zorin OS** (if you can find their public docs/blog posts, source itself isn't fully open) — the actual UX benchmark this whole project is chasing in Part II

---

## PART XVI — GLOSSARY

- **AUR** — Arch User Repository, community package repo layered on top of official Arch packages
- **DKMS** — Dynamic Kernel Module Support; rebuilds out-of-tree kernel modules (Nvidia, VirtualBox, VMware) automatically on kernel updates
- **VFIO** — kernel framework enabling GPU/device passthrough into a VM
- **HCL** — Hardware Compatibility List (Part III)
- **IOMMU** — hardware feature required for safe device passthrough to VMs
- **sbctl** — tool for managing Secure Boot keys and auto-signing kernel modules/bootloaders on Arch
- **Optimus/hybrid graphics** — laptop setups with both an integrated (Intel/AMD) and discrete (Nvidia) GPU, requiring a switcher
- **VA-API** — Video Acceleration API, used for hardware video decode/encode on Linux


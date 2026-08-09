#!/usr/bin/env bash
# Executed by mkarchiso inside the airootfs chroot, after packages from
# packages.x86_64 are installed and the airootfs/ overlay is copied in,
# but before the squashfs is created. mkarchiso deletes this script from
# the final image automatically -- it never ships to users.
#
# Static config (units to *disable*, files to remove, permissions) belongs
# in the airootfs/ overlay tree instead. This script is for the things
# that genuinely need a real chroot: useradd, systemctl enable/disable
# (so package presets are respected), glib-compile-schemas, and fetching
# the two GNOME Shell extensions that give us the Windows-style taskbar +
# start menu from Part II of the plan.

set -euo pipefail

# --- TLS-intercepting proxy trust (only relevant behind one, e.g. a dev
# sandbox) -------------------------------------------------------------------
# This chroot is a separate filesystem from the outer build container, so
# trusting a proxy's CA out there (see scripts/build-iso.sh) doesn't reach
# in here. If a CA bundle was staged at this path, trust it before the git
# clones below need real internet; on an unrestricted machine this file
# never exists and the block is a no-op.
if [ -f /etc/ca-bundle-proxy.crt ]; then
	cp /etc/ca-bundle-proxy.crt /etc/ca-certificates/trust-source/anchors/proxy-ca.crt
	update-ca-trust extract
fi

# --- installer config -------------------------------------------------------
# Our Calamares config is staged at /root/calamares-config instead of
# living directly at /etc/calamares in the airootfs overlay, because
# mkarchiso copies the overlay *before* installing packages.x86_64 --
# and the calamares package (pulled from the CachyOS bootstrap repo, see
# pacman.conf) depends on cachyos-calamares, which ships its own default
# files at /etc/calamares/modules/*.conf. If ours were already sitting
# there, that package install fails outright (pacman refuses to clobber
# unowned files). Applying ours here, after packages are installed,
# means we overwrite CachyOS's branding with our own instead.
rm -rf /etc/calamares
mkdir -p /etc/calamares
cp -a /root/calamares-config/. /etc/calamares/
rm -rf /root/calamares-config

# --- live/default desktop user -------------------------------------------
# GDM autologins as this account for the live session only. This account,
# its NOPASSWD sudo, and this GDM autologin config all get stripped from
# the installed system by Calamares' shellprocess_remove_live_user.conf
# (see calamares-config/modules) -- unpackfs copies the live rootfs
# verbatim, so without that step an installed system would keep a
# passwordless local account and live-session autologin.
useradd -m -G wheel,video,input,storage,optical,scanner,lp -s /usr/bin/zsh liveuser
passwd -d liveuser
mkdir -p /etc/sudoers.d
echo 'liveuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-liveuser
chmod 0440 /etc/sudoers.d/10-liveuser

mkdir -p /etc/gdm
cat > /etc/gdm/custom.conf <<'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=liveuser
WaylandEnable=true
EOF

# --- services --------------------------------------------------------------
systemctl enable NetworkManager.service
systemctl enable gdm.service
systemctl enable bluetooth.service || true
systemctl set-default graphical.target

# --- taskbar + start menu extensions (Part II) ------------------------------
# Vendored from upstream at ISO-build time (this step needs real internet,
# which the archiso build host has even when this dev sandbox doesn't).
# Each project ships its own `make install DESTDIR=` target that does the
# right thing (dash-to-panel moves its schema to the global schema dir;
# arcmenu keeps its schema inside its own extension dir) -- that's more
# correct than hand-copying files ourselves.
SHELL_MAJOR="$(gnome-shell --version | grep -oP '\d+' | head -1)"

install_extension() {
	local repo_url="$1" ref="$2"
	local clone_dir
	clone_dir="/tmp/$(basename "$repo_url" .git)"
	if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
		# Pinned to an exact commit (used where upstream doesn't cut
		# version tags -- see dash-to-dock below) rather than a tag:
		# `--branch` only accepts ref names, not bare commit SHAs, so
		# fetch the specific commit directly instead (GitHub's smart HTTP
		# transport supports this for public repos).
		mkdir -p "$clone_dir"
		git -C "$clone_dir" init -q
		git -C "$clone_dir" fetch --depth 1 "$repo_url" "$ref" >&2
		git -C "$clone_dir" checkout -q FETCH_HEAD
	else
		git clone --depth 1 --branch "$ref" "$repo_url" "$clone_dir" >&2
	fi
	local uuid
	uuid="$(grep -oP '"uuid"\s*:\s*"\K[^"]+' "$clone_dir/metadata.json")"
	# ArcMenu (and occasionally others) lags bumping metadata.json's
	# shell-version array behind actual compatibility; GNOME Shell refuses
	# to load an extension whose current major isn't listed. AUR's
	# arcmenu-git PKGBUILD works around this the same way: add the
	# installed shell's major version if it's missing.
	if ! grep -q "\"$SHELL_MAJOR\"" "$clone_dir/metadata.json"; then
		sed -i "s/\"shell-version\": \[/\"shell-version\": [ \"$SHELL_MAJOR\", /" "$clone_dir/metadata.json"
	fi
	# Redirect stdout to stderr: this function's real return value is the
	# `echo "$uuid"` below, captured via command substitution by the
	# caller. Without this redirect, make's own recipe-echo output (e.g.
	# "glib-compile-schemas ./schemas/") gets captured too, silently
	# corrupting the UUID variable with multiple lines of build noise.
	make -C "$clone_dir" install DESTDIR=/ >&2
	# Some extensions' `install` targets return 0 even when a prerequisite
	# recipe failed partway through (observed with dash-to-dock: a missing
	# sassc broke its stylesheet.css build, but the outer `make install`
	# still exited 0 without ever copying files) -- so a clean exit code
	# above isn't proof the extension actually landed. Verify the real
	# destination directly and fail loudly instead of silently shipping a
	# UUID that GNOME Shell won't be able to find at runtime.
	if [ ! -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
		echo "error: install_extension: $repo_url claimed success but /usr/share/gnome-shell/extensions/$uuid doesn't exist" >&2
		exit 1
	fi
	rm -rf "$clone_dir"
	echo "$uuid"
}

DASH_TO_PANEL_UUID="$(install_extension https://github.com/home-sweet-gnome/dash-to-panel.git v73)"
ARCMENU_UUID="$(install_extension https://github.com/jordimas/gnome-shell-extension-arcmenu.git v49-Stable)"
# dash-to-dock: needed for the macOS/Ubuntu/elementary-style desktop
# layouts (Part II layout switcher, /usr/local/bin/uos-layout-switcher),
# which use a dock instead of dash-to-panel's taskbar.
# NOTE: unlike dash-to-panel/arcmenu, dash-to-dock doesn't cut a
# version-specific tag per GNOME Shell release -- "master" is its
# long-standing default branch. Pinned to a specific reviewed commit
# (2026-07-25) rather than tracking master directly: this is root-elevated
# code loaded into the live session's GNOME Shell, and floating a moving
# branch there means a future upstream compromise becomes an unreviewed
# root compromise of every subsequent build. Bump this SHA deliberately,
# not automatically.
DASH_TO_DOCK_UUID="$(install_extension https://github.com/micheleg/dash-to-dock.git 4ceb03ed3976348cbe0db403d847a6e1ef7bedd3)"

glib-compile-schemas /usr/share/glib-2.0/schemas

# Bake the resolved UUIDs into the dconf override so enabled-extensions
# matches whatever these repos actually call themselves, rather than a
# guessed literal string.
install -d /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/01-taskbar-extensions <<EOF
[org/gnome/shell]
enabled-extensions=['${DASH_TO_PANEL_UUID}', '${ARCMENU_UUID}']
EOF

# uos-layout-switcher (see usr/local/bin/) needs these UUIDs at runtime to
# build enabled-extensions lists per layout -- it can't rediscover them
# itself since UUIDs are resolved from upstream metadata.json at build
# time, not something fixed we can hardcode into the script.
install -d /etc/unemployed-os
cat > /etc/unemployed-os/extension-uuids.env <<EOF
DASH_TO_PANEL_UUID='${DASH_TO_PANEL_UUID}'
ARCMENU_UUID='${ARCMENU_UUID}'
DASH_TO_DOCK_UUID='${DASH_TO_DOCK_UUID}'
EOF

# --- branding: version, logo, boot splash (Part II, 1.0 "Severance") -------
# /etc/os-release is a symlink to /usr/lib/os-release shipped by the
# `filesystem` package -- same overlay-copied-before-pacstrap problem as
# /etc/calamares above, so this overwrites the real target file here,
# post-pacstrap, instead of via the airootfs overlay.
cat > /usr/lib/os-release <<'EOF'
NAME="Unemployed OS"
PRETTY_NAME="Unemployed OS 1.0 (Severance)"
ID=unemployedos
ID_LIKE=arch
VERSION="1.0 (Severance)"
VERSION_ID=1.0
BUILD_ID=severance
ANSI_COLOR="38;2;255;122;60"
LOGO=unemployed-os-logo
HOME_URL="https://github.com/amoguslittleahhh/unemployed-os"
DOCUMENTATION_URL="https://github.com/amoguslittleahhh/unemployed-os"
BUG_REPORT_URL="https://github.com/amoguslittleahhh/unemployed-os/issues"
EOF

# Icon theme cache so unemployed-os-logo(-symbolic) resolve immediately
# without a first-login regeneration. gtk-update-icon-cache ships with
# gtk3 (already pulled in by gnome-shell); guard in case that ever
# changes rather than failing the whole build over a cosmetic cache miss.
if command -v gtk-update-icon-cache >/dev/null; then
	gtk-update-icon-cache -f -t /usr/share/icons/hicolor
fi

# plymouth-set-default-theme only rewrites /etc/plymouth/plymouthd.conf --
# it does NOT rebuild the initramfs on its own, and critically, this is
# too late to rely on pacstrap's own mkinitcpio run to pick it up: pacman
# regenerates /boot/initramfs-linux-zen.img automatically via a post-install
# hook the moment the kernel/mkinitcpio/plymouth packages are installed
# (visible in a real build log as "(19/36) Updating linux initcpios..."),
# which happens *before* this script (customize_airootfs.sh) even starts --
# confirmed by boot-testing an ISO built without this fix: it showed
# plymouth's factory-default "bgrt" spinner (Arch Linux logo), not our
# theme, because mkarchiso only *copies* the already-built initramfs into
# the ISO afterward, it never invokes mkinitcpio a second time. So the
# initramfs baked during pacstrap -- using whatever theme was selected
# before this script ran -- is exactly what ships. Explicitly rebuilding
# here, after the theme is actually set, is the fix.
plymouth-set-default-theme unemployed-os
mkinitcpio -P

# GRUB's OEM-style boot logo (the bootloader menu itself, not Plymouth's
# post-kernel splash) -- installed_target-facing since the live medium
# doesn't use GRUB at all (see profiledef.sh bootmodes: bios.syslinux +
# uefi.systemd-boot), only Calamares' grub-install/grub-mkconfig does.
# Same overlay-copied-before-pacstrap conflict as /etc/calamares above:
# the grub package ships its own /etc/default/grub, so ours is staged
# here and applied post-pacstrap instead of living in the overlay.
cp /root/branding-assets/etc-default-grub /etc/default/grub
rm -rf /root/branding-assets

# --- dconf defaults (see /etc/dconf/db/local.d in the overlay, plus the
# extensions file just written above) ----------------------------------------
dconf update

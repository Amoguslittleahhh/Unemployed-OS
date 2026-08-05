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
	git clone --depth 1 --branch "$ref" "$repo_url" "$clone_dir" >&2
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
	rm -rf "$clone_dir"
	echo "$uuid"
}

DASH_TO_PANEL_UUID="$(install_extension https://github.com/home-sweet-gnome/dash-to-panel.git v73)"
ARCMENU_UUID="$(install_extension https://github.com/jordimas/gnome-shell-extension-arcmenu.git v49-Stable)"

glib-compile-schemas /usr/share/glib-2.0/schemas

# Bake the resolved UUIDs into the dconf override so enabled-extensions
# matches whatever these repos actually call themselves, rather than a
# guessed literal string.
install -d /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/01-taskbar-extensions <<EOF
[org/gnome/shell]
enabled-extensions=['${DASH_TO_PANEL_UUID}', '${ARCMENU_UUID}']
EOF

# --- dconf defaults (see /etc/dconf/db/local.d in the overlay, plus the
# extensions file just written above) ----------------------------------------
dconf update

#!/usr/bin/env bash
# Build the Unemployed OS live/install ISO from archiso/.
#
# On a native Arch host with archiso installed, this just runs mkarchiso.
# Everywhere else (including this dev container, which is Ubuntu-based),
# it drives an official `archlinux` Docker image so you don't need an
# Arch machine to build the ISO -- only Docker.
#
# Usage: scripts/build-iso.sh [extra mkarchiso args]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$REPO_ROOT/archiso"
WORK_DIR="$REPO_ROOT/work"
OUT_DIR="$REPO_ROOT/out"

# Pins the *builder image* (bash/pacman/mkarchiso tooling) for reproducible
# runs from the same commit -- this does NOT pin package versions, since
# packages.x86_64 is always resolved against the live Arch repos regardless
# (that's the point of a rolling-release ISO). Update by re-pulling
# archlinux:latest and taking `docker inspect --format='{{index .RepoDigests 0}}'`.
BUILDER_IMAGE="${UOS_BUILDER_IMAGE:-archlinux@sha256:345a872f6c95e082d4b8c050af637eebb57402c6e2177b411c3acf7df84eb33b}"

mkdir -p "$WORK_DIR" "$OUT_DIR"

# UOS_PACMAN_SNAPSHOT_DATE (format YYYY/MM/DD) pins core/extra/multilib to a
# specific Arch Linux Archive date instead of whatever the live mirrors
# resolve to right now, so two builds from the same commit + same snapshot
# date get the same package versions -- the piece the digest-pinned builder
# image alone can't cover (that only pins the bash/pacman/mkarchiso
# tooling, not what packages.x86_64 resolves to). Doesn't cover the
# [cachyos] bootstrap repo (see the "Known gaps" section in README.md for
# that one -- it's unsigned upstream, a snapshot date doesn't fix that).
# Unset (the default) keeps today's rolling-release behavior.
if [ -n "${UOS_PACMAN_SNAPSHOT_DATE:-}" ]; then
	if [[ ! "$UOS_PACMAN_SNAPSHOT_DATE" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]]; then
		echo "error: UOS_PACMAN_SNAPSHOT_DATE must use YYYY/MM/DD (got '$UOS_PACMAN_SNAPSHOT_DATE')." >&2
		exit 1
	fi
	# The regex above only checks the shape -- 2026/02/31 matches it fine
	# despite not being a real day. Round-tripping through `date` catches
	# calendar-invalid dates too: GNU date normalizes an invalid day/month
	# combination (rather than erroring), so a mismatch after round-trip
	# means the input wasn't a real date.
	normalized_snapshot="$(date -u -d "${UOS_PACMAN_SNAPSHOT_DATE//\//-}" +%Y/%m/%d 2>/dev/null || true)"
	if [ "$normalized_snapshot" != "$UOS_PACMAN_SNAPSHOT_DATE" ]; then
		echo "error: UOS_PACMAN_SNAPSHOT_DATE is not a valid calendar date (got '$UOS_PACMAN_SNAPSHOT_DATE')." >&2
		exit 1
	fi
	SNAPSHOT_PROFILE_DIR="$WORK_DIR/pacman-snapshot-profile"
	rm -rf "$SNAPSHOT_PROFILE_DIR"
	cp -a "$PROFILE_DIR" "$SNAPSHOT_PROFILE_DIR"
	sed -i \
		-e "s#^Include = /etc/pacman.d/mirrorlist#Server = https://archive.archlinux.org/repo/${UOS_PACMAN_SNAPSHOT_DATE}/\$repo/os/\$arch#" \
		"$SNAPSHOT_PROFILE_DIR/pacman.conf"
	if ! grep -q "^Server = https://archive.archlinux.org/repo/${UOS_PACMAN_SNAPSHOT_DATE}/" "$SNAPSHOT_PROFILE_DIR/pacman.conf"; then
		echo "error: failed to pin pacman.conf to the Arch Linux Archive snapshot -- the expected 'Include = /etc/pacman.d/mirrorlist' line wasn't found to replace." >&2
		exit 1
	fi
	echo "==> Pinning core/extra/multilib to Arch Linux Archive snapshot $UOS_PACMAN_SNAPSHOT_DATE"
	PROFILE_DIR="$SNAPSHOT_PROFILE_DIR"
fi
# In-container path for the Docker branch below -- mirrors PROFILE_DIR but
# rooted at /repo (the container's bind-mount of $REPO_ROOT) instead of the
# host path, since PROFILE_DIR may now point under $WORK_DIR.
CONTAINER_PROFILE_DIR="/repo/${PROFILE_DIR#"$REPO_ROOT"/}"

if command -v mkarchiso >/dev/null 2>&1; then
	if [ "$(id -u)" -eq 0 ]; then
		echo "==> Native mkarchiso found, running as root."
		mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$@" "$PROFILE_DIR"
	elif command -v sudo >/dev/null 2>&1; then
		echo "==> Native mkarchiso found, building directly (needs root)."
		# --preserve-env keeps SOURCE_DATE_EPOCH (if set) flowing through to
		# mkarchiso, so profiledef.sh's iso_label/iso_version match what the
		# Docker path below would produce for the same commit.
		sudo --preserve-env=SOURCE_DATE_EPOCH mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$@" "$PROFILE_DIR"
	else
		echo "error: mkarchiso needs root, and neither running as root nor sudo is available." >&2
		exit 1
	fi
elif command -v docker >/dev/null 2>&1; then
	echo "==> No native archiso; building inside a pinned archlinux Docker container ($BUILDER_IMAGE)."
	# Behind an egress proxy that re-terminates TLS (e.g. this dev sandbox),
	# containers need --network host to reach a proxy bound to 127.0.0.1,
	# and need the proxy's CA imported before pacman will trust it. Both are
	# no-ops (env unset, files absent) on an unrestricted machine.
	DOCKER_NET_ARGS=()
	DOCKER_ENV_ARGS=()
	DOCKER_MOUNT_ARGS=()
	PRE_PACMAN_CMD=":"
	if [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ]; then
		# Strip any embedded userinfo (user:pass@) before the proxy URL goes
		# into the container: customize_airootfs.sh clones and runs
		# arbitrary upstream Makefiles inside there, so a credentialed
		# proxy URL shouldn't be handed to code we don't control the
		# provenance of. host:port is enough for the container to route
		# through the same proxy; credentials, if any, stay out here.
		proxy_url="${HTTPS_PROXY:-$https_proxy}"
		proxy_no_creds="$(printf '%s' "$proxy_url" | sed -E 's#^(https?://)[^@/]*@#\1#')"
		DOCKER_ENV_ARGS=(-e "HTTPS_PROXY=$proxy_no_creds" -e "https_proxy=$proxy_no_creds")
		# --network host is only needed (and only safe) when the proxy is
		# bound to this host's own loopback interface -- that's the only
		# case where the container's normal bridge network can't already
		# reach it. Sharing the host's network namespace is a much bigger
		# blast radius than this build needs for any other proxy target, so
		# only opt into it for that one case.
		# Strip scheme and path/query, but keep the whole host[:port] --
		# truncating at the first colon (as a naive `s#[:/].*##` would)
		# mangles a bracketed IPv6 host like [::1]:3128 down to just "[",
		# silently missing the --network host case for a proxy bound to
		# IPv6 loopback.
		proxy_host="$(printf '%s' "$proxy_no_creds" | sed -E 's#^https?://##; s#/.*$##')"
		case "$proxy_host" in
			localhost|localhost:*|127.0.0.1|127.0.0.1:*|::1|\[::1\]|\[::1\]:*)
				DOCKER_NET_ARGS=(--network host)
				;;
		esac
		if [ -f /root/.ccr/ca-bundle.crt ]; then
			DOCKER_MOUNT_ARGS=(-v /root/.ccr/ca-bundle.crt:/etc/ca-bundle.crt:ro)
			PRE_PACMAN_CMD="cp /etc/ca-bundle.crt /etc/ca-certificates/trust-source/anchors/proxy-ca.crt && update-ca-trust extract"
		fi
	fi
	if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
		DOCKER_ENV_ARGS+=(-e "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}")
	fi
	# Extra args are forwarded as real positional parameters ("$@" inside
	# the inner script, via the "bash ... bash "$@"" pattern below) rather
	# than interpolated into the -c string -- interpolating them directly
	# would let a caller-supplied argument break out of the intended
	# mkarchiso invocation.
	#
	# --privileged is required: mkarchiso needs loopback/squashfs mount
	# capabilities an unprivileged container can't get. That does mean
	# customize_airootfs.sh and any other repo-tree hook effectively runs
	# with host-level capabilities -- only run this against a tree you
	# trust, same as running any other build script as root.
		# This is a real structural limitation, not something a --cap-add
		# allowlist safely closes (mkarchiso's actual mount/loopback needs
		# weren't re-verified against a reduced capability set here, and
		# getting that wrong silently breaks every build) -- see Unemployed
		# OS issue #7. What this script *can* do safely is stop and make a
		# human confirm before running privileged in an interactive session;
		# non-interactive runs (no TTY, e.g. CI) skip the prompt but still
		# print the warning.
		if [ -t 0 ] && [ -z "${UOS_SKIP_PRIVILEGED_CONFIRM:-}" ]; then
			echo "==> About to run 'docker run --privileged' against $REPO_ROOT." >&2
			echo "    Every hook in that tree (customize_airootfs.sh, etc.) runs with" >&2
			echo "    host-level container capabilities. Only continue if you trust it." >&2
			read -r -p "    Continue? [y/N] " confirm
			case "$confirm" in
				y|Y|yes|YES) ;;
				*) echo "Aborted." >&2; exit 1 ;;
			esac
		else
			echo "==> Running 'docker run --privileged' against $REPO_ROOT (non-interactive; set UOS_SKIP_PRIVILEGED_CONFIRM=1 to silence this note)." >&2
		fi
	docker run --rm --privileged \
		"${DOCKER_NET_ARGS[@]}" "${DOCKER_ENV_ARGS[@]}" "${DOCKER_MOUNT_ARGS[@]}" \
		-v "$REPO_ROOT:/repo" \
		-w /repo \
		"$BUILDER_IMAGE" \
		bash -c "
			set -euo pipefail
			$PRE_PACMAN_CMD
			pacman -Syu --noconfirm archiso
			mkarchiso -v -w /repo/work -o /repo/out \"\$@\" \"$CONTAINER_PROFILE_DIR\"
		" bash "$@"
else
	echo "error: need either mkarchiso (native Arch host) or docker installed." >&2
	exit 1
fi

echo "==> Build complete. ISO(s) in $OUT_DIR"
ls -lh "$OUT_DIR"

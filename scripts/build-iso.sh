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

if command -v mkarchiso >/dev/null 2>&1; then
	if [ "$(id -u)" -eq 0 ]; then
		echo "==> Native mkarchiso found, running as root."
		mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" "$@"
	elif command -v sudo >/dev/null 2>&1; then
		echo "==> Native mkarchiso found, building directly (needs root)."
		# --preserve-env keeps SOURCE_DATE_EPOCH (if set) flowing through to
		# mkarchiso, so profiledef.sh's iso_label/iso_version match what the
		# Docker path below would produce for the same commit.
		sudo --preserve-env=SOURCE_DATE_EPOCH mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" "$@"
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
		DOCKER_NET_ARGS=(--network host)
		# Strip any embedded userinfo (user:pass@) before the proxy URL goes
		# into the container: customize_airootfs.sh clones and runs
		# arbitrary upstream Makefiles inside there, so a credentialed
		# proxy URL shouldn't be handed to code we don't control the
		# provenance of. host:port is enough for the container to route
		# through the same proxy; credentials, if any, stay out here.
		proxy_url="${HTTPS_PROXY:-$https_proxy}"
		proxy_no_creds="$(printf '%s' "$proxy_url" | sed -E 's#^(https?://)[^@/]*@#\1#')"
		DOCKER_ENV_ARGS=(-e "HTTPS_PROXY=$proxy_no_creds" -e "https_proxy=$proxy_no_creds")
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
	docker run --rm --privileged \
		"${DOCKER_NET_ARGS[@]}" "${DOCKER_ENV_ARGS[@]}" "${DOCKER_MOUNT_ARGS[@]}" \
		-v "$REPO_ROOT:/repo" \
		-w /repo \
		"$BUILDER_IMAGE" \
		bash -c "
			set -euo pipefail
			$PRE_PACMAN_CMD
			pacman -Syu --noconfirm archiso
			mkarchiso -v -w /repo/work -o /repo/out /repo/archiso \"\$@\"
		" bash "$@"
else
	echo "error: need either mkarchiso (native Arch host) or docker installed." >&2
	exit 1
fi

echo "==> Build complete. ISO(s) in $OUT_DIR"
ls -lh "$OUT_DIR"

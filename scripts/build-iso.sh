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

mkdir -p "$WORK_DIR" "$OUT_DIR"

if command -v mkarchiso >/dev/null 2>&1; then
	if [ "$(id -u)" -eq 0 ]; then
		echo "==> Native mkarchiso found, running as root."
		mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" "$@"
	elif command -v sudo >/dev/null 2>&1; then
		echo "==> Native mkarchiso found, building directly (needs root)."
		sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" "$@"
	else
		echo "error: mkarchiso needs root, and neither running as root nor sudo is available." >&2
		exit 1
	fi
elif command -v docker >/dev/null 2>&1; then
	echo "==> No native archiso; building inside an archlinux:latest Docker container."
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
		DOCKER_ENV_ARGS=(-e "HTTPS_PROXY=${HTTPS_PROXY:-$https_proxy}" -e "https_proxy=${HTTPS_PROXY:-$https_proxy}")
		if [ -f /root/.ccr/ca-bundle.crt ]; then
			DOCKER_MOUNT_ARGS=(-v /root/.ccr/ca-bundle.crt:/etc/ca-bundle.crt:ro)
			PRE_PACMAN_CMD="cp /etc/ca-bundle.crt /etc/ca-certificates/trust-source/anchors/proxy-ca.crt && update-ca-trust extract"
		fi
	fi
	# Extra args are forwarded as real positional parameters ("$@" inside
	# the inner script, via the "bash ... bash "$@"" pattern below) rather
	# than interpolated into the -c string -- interpolating them directly
	# would let a caller-supplied argument break out of the intended
	# mkarchiso invocation.
	docker run --rm --privileged \
		"${DOCKER_NET_ARGS[@]}" "${DOCKER_ENV_ARGS[@]}" "${DOCKER_MOUNT_ARGS[@]}" \
		-v "$REPO_ROOT:/repo" \
		-w /repo \
		archlinux:latest \
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

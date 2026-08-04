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
	echo "==> Native mkarchiso found, building directly (needs root)."
	sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" "$@"
elif command -v docker >/dev/null 2>&1; then
	echo "==> No native archiso; building inside an archlinux:latest Docker container."
	docker run --rm --privileged \
		-v "$REPO_ROOT:/repo" \
		-w /repo \
		archlinux:latest \
		bash -c "
			set -euo pipefail
			pacman -Sy --noconfirm archiso
			mkarchiso -v -w /repo/work -o /repo/out /repo/archiso $*
		"
else
	echo "error: need either mkarchiso (native Arch host) or docker installed." >&2
	exit 1
fi

echo "==> Build complete. ISO(s) in $OUT_DIR"
ls -lh "$OUT_DIR"

#!/usr/bin/env bash
# Boot the most recently built Unemployed OS ISO in QEMU for a fast
# inner-loop test, per PART XV of the build plan.
#
# Usage: scripts/run-qemu.sh [path/to/iso]
# If no ISO path is given, the newest *.iso under out/ is used.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

ISO="${1:-}"
if [ -z "$ISO" ]; then
	ISO="$(ls -t "$OUT_DIR"/*.iso 2>/dev/null | head -n1 || true)"
fi
if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
	echo "error: no ISO found. Build one first with scripts/build-iso.sh, or pass a path." >&2
	exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
	echo "error: qemu-system-x86_64 not installed." >&2
	exit 1
fi

KVM_ARGS=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	KVM_ARGS=(-enable-kvm -cpu host)
else
	echo "note: /dev/kvm not available, falling back to TCG (slow) emulation." >&2
fi

# Prefer UEFI firmware (OVMF) so the systemd-boot path gets exercised too,
# same as most real reference hardware. Falls back to BIOS/syslinux if
# OVMF isn't installed.
OVMF_CODE=""
for candidate in \
	/usr/share/OVMF/OVMF_CODE.fd \
	/usr/share/ovmf/OVMF.fd \
	/usr/share/edk2/x64/OVMF_CODE.fd; do
	if [ -f "$candidate" ]; then
		OVMF_CODE="$candidate"
		break
	fi
done

BIOS_ARGS=()
if [ -n "$OVMF_CODE" ]; then
	echo "==> Booting UEFI via $OVMF_CODE"
	BIOS_ARGS=(-bios "$OVMF_CODE")
else
	echo "==> No OVMF firmware found, booting legacy BIOS/syslinux instead."
fi

echo "==> Booting $ISO"
qemu-system-x86_64 \
	"${KVM_ARGS[@]}" \
	"${BIOS_ARGS[@]}" \
	-m 4G \
	-smp 2 \
	-cdrom "$ISO" \
	-boot d \
	-vga virtio \
	-netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
	-serial mon:stdio

#!/usr/bin/env bash
# Fast, no-network sanity checks for the archiso profile and Calamares
# config. This is the "package/config unit tests" item from the plan's
# Part XI testing framework -- it does NOT build or boot the ISO (that's
# a separate, much slower job); it just catches the class of bug that's
# broken every build so far: shell syntax errors, invalid YAML, and
# duplicate/missing package entries.
#
# Usage: scripts/validate.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail=0

echo "==> Bash syntax (bash -n)"
while IFS= read -r -d '' f; do
	if ! bash -n "$f"; then
		echo "SYNTAX ERROR: $f"
		fail=1
	fi
done < <(find archiso scripts -type f \( -name '*.sh' -o -name 'profiledef.sh' -o -name 'customize_airootfs.sh' \) -print0)
echo "   ok"

if command -v shellcheck >/dev/null 2>&1; then
	echo "==> shellcheck"
	while IFS= read -r -d '' f; do
		# SC1091 (can't follow sourced files) is expected -- these scripts
		# run inside a live/chroot environment this check doesn't have.
		if ! shellcheck -e SC1091 "$f"; then
			fail=1
		fi
	done < <(find archiso scripts -type f \( -name '*.sh' -o -name 'profiledef.sh' -o -name 'customize_airootfs.sh' \) -print0)
else
	echo "==> shellcheck not installed, skipping"
fi

echo "==> Calamares module YAML"
python3 - <<'EOF' || fail=1
import glob, sys
import yaml

ok = True
for f in sorted(glob.glob("archiso/airootfs/root/calamares-config/**/*.conf", recursive=True)):
    try:
        list(yaml.safe_load_all(open(f).read()))
    except Exception as e:
        print(f"YAML ERROR: {f}: {e}")
        ok = False
sys.exit(0 if ok else 1)
EOF
echo "   ok"

echo "==> packages.x86_64 duplicates"
dupes="$(sort archiso/packages.x86_64 | grep -v '^#\|^$' | uniq -d || true)"
if [ -n "$dupes" ]; then
	echo "DUPLICATE PACKAGE ENTRIES:"
	echo "$dupes"
	fail=1
else
	echo "   ok"
fi

echo "==> profiledef.sh required fields"
required_vars=(iso_name iso_label iso_publisher iso_application iso_version install_dir arch buildmodes bootmodes)
profiledef_content="$(cat archiso/profiledef.sh)"
for var in "${required_vars[@]}"; do
	if ! grep -q "^${var}=" <<<"$profiledef_content"; then
		echo "MISSING profiledef.sh field: $var"
		fail=1
	fi
done
echo "   ok"

if [ "$fail" -ne 0 ]; then
	echo
	echo "==> validate.sh FAILED"
	exit 1
fi

echo
echo "==> validate.sh passed"

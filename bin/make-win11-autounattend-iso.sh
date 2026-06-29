#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/answer_files/11_pro_uefi"
OUT="$ROOT/iso/win11-autounattend.iso"

mkdir -p "$(dirname "$OUT")"
# libvirt may chown attached media to libvirt-qemu; unlink and recreate instead of overwriting.
rm -f "$OUT"

if ! command -v xorriso >/dev/null 2>&1; then
  echo "xorriso is required (Arch package: libisoburn)." >&2
  exit 1
fi

python - <<'PY' "$SRC/Autounattend.xml"
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY

xorriso -as mkisofs \
  -iso-level 3 \
  -J -joliet-long \
  -r \
  -V WIN11AUTO \
  -o "$OUT" \
  "$SRC" >/dev/null

chmod 0644 "$OUT"
echo "$OUT"

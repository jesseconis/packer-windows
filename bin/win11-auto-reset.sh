#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-win11-auto}"
POOL="${POOL:-packer-windows}"
DISK_VOL="${DISK_VOL:-${NAME}.qcow2}"
CONNECT="${CONNECT:-qemu:///system}"

if virsh --connect "$CONNECT" dominfo "$NAME" >/dev/null 2>&1; then
  virsh --connect "$CONNECT" destroy "$NAME" >/dev/null 2>&1 || true
  virsh --connect "$CONNECT" undefine "$NAME" --nvram --tpm >/dev/null 2>&1 || \
    virsh --connect "$CONNECT" undefine "$NAME" --nvram >/dev/null 2>&1 || \
    virsh --connect "$CONNECT" undefine "$NAME" >/dev/null
fi

if virsh --connect "$CONNECT" vol-info --pool "$POOL" "$DISK_VOL" >/dev/null 2>&1; then
  virsh --connect "$CONNECT" vol-delete --pool "$POOL" "$DISK_VOL" >/dev/null
fi

echo "Removed domain '$NAME' and volume '$DISK_VOL' (if they existed)."

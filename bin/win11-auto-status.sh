#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${NAME:-win11-auto}"
CONNECT="${CONNECT:-qemu:///system}"

if ! timeout 10s virsh --connect "$CONNECT" dominfo "$NAME" >/dev/null 2>&1; then
  echo "Domain '$NAME' does not exist on $CONNECT"
  exit 1
fi

echo "== domain =="
timeout 10s virsh --connect "$CONNECT" dominfo "$NAME" | sed -n '1,24p' || true

echo
echo "== display =="
timeout 10s virsh --connect "$CONNECT" domdisplay "$NAME" 2>/dev/null || true

echo
echo "== interface addresses (lease) =="
timeout 5s virsh --connect "$CONNECT" domifaddr "$NAME" --source lease 2>/dev/null || true

echo
echo "== interface addresses (qemu guest agent, available after firstlogon installs virtio tools) =="
timeout 5s virsh --connect "$CONNECT" domifaddr "$NAME" --source agent 2>/dev/null || true

echo
echo "== default network DHCP leases =="
timeout 5s virsh --connect "$CONNECT" net-dhcp-leases default 2>/dev/null || true

echo
echo "To open the desktop: virt-viewer --connect $CONNECT $NAME"
echo "Credentials after setup: vagrant / vagrant"

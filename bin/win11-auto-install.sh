#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${NAME:-win11-auto}"
POOL="${POOL:-packer-windows}"
DISK_VOL="${DISK_VOL:-${NAME}.qcow2}"
DISK_SIZE="${DISK_SIZE:-80G}"
MEMORY_MIB="${MEMORY_MIB:-8192}"
VCPUS="${VCPUS:-4}"
WIN_ISO="${WIN_ISO:-$ROOT/Win11_25H2_English_x64_v2.iso}"
VIRTIO_ISO="${VIRTIO_ISO:-$ROOT/virtio-win.iso}"
UNATTEND_ISO="$ROOT/iso/win11-autounattend.iso"
CONNECT="${CONNECT:-qemu:///system}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}

require virsh
require virt-install
require qemu-system-x86_64

if [[ ! -r "$WIN_ISO" ]]; then
  echo "Windows ISO not found/readable: $WIN_ISO" >&2
  exit 1
fi
if [[ ! -r "$VIRTIO_ISO" ]]; then
  echo "VirtIO ISO not found/readable: $VIRTIO_ISO" >&2
  exit 1
fi

"$ROOT/bin/make-win11-autounattend-iso.sh" >/dev/null

if ! qemu-system-x86_64 -accel kvm -M q35 -nodefaults -display none -serial none -monitor none -S -pidfile /tmp/win11-auto-kvm-test.pid -daemonize 2>/tmp/win11-auto-kvm-test.err; then
  cat /tmp/win11-auto-kvm-test.err >&2 || true
  echo "KVM acceleration failed; refusing to fall back to TCG for Windows 11." >&2
  exit 1
fi
if [[ -s /tmp/win11-auto-kvm-test.pid ]]; then
  kill "$(cat /tmp/win11-auto-kvm-test.pid)" 2>/dev/null || true
  rm -f /tmp/win11-auto-kvm-test.pid
fi

if ! virsh --connect "$CONNECT" pool-info "$POOL" >/dev/null 2>&1; then
  echo "libvirt pool '$POOL' does not exist on $CONNECT" >&2
  echo "Existing pools:" >&2
  virsh --connect "$CONNECT" pool-list --all >&2 || true
  exit 1
fi
virsh --connect "$CONNECT" pool-start "$POOL" >/dev/null 2>&1 || true

created=0
if virsh --connect "$CONNECT" dominfo "$NAME" >/dev/null 2>&1; then
  state="$(virsh --connect "$CONNECT" domstate "$NAME" | tr -d '\r')"
  echo "Domain '$NAME' already exists ($state)."
  if [[ "$state" != "running" ]]; then
    virsh --connect "$CONNECT" start "$NAME"
  fi
else
  created=1
  if ! virsh --connect "$CONNECT" vol-info --pool "$POOL" "$DISK_VOL" >/dev/null 2>&1; then
    virsh --connect "$CONNECT" vol-create-as "$POOL" "$DISK_VOL" "$DISK_SIZE" --format qcow2 >/dev/null
  fi
  DISK_PATH="$(virsh --connect "$CONNECT" vol-path --pool "$POOL" "$DISK_VOL")"

  virt-install --connect "$CONNECT" \
    --name "$NAME" \
    --memory "$MEMORY_MIB" \
    --vcpus "$VCPUS" \
    --cpu host-passthrough \
    --machine q35 \
    --os-variant win11 \
    --virt-type kvm \
    --features smm=on \
    --boot uefi,bootmenu.enable=on \
    --disk "path=$DISK_PATH,format=qcow2,bus=sata,cache=writeback,discard=unmap" \
    --cdrom "$WIN_ISO" \
    --disk "path=$UNATTEND_ISO,device=cdrom,bus=sata,readonly=on" \
    --disk "path=$VIRTIO_ISO,device=cdrom,bus=sata,readonly=on" \
    --network network=default,model=e1000e \
    --graphics spice,listen=127.0.0.1 \
    --video qxl \
    --sound ich9 \
    --channel spicevmc \
    --channel type=unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --check path_in_use=off \
    --noautoconsole
fi

# Catch the initial Windows ISO "Press any key to boot from CD/DVD" prompt.
# This is sent once, only for freshly-created domains, so it cannot accidentally
# press Setup buttons after Windows has started or on later boots from disk.
if [[ "$created" == "1" && "${SEND_BOOT_ENTER:-1}" == "1" ]]; then
  (
    sleep "${SEND_BOOT_ENTER_DELAY:-2}"
    virsh --connect "$CONNECT" send-key "$NAME" KEY_ENTER >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
fi

echo "Started $NAME. Unattended install is now running under KVM."
echo "Console: virt-viewer --connect $CONNECT $NAME"
echo "Display URI: $(virsh --connect "$CONNECT" domdisplay "$NAME" 2>/dev/null || true)"
echo "Status:  $ROOT/bin/win11-auto-status.sh"
echo "Login after install: vagrant / vagrant"

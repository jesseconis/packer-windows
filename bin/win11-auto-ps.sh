#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-win11-auto}"
CONNECT="${CONNECT:-qemu:///system}"

usage() {
  cat <<'EOF'
Usage:
  bin/win11-auto-ps.sh 'Get-ComputerInfo | select WindowsProductName,OsVersion'
  bin/win11-auto-ps.sh -f ./script.ps1

Runs PowerShell non-interactively inside the win11-auto VM via the QEMU guest
agent. Commands run as LocalSystem, which is ideal for admin/script testing.
Set NAME=... or CONNECT=... to target a different libvirt guest.
EOF
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "-f" || "${1:-}" == "--file" ]]; then
  [[ $# -eq 2 ]] || { usage >&2; exit 2; }
  [[ -r "$2" ]] || { echo "Cannot read script file: $2" >&2; exit 1; }
  SCRIPT="$(cat "$2")"
else
  SCRIPT="$*"
fi

export WIN11_AUTO_NAME="$NAME" WIN11_AUTO_CONNECT="$CONNECT" WIN11_AUTO_SCRIPT="$SCRIPT"
python - <<'PY'
import base64
import json
import os
import subprocess
import sys
import time

name = os.environ['WIN11_AUTO_NAME']
connect = os.environ['WIN11_AUTO_CONNECT']
script = "$ProgressPreference = 'SilentlyContinue';\n" + os.environ['WIN11_AUTO_SCRIPT']
encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')

ps = r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
payload = {
    'execute': 'guest-exec',
    'arguments': {
        'path': ps,
        'arg': ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
        'capture-output': True,
    },
}

def qga(obj, timeout=30):
    raw = subprocess.check_output(
        ['virsh', '--connect', connect, 'qemu-agent-command', name, json.dumps(obj)],
        text=True,
        timeout=timeout,
    )
    return json.loads(raw)['return']

try:
    pid = qga(payload)['pid']
except subprocess.CalledProcessError as exc:
    print(exc, file=sys.stderr)
    sys.exit(exc.returncode or 1)

status = None
for _ in range(3600):
    status = qga({'execute': 'guest-exec-status', 'arguments': {'pid': pid}})
    if status.get('exited'):
        break
    time.sleep(1)
else:
    print('Timed out waiting for guest command to exit', file=sys.stderr)
    sys.exit(124)

for key, stream in [('out-data', sys.stdout), ('err-data', sys.stderr)]:
    data = status.get(key)
    if data:
        stream.write(base64.b64decode(data).decode('utf-8', errors='replace'))
        stream.flush()

sys.exit(int(status.get('exitcode', 1)))
PY

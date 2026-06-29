$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$log = 'C:\Windows\Temp\win11-auto-firstlogon.log'
try { Start-Transcript -Path $log -Append | Out-Null } catch {}

Write-Output "=== win11-auto firstlogon bootstrap started: $(Get-Date -Format o) ==="

try {
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
} catch { Write-Output "Set-ExecutionPolicy failed: $_" }

# Keep the test account predictable and durable.
try {
  & net.exe user vagrant vagrant /active:yes /expires:never
  & net.exe localgroup Administrators vagrant /add
  & wmic.exe useraccount where "name='vagrant'" set PasswordExpires=FALSE
} catch { Write-Output "Account hardening failed: $_" }

# Preserve console/desktop convenience for script and app testing.
try {
  & reg.exe ADD 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v HideFileExt /t REG_DWORD /d 0 /f
  & reg.exe ADD 'HKCU\Console' /v QuickEdit /t REG_DWORD /d 1 /f
  & reg.exe ADD 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoAdminLogon /t REG_SZ /d 1 /f
  & reg.exe ADD 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultUserName /t REG_SZ /d vagrant /f
  & reg.exe ADD 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultPassword /t REG_SZ /d vagrant /f
} catch { Write-Output "Explorer/autologon tweaks failed: $_" }

# No sleeping during long tests.
try {
  & powercfg.exe -h off
  & powercfg.exe -change -monitor-timeout-ac 0
  & powercfg.exe -change -standby-timeout-ac 0
  & powercfg.exe -change -disk-timeout-ac 0
} catch { Write-Output "Power configuration failed: $_" }

# RDP for GUI access from the host/network.
try {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Type DWord -Value 0
  Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
  & netsh.exe advfirewall firewall set rule group='remote desktop' new enable=Yes
} catch { Write-Output "RDP enable failed: $_" }

# WinRM/PowerShell remoting for non-interactive script execution from Linux.
try {
  Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
  Set-Service -Name WinRM -StartupType Automatic
  Start-Service -Name WinRM
  & winrm.exe quickconfig -quiet
  Enable-PSRemoting -Force -SkipNetworkProfileCheck
  Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
  Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
  New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null
  & netsh.exe advfirewall firewall set rule group='Windows Remote Management' new enable=yes
} catch { Write-Output "WinRM enable failed: $_" }

# Make ping and libvirt/qemu-agent based discovery easier.
try {
  & netsh.exe advfirewall firewall add rule name='ICMP Allow incoming V4 echo request' protocol=icmpv4:8,any dir=in action=allow
} catch { Write-Output "ICMP firewall rule failed: $_" }

# If the Fedora virtio-win ISO is attached, install guest tools/qemu-ga/SPICE drivers.
try {
  $virtioRoot = $null
  foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
    if (Test-Path (Join-Path $drive.Root 'virtio-win-guest-tools.exe')) {
      $virtioRoot = $drive.Root
      break
    }
  }
  if ($virtioRoot) {
    $installer = Join-Path $virtioRoot 'virtio-win-guest-tools.exe'
    Write-Output "Installing virtio guest tools from $installer"
    Start-Process -FilePath $installer -ArgumentList '/quiet', '/norestart' -Wait
  } else {
    Write-Output 'virtio-win-guest-tools.exe not found; skipping virtio guest tools.'
  }
} catch { Write-Output "VirtIO guest tools install failed: $_" }

try {
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
    Select-Object -ExpandProperty IPAddress
  $ready = @(
    "win11-auto ready: $(Get-Date -Format o)",
    "user: vagrant",
    "password: vagrant",
    "ipv4: $($ips -join ', ')"
  )
  $ready | Set-Content -Path 'C:\win11-auto-ready.txt' -Encoding ASCII
  $ready | Write-Output
} catch { Write-Output "Ready marker failed: $_" }

Write-Output "=== win11-auto firstlogon bootstrap finished: $(Get-Date -Format o) ==="
try { Stop-Transcript | Out-Null } catch {}

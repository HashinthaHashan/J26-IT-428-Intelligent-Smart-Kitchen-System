<#
.SYNOPSIS
  Starts the KitchenGuard preview backend so REAL ESP32 devices can reach it,
  after checking the usual traps. Run from the repo root:

    .\scripts\dev_stack.ps1               # check, then start the stack
    .\scripts\dev_stack.ps1 -CheckOnly    # only report (safe to run any time)
    .\scripts\dev_stack.ps1 -WithSimulators  # also run the LPG simulator

  By default the LPG simulator is switched OFF so it cannot fight a real
  device over the device_id "lpg01".
#>
param(
  [switch]$CheckOnly,
  [switch]$WithSimulators,                 # run ALL simulators (no real hardware at all)
  [string]$Simulators = 'child'            # which simulators to run; the ones whose real
                                           # hardware is connected (lpg, pantry) stay off
)

$root = Split-Path -Parent $PSScriptRoot
$problems = 0
function Bad($msg)  { $script:problems++; Write-Host "  [FIX]  $msg" -ForegroundColor Yellow }
function Good($msg) { Write-Host "  [ OK ] $msg" -ForegroundColor Green }

Write-Host "`nKitchenGuard dev-stack check" -ForegroundColor Cyan

# 1. Which adapter/IP do devices see? (the one with a default gateway)
$cfg = Get-NetIPConfiguration | Where-Object {
  $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up'
} | Select-Object -First 1
if (-not $cfg) { Bad "No connected network adapter with a gateway found."; exit 1 }
$ip = $cfg.IPv4Address.IPAddress
Write-Host "  Laptop IPv4: $ip  (network: $($cfg.NetProfile.Name))"

# 2. MQTT_HOST in firmware config must equal that IP
$configH = Join-Path $root 'firmware\LPG_Device\config.h'
if (Test-Path $configH) {
  $m = Select-String -Path $configH -Pattern '#define\s+MQTT_HOST\s+"([^"]*)"'
  $host_ = if ($m) { $m.Matches[0].Groups[1].Value } else { '' }
  if ($host_ -eq $ip) { Good "firmware MQTT_HOST ($host_) matches this laptop" }
  else { Bad "firmware MQTT_HOST is '$host_' but this laptop is $ip. Edit config.h and re-flash." }
}

# 3. Network category: a rule scoped to Private does nothing on a Public network
$category = $cfg.NetProfile.NetworkCategory
if ($category -eq 'Private') { Good "network profile is Private" }
else {
  Bad ("network profile is '$category'. Fix once, in an ADMIN PowerShell:`n" +
       "         Set-NetConnectionProfile -InterfaceAlias '$($cfg.InterfaceAlias)' -NetworkCategory Private")
}

# 4. Inbound firewall rule for TCP 1883, scoped to Private
$rule = Get-NetFirewallRule -DisplayName 'KitchenGuard MQTT 1883' -ErrorAction SilentlyContinue
if ($rule -and $rule.Enabled -eq 'True') { Good "firewall rule 'KitchenGuard MQTT 1883' exists" }
else {
  Bad ("no inbound firewall rule for TCP 1883. Add once, in an ADMIN PowerShell:`n" +
       "         New-NetFirewallRule -DisplayName 'KitchenGuard MQTT 1883' -Direction Inbound -Protocol TCP -LocalPort 1883 -Action Allow -Profile Private")
}

# 4b. The pest camera board POSTs photos to the API on TCP 8000 over the LAN
$apiRule = Get-NetFirewallRule -DisplayName 'KitchenGuard API 8000' -ErrorAction SilentlyContinue
if ($apiRule -and $apiRule.Enabled -eq 'True') { Good "firewall rule 'KitchenGuard API 8000' exists (pest camera uploads)" }
else {
  Bad ("no inbound firewall rule for TCP 8000 (the pest camera board uploads photos there). In an ADMIN PowerShell:`n" +
       "         New-NetFirewallRule -DisplayName 'KitchenGuard API 8000' -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private")
}
$apiListen = Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($apiListen -and $apiListen.LocalAddress -notin @('0.0.0.0', '::')) {
  Bad ("the API (PID $($apiListen.OwningProcess)) listens on $($apiListen.LocalAddress) ONLY, so the camera board cannot upload photos.`n" +
       "         Restart the stack with the current preview_stack.py (it now binds 0.0.0.0).")
}

# 5. What is already listening on 1883, and on which address?
$listen = Get-NetTCPConnection -State Listen -LocalPort 1883 -ErrorAction SilentlyContinue
if ($listen) {
  $addr = ($listen | Select-Object -First 1).LocalAddress
  $procId = ($listen | Select-Object -First 1).OwningProcess
  if ($addr -in @('0.0.0.0', '::')) { Good "broker already listening on all interfaces (PID $procId)" }
  else {
    Bad ("a broker (PID $procId) is listening on $addr ONLY, so the ESP32 cannot reach it.`n" +
         "         Stop it (Ctrl+C in its terminal) and run this script again.")
  }
} else { Write-Host "  [ -- ] nothing listening on 1883 yet" }

# 5b. Pest species model (informational: the pipeline works without it, just unclassified)
$yolo = Join-Path $root 'ml\models\pest_yolo.onnx'
if (Test-Path $yolo) { Good "pest YOLO model present (ml\models\pest_yolo.onnx)" }
else { Write-Host "  [ -- ] no ml\models\pest_yolo.onnx yet: photos are saved but not classified" }

# 6. Is a simulator also running?
$sims = Get-CimInstance Win32_Process -Filter "Name like 'python%'" |
  Where-Object { $_.CommandLine -match 'lpg_sim|run_all' }
if ($sims) { Bad "simulator process running (PID $($sims.ProcessId -join ', ')). It will fight the real lpg01 device." }

if ($CheckOnly) {
  if ($problems -eq 0) { Write-Host "`nAll checks passed." -ForegroundColor Green }
  else { Write-Host "`n$problems item(s) need attention (see [FIX] above)." -ForegroundColor Yellow }
  exit $problems
}

if ($listen) { Write-Host "`nNot starting: something already holds port 1883 (see above)." -ForegroundColor Yellow; exit 1 }

$env:MQTT_BIND = '0.0.0.0'
if ($WithSimulators) { $env:PREVIEW_SIMULATORS = 'lpg,pantry,pest,child' }
else { $env:PREVIEW_SIMULATORS = $Simulators }
Write-Host "`nStarting backend: MQTT_BIND=0.0.0.0, simulators ON: $env:PREVIEW_SIMULATORS" -ForegroundColor Cyan
Write-Host "(a simulator must be OFF once its real device is connected: lpg01 = LPG board, pantry01 = pantry boards)"
Write-Host "Verify from another terminal:  .\scripts\dev_stack.ps1 -CheckOnly   (broker must say 'all interfaces')`n"
Set-Location $root
python .\backend\preview_stack.py

# Copies the addon into the game's AddOns folder (the live WoW: Forever client by default).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/install.ps1
# A new file or a changed .toc needs a full restart of the game; changed .lua files only need /reload.
# First it backs up XNAH's saved data of every WoW account (private\backups\install-<date>\<account>.lua; the last 15
# kept) - Xn, 2026-11-22: "is there a way to preserve it" after an update seemed to wipe a week of prices.
param([string]$AddOns = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns')
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'XNAH'
$dst = Join-Path $AddOns 'XNAH'
if (-not (Test-Path $AddOns)) { Write-Output "AddOns folder not found: $AddOns"; exit 1 }

# [[ backup of the saved data ]]
$wtf = Join-Path (Split-Path (Split-Path $AddOns -Parent) -Parent) 'WTF\Account'
if (Test-Path $wtf) {
  $stamp = Get-Date -Format 'yyyy-MM-dd-HH-mm'
  $bdir = Join-Path $root "private\backups\install-$stamp"
  $saved = 0
  Get-ChildItem -Path $wtf -Directory | ForEach-Object {
    $f = Join-Path $_.FullName 'SavedVariables\XNAH.lua'
    if (Test-Path $f) {
      if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Path $bdir -Force | Out-Null }
      $name = ($_.Name -replace '[^A-Za-z0-9_#-]', '_') + '.lua'
      Copy-Item -Path $f -Destination (Join-Path $bdir $name) -Force
      $saved++
    }
  }
  if ($saved -gt 0) { Write-Output "saved data of $saved account(s) backed up to $bdir" }
  $old = Get-ChildItem -Path (Join-Path $root 'private\backups') -Directory -Filter 'install-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -Skip 15
  foreach ($o in $old) { Remove-Item -Path $o.FullName -Recurse -Force }
}

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
$n = 0
Get-ChildItem -Path $src -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination (Join-Path $dst $_.Name) -Force; $n++ }
$bad = 0
Get-ChildItem -Path $src -File | ForEach-Object {
  $a = (Get-FileHash $_.FullName).Hash; $b = (Get-FileHash (Join-Path $dst $_.Name)).Hash
  if ($a -ne $b) { $bad++; Write-Output "DIFFERENT: $($_.Name)" }
}
$stale = Get-ChildItem -Path $dst -File | Where-Object { -not (Test-Path (Join-Path $src $_.Name)) }
foreach ($f in $stale) { Write-Output "NOTE: $($f.Name) is in the game's folder but no longer part of the addon (not loaded if the .toc does not list it)" }
Write-Output "$n files copied to $dst, $bad differ"
if ($bad -gt 0) { exit 1 }

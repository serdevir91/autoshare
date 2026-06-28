$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

# Read version from pubspec.yaml
$pubspec = Get-Content -Path "pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s*([0-9\.\+]+)')
if ($versionMatch.Success) {
  $fullVersion = $versionMatch.Groups[1].Value.Trim()
  $versionName = $fullVersion.Split('+')[0]
} else {
  $versionName = "1.0.4" # fallback
}

Write-Host "Detected version $versionName from pubspec.yaml"

flutter build windows --release

$issTemplatePath = "windows\installer.iss"
$issPath = "build\windows\x64\runner\Release\installer.iss"

if (Test-Path $issTemplatePath) {
  $releaseDir = Split-Path -Path $issPath -Parent
  if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
  }
  Copy-Item -Path $issTemplatePath -Destination $issPath -Force
  Write-Host "Copied installer.iss template to $issPath"
} elseif (-not (Test-Path $issPath)) {
  throw "installer.iss not found at template path $issTemplatePath or release path $issPath"
}

$content = Get-Content -Raw $issPath
$content = $content -replace "AppVersion=[0-9\.\+]+", "AppVersion=$versionName"
$content = $content -replace "OutputBaseFilename=\S+", "OutputBaseFilename=windows-setup-AutoShare"

Set-Content -Path $issPath -Value $content -NoNewline

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  throw "ISCC not found at $iscc"
}

& $iscc $issPath
Write-Host "Installer generated under installer_output/ as windows-setup-AutoShare.exe"

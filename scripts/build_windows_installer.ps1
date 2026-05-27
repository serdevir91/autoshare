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

$issPath = "build\windows\x64\runner\Release\installer.iss"
if (-not (Test-Path $issPath)) {
  throw "installer.iss not found at $issPath"
}

$content = Get-Content -Raw $issPath
$content = $content -replace "AppVersion=1.0.0", "AppVersion=$versionName"
$content = $content -replace "OutputBaseFilename=AutoShare-Setup-1.0.0", "OutputBaseFilename=windows-setup-AutoShare"
$content = $content -replace "PrivilegesRequired=admin", "PrivilegesRequired=admin`r`nCloseApplications=force"
$content = $content -replace [regex]::Escape("// Add firewall rules for AutoShare`r`n    Exec('netsh', 'advfirewall firewall add rule name=""AutoShare UDP"" dir=in action=allow protocol=UDP localport=53842', '', SW_HIDE, ewNoWait, ResultCode);`r`n    Exec('netsh', 'advfirewall firewall add rule name=""AutoShare TCP"" dir=in action=allow protocol=TCP localport=53843', '', SW_HIDE, ewNoWait, ResultCode);"), @"
// Replace existing rules to avoid duplicates
    Exec('netsh', 'advfirewall firewall delete rule name="AutoShare UDP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('netsh', 'advfirewall firewall delete rule name="AutoShare TCP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // Add safer inbound rules scoped to any network profile (critical for public/hotspot networks) and this executable only
    Exec('netsh', 'advfirewall firewall add rule name="AutoShare UDP" dir=in action=allow profile=any program="{app}\autoshare.exe" protocol=UDP localport=53842', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('netsh', 'advfirewall firewall add rule name="AutoShare TCP" dir=in action=allow profile=any program="{app}\autoshare.exe" protocol=TCP localport=53843', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Exec('netsh', 'advfirewall firewall delete rule name="AutoShare UDP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('netsh', 'advfirewall firewall delete rule name="AutoShare TCP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
"@

Set-Content -Path $issPath -Value $content -NoNewline

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  throw "ISCC not found at $iscc"
}

& $iscc $issPath
Write-Host "Installer generated under installer_output/ as windows-setup-AutoShare.exe"

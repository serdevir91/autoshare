[Setup]
AppName=AutoShare
AppVersion=1.0.10
AppPublisher=Soner Erdevir
DefaultDirName={autopf}\AutoShare
DefaultGroupName=AutoShare
OutputDir=..\..\..\..\..\installer_output
OutputBaseFilename=windows-setup-AutoShare
UninstallDisplayIcon={app}\autoshare.exe
WizardStyle=modern
PrivilegesRequired=admin
CloseApplications=force
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AutoShare"; Filename: "{app}\autoshare.exe"
Name: "{group}\Uninstall AutoShare"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AutoShare"; Filename: "{app}\autoshare.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\autoshare.exe"; Description: "Launch AutoShare"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
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
  end;
end;

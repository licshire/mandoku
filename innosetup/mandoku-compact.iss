; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

#define MyAppName "Emacs Mandoku"
#define MyAppVersion "0.1"
#define MyAppPublisher "Christian Wittern"
#define MyAppURL "http://www.mandoku.org/"
#define MyAppExeName "runemacs.exe"
;{ extracts drive letter from the source
;{drive:{src}}

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
PrivilegesRequired=none
AppId={{5B73A9B3-976F-4074-83AD-9A3B74C7D60E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
;AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DisableDirPage=yes
DefaultDirName=krp
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=license.txt
InfoBeforeFile=readme.txt
   ;InfoAfterFile={%HOME}\.emacs.d\md\myfiles.txt
OutputBaseFilename=mandoku-setup-compact
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

;[Tasks]
;Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked


[Dirs]
Name: "{code:GetDataDir}\images"
Name: "{code:GetDataDir}\index"
Name: "{code:GetDataDir}\meta"
Name: "{code:GetDataDir}\system"
Name: "{code:GetDataDir}\temp"
Name: "{code:GetDataDir}\text"
Name: "{code:GetDataDir}\user"
Name: "{code:GetDataDir}\work"
Name: "{%HOME}\.emacs.d\user"



[Files]
;#include "e:\py\out.txt"
; NOTE: Don't use "Flags: ignoreversion" on any shared system files'
;; try this!
Source: "c:\python\*"; DestDir: "{code:GetDataDir}\system\python"; Flags: recursesubdirs; 
;Source: "c:\krp\bin\*"; DestDir: "{app}\bin"; Flags: recursesubdirs; Excludes: "*.pyc,installer,installdirs"
;Source: "README.TXT"; DestDir: "{app}"; Flags: isreadme
;Source:"addsshkey.bat"; DestDir: "{app}"; 
;Source:"init.el"; DestDir: "{%HOME}\.emacs.d\"; Flags: ignoreversion
;onlyifdoesntexist
Source: "..\md\md-kit.el"; DestDir: "{%HOME}\.emacs.d\md"; Flags: ignoreversion
Source: "..\md\md-init.el"; DestDir: "{%HOME}\.emacs.d\md"; Flags: ignoreversion
Source: "..\md\install-packages.el"; DestDir: "{%HOME}\.emacs.d\md"; Flags: ignoreversion
Source:"postflight.py"; DestDir: "{%HOME}\.emacs.d\md"; Flags: ignoreversion
Source:"ffm.bat"; DestDir: "{%HOME}\.emacs.d\md"; Flags: ignoreversion
Source: "addsshkey.py"; DestDir: "{code:GetDataDir}\system\python"; Flags: ignoreversion
;[Icons]
;Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
;Name:"{commondesktop}\{#MyAppName}"; Filename: "{app}\bin\emacs-24.3\bin\{#MyAppExeName}"; Tasks: desktopicon

[REGISTRY]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "HOME"; ValueData: "{%USERPROFILE}"
Root: HKCU; Subkey: "Environment"; ValueType: string; ValueName: "MDTEMP"; ValueData: "{code:GetDataDir}\temp"
;Root: HKCU; Subkey: "Environment"; ValueType expandsz; ValueName "TMP"; ValueData "{code:GetDataDir}\tmp"

[INI]
Filename:"{%HOME}\.emacs.d\md\mandoku.cfg"; Section: "Mandoku"; Key: "basedir"; String: "{code:GetDataDir}"
Filename:"{%HOME}\.emacs.d\md\mandoku.cfg"; Section: "Mandoku"; Key: "appdir"; String: "{app}"
Filename:"{code:GetDataDir}\user\mandoku-settings.cfg"; Section: "Gitlab"; Key: "Private Token"; String: "{code:GetUser|Token}"
Filename:"{code:GetDataDir}\user\mandoku-settings.cfg"; Section: "Gitlab"; Key: "Username"; String: "{code:GetUser|Name}"
Filename:"{code:GetDataDir}\user\mandoku-settings.cfg"; Section: "Gitlab"; Key: "Email"; String: "{code:GetUser|Email}"
;Filename: "MyProg.ini"; Section: "InstallSettings"; Key: "InstallPath"; String: "{app}"


[Run]
;optional
Filename:"{%HOME}\.emacs.d\md\ffm.bat"; Parameters: "{code:GetDataDir}"
;Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

;{pf}, {pf32}, {pf64} = program directories
[Code]


var
  UserPage: TInputQueryWizardPage;
  DataDirPage: TInputDirWizardPage;
  
procedure InitializeWizard;
begin
  { Create the pages }
{wpWelcome, wpLicense, wpPassword, wpInfoBefore, wpUserInfo, wpSelectDir, wpSelectComponents, wpSelectProgramGroup, wpSelectTasks, wpReady, wpPreparing, wpInstalling, wpInfoAfter, wpFinished}   
  UserPage := CreateInputQueryPage(wpInfoBefore,
    'Gitlab Token', 'Enter the Gitlab token and username?',
    'The token is available on your Gitlab profile page. Please enter the necessary information, then click Next.');
  UserPage.Add('Gitlab Private token:', False);
  UserPage.Add('Gitlab Username:     ', False); 
  UserPage.Add('Gitlab Email:     ', False); 

  DataDirPage := CreateInputDirPage(wpSelectDir,
    'Select the Mandoku Base Directory', 'Where should the Mandoku data files be installed?',
    'Select the folder in which Setup should install the Mandoku data files, then click Next.',
    False, '');
  DataDirPage.Add('');

   
  { Set default values, using settings that were stored last time if possible }

  UserPage.Values[0] := GetPreviousData('Token', '');
  UserPage.Values[1] := GetPreviousData('Name', ''); 
  UserPage.Values[2] := GetPreviousData('Email', ''); 
  DataDirPage.Values[0] := GetPreviousData('DataDir', '');

end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
var
  UsageMode: String;
begin
  { Store the settings so we can restore them next time }
  SetPreviousData(PreviousDataKey, 'Token', UserPage.Values[0]);
  SetPreviousData(PreviousDataKey, 'Name', UserPage.Values[1]); 
  SetPreviousData(PreviousDataKey, 'Email', UserPage.Values[2]); 
  SetPreviousData(PreviousDataKey, 'DataDir', DataDirPage.Values[0]);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  { Validate certain pages before allowing the user to proceed }
  if CurPageID = UserPage.ID then begin
    if UserPage.Values[0] = '' then begin
      MsgBox('You must enter your private token.', mbError, MB_OK);
      Result := False;
    end else
      Result := True;
  end else
    Result := True;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  S: String;
begin
  { Fill the 'Ready Memo' with the normal settings and the custom settings }
  S := '';
  S := S + 'Information you provided for Installation:' + NewLine;
  S := S + Space + UserPage.Values[0] + NewLine;
  if UserPage.Values[1] <> '' then
    S := S + Space + UserPage.Values[1] + NewLine;
  if UserPage.Values[2] <> '' then
    S := S + Space + UserPage.Values[2] + NewLine;
  S := S + NewLine;

  Result := S;
end;

function GetUser(Param: String): String;
begin
  { Return a user value }
  { Could also be split into separate GetUserName and GetUserCompany functions }
  if Param = 'Token' then
    Result := UserPage.Values[0]
  else if Param = 'Name' then
    Result := UserPage.Values[1];
end;


function GetDataDir(Param: String): String;
begin
  { Return the selected DataDir }
  Result := DataDirPage.Values[0];
end;

{ procedure WriteBatch(Param : String ); }
{ begin }
{    SaveStringToFile('c:\filename.txt', #13#10 + 'the string' + #13#10, True); }
{ end; }


; Instalador do Stemma (F5b, ADR 0014). Inno Setup 6.3+ (usa ExecAndLogOutput).
; Compilar: powershell -File installer\build.ps1 -ZipPath <stemma-vX.Y.Z.zip>
; Este arquivo só monta as telas e repassa parâmetros: toda a lógica fica em deploy\setup.ps1
; e deploy\StemmaDeploy.psm1.
;
; Linha de comando (além das do Inno):
;   /SIMULATEFAILURE   na atualização, faz o /health da versão nova falhar (teste do rollback)
;   /ROOT=, /SERVICEID=, /PORT=, /DATAROOT=, /SKIPTAILSCALE   ensaio numa instalação paralela

#ifndef AppVersion
  #error Defina AppVersion (ex.: /DAppVersion=1.4.0)
#endif
#ifndef PayloadDir
  #error Defina PayloadDir (pasta com o zip da release, o .sha256 e a wheel do segno)
#endif
#define ZipName "stemma-v" + AppVersion + ".zip"

[Setup]
AppId=Stemma{code:AppIdSuffix}
AppName=Stemma
AppVersion={#AppVersion}
AppVerName=Stemma {#AppVersion}
AppPublisher=Arthur Luciani
AppPublisherURL=https://github.com/Arthur-Luciani/stemma
DefaultDirName={code:GetRoot}\setup
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=no
UsePreviousLanguage=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=Stemma-Setup-v{#AppVersion}
SetupIconFile=stemma.ico
UninstallDisplayIcon={app}\stemma.ico
UninstallDisplayName=Stemma
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=120
CloseApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Messages]
brazilianportuguese.WelcomeLabel2=Vamos instalar o Stemma {#AppVersion} neste PC.%n%nO Stemma roda como um serviço do Windows e fica acessível no celular pelo Tailscale. Na primeira vez são baixados alguns componentes (até ~3 GB, se ainda não estiverem no PC).

[InstallDelete]
Type: filesandordirs; Name: "{app}\payload"

[Files]
Source: "..\deploy\setup.ps1"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "..\deploy\StemmaDeploy.psm1"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "qr.py"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "{#PayloadDir}\segno-*.whl"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "{#PayloadDir}\{#ZipName}"; DestDir: "{app}\payload"; Flags: ignoreversion
Source: "{#PayloadDir}\{#ZipName}.sha256"; DestDir: "{app}\payload"; Flags: ignoreversion
Source: "stemma.ico"; DestDir: "{app}"; Flags: ignoreversion
; Ícone da bandeja (installer\tray\StemmaTray.cs, compilado pelo build.ps1).
Source: "{#PayloadDir}\Stemma.exe"; DestDir: "{app}"; Flags: ignoreversion
; Cópias para a checagem antes de instalar (extraídas em {tmp}).
Source: "..\deploy\setup.ps1"; Flags: dontcopy
Source: "..\deploy\StemmaDeploy.psm1"; Flags: dontcopy

[Icons]
; Menu Iniciar: abre o navegador (e põe o ícone na bandeja, se não estiver). No login: só o ícone.
; Parar/iniciar ficam no menu do ícone da bandeja.
Name: "{autoprograms}\{code:GroupName}"; Filename: "{app}\Stemma.exe"; Parameters: "--root ""{code:GetRoot}"" --service ""{code:GetServiceId}"" --open"
Name: "{autostartup}\{code:GroupName}"; Filename: "{app}\Stemma.exe"; Parameters: "--root ""{code:GetRoot}"" --service ""{code:GetServiceId}"""

[UninstallDelete]
Type: files; Name: "{app}\qr.bmp"
Type: files; Name: "{app}\Stemma.url"
Type: dirifempty; Name: "{app}"
Type: dirifempty; Name: "{app}\.."

[Code]
var
  DataPage: TInputDirWizardPage;
  PortPage: TInputQueryWizardPage;
  TailscalePage: TWizardPage;
  TsStatus: TNewStaticText;
  TsAction: TNewButton;
  TsRefresh: TNewButton;
  TsPanel: TNewButton;
  OpenButton: TNewButton;
  QrImage: TBitmapImage;
  { Resultado do motor (linhas ##RESULT). }
  Installed, HasService, CheckPort, CheckDataRoot, TsState, TsHost, Gpu: String;
  ResultUrl, ResultQr, ResultVersion, ResultLog, ErrorText, LastStep: String;
  Succeeded: Boolean;

{ --- linha de comando -------------------------------------------------------- }

function HasFlag(const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/' + Name) = 0 then
      Result := True;
end;

function GetRoot(Param: String): String;
begin
  Result := ExpandConstant('{param:ROOT|C:\stemma}');
end;

function ServiceId: String;
begin
  Result := ExpandConstant('{param:SERVICEID|stemma}');
end;

function GetServiceId(Param: String): String;
begin
  Result := ServiceId;
end;

function GroupName(Param: String): String;
begin
  if CompareText(ServiceId, 'stemma') = 0 then
    Result := 'Stemma'
  else
    Result := 'Stemma (' + ServiceId + ')';
end;

function AppIdSuffix(Param: String): String;
begin
  { Ensaio com outro serviço não pode reaproveitar o registro da instalação real. }
  if CompareText(ServiceId, 'stemma') = 0 then
    Result := ''
  else
    Result := '-' + ServiceId;
end;

function SkipTailscale: Boolean;
begin
  Result := HasFlag('SKIPTAILSCALE');
end;

function IsUpdate: Boolean;
begin
  Result := (Installed <> '') and (HasService = 'yes');
end;

{ --- motor (deploy\setup.ps1) ------------------------------------------------ }

function PowerShellExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

function EngineParams(const Script, Mode, Extra: String): String;
begin
  Result := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Mode ' + Mode +
    ' -Root "' + GetRoot('') + '" -ServiceId "' + ServiceId + '"';
  if SkipTailscale then
    Result := Result + ' -SkipTailscale';
  if Extra <> '' then
    Result := Result + ' ' + Extra;
end;

procedure HandleLine(const S: String);
var
  Line, Key, Value: String;
  P: Integer;
begin
  Line := Trim(S);
  if Pos('##RESULT ', Line) = 1 then
  begin
    Line := Copy(Line, 10, Length(Line));
    P := Pos('=', Line);
    if P = 0 then Exit;
    Key := Copy(Line, 1, P - 1);
    Value := Copy(Line, P + 1, Length(Line));
    if Key = 'installed' then Installed := Value
    else if Key = 'service' then HasService := Value
    else if Key = 'port' then CheckPort := Value
    else if Key = 'dataroot' then CheckDataRoot := Value
    else if Key = 'tailscale' then TsState := Value
    else if Key = 'host' then TsHost := Value
    else if Key = 'gpu' then Gpu := Value
    else if Key = 'url' then ResultUrl := Value
    else if Key = 'qr' then ResultQr := Value
    else if Key = 'version' then ResultVersion := Value
    else if Key = 'log' then ResultLog := Value;
  end
  else if Pos('##ERROR ', Line) = 1 then
    ErrorText := Copy(Line, 9, Length(Line))
  else if Pos('==> ', Line) = 1 then
    LastStep := Copy(Line, 5, Length(Line));
end;

function TempEngine: String;
begin
  ExtractTemporaryFile('setup.ps1');
  ExtractTemporaryFile('StemmaDeploy.psm1');
  Result := ExpandConstant('{tmp}\setup.ps1');
end;

{ Roda um modo rápido do motor e lê as linhas ##RESULT. }
function RunEngineQuick(const Mode, Extra: String): Boolean;
var
  Output: TExecOutput;
  ResultCode, I: Integer;
begin
  ErrorText := '';
  Result := ExecAndCaptureOutput(PowerShellExe, EngineParams(TempEngine, Mode, Extra), '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode, Output) and (ResultCode = 0);
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
  begin
    Log(Output.StdOut[I]);
    HandleLine(Output.StdOut[I]);
  end;
end;

{ Instalação/atualização: o texto de cada etapa vai para a tela de progresso. }
procedure OnEngineLog(const S: String; const Error, FirstLine: Boolean);
begin
  Log(S);
  HandleLine(S);
  WizardForm.StatusLabel.Caption := LastStep;
  if (Pos('##', Trim(S)) <> 1) and (Pos('==> ', Trim(S)) <> 1) then
    WizardForm.FilenameLabel.Caption := Trim(S);
end;

{ --- Tailscale ------------------------------------------------------------------ }

procedure UpdateTailscalePage;
begin
  TsAction.Visible := True;
  TsPanel.Visible := False;
  if TsState = 'missing' then
  begin
    TsStatus.Caption := 'O Tailscale não está instalado. Ele dá ao Stemma um endereço HTTPS para abrir no celular, de qualquer lugar.';
    TsAction.Caption := 'Instalar o Tailscale';
  end
  else if (TsState = 'needslogin') or (TsState = 'stopped') then
  begin
    TsStatus.Caption := 'O Tailscale está instalado, mas não está conectado. Clique em Entrar, faça o login no navegador e depois em Verificar de novo.';
    TsAction.Caption := 'Entrar';
  end
  else if TsState = 'nohttps' then
  begin
    TsStatus.Caption := 'Falta ativar os certificados HTTPS no seu tailnet: no painel do Tailscale, em DNS, ative "HTTPS Certificates". Depois clique em Verificar de novo.';
    TsAction.Visible := False;
    TsPanel.Visible := True;
  end
  else if TsState = 'ready' then
  begin
    TsStatus.Caption := 'Tudo certo. O Stemma vai ficar em https://' + TsHost;
    TsAction.Visible := False;
  end
  else
  begin
    TsStatus.Caption := 'O Tailscale está iniciando. Aguarde alguns segundos e clique em Verificar de novo.';
    TsAction.Visible := False;
  end;
end;

procedure RefreshTailscale;
begin
  WizardForm.NextButton.Enabled := False;
  TsStatus.Caption := 'Verificando o Tailscale…';
  RunEngineQuick('Check', '');
  UpdateTailscalePage;
  WizardForm.NextButton.Enabled := True;
end;

procedure TsActionClick(Sender: TObject);
begin
  TsAction.Enabled := False;
  try
    if TsState = 'missing' then
    begin
      TsStatus.Caption := 'Baixando e instalando o Tailscale…';
      if not RunEngineQuick('TailscaleInstall', '') then
        MsgBox('Não foi possível instalar o Tailscale: ' + ErrorText, mbError, MB_OK);
    end
    else
    begin
      TsStatus.Caption := 'Abrindo o login do Tailscale no navegador…';
      RunEngineQuick('TailscaleLogin', '');
    end;
    RefreshTailscale;
  finally
    TsAction.Enabled := True;
  end;
end;

procedure TsRefreshClick(Sender: TObject);
begin
  RefreshTailscale;
end;

procedure TsPanelClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ShellExec('open', 'https://login.tailscale.com/admin/dns', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

procedure OpenButtonClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ShellExec('open', ResultUrl, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

{ --- telas ------------------------------------------------------------------------ }

procedure InitializeWizard;
begin
  RunEngineQuick('Check', '');
  if Gpu <> 'ok' then
    SuppressibleMsgBox('Não achei a GPU NVIDIA (nvidia-smi). O Stemma funciona, mas a separação na CPU é bem mais lenta. Instale o driver da NVIDIA se o PC tiver uma placa.',
      mbInformation, MB_OK, IDOK);

  DataPage := CreateInputDirPage(wpWelcome, 'Pasta de dados',
    'Onde ficam músicas, stems, exportações e o banco do Stemma.',
    'Escolha uma pasta com espaço livre (cada música separada ocupa algumas dezenas de MB).',
    False, '');
  DataPage.Add('');
  DataPage.Values[0] := ExpandConstant('{param:DATAROOT|' + CheckDataRoot + '}');

  PortPage := CreateInputQueryPage(DataPage.ID, 'Porta',
    'Porta local do Stemma neste PC.',
    'O Tailscale publica o Stemma em HTTPS a partir desta porta. Mude só se a 8000 já estiver em uso.');
  PortPage.Add('Porta:', False);
  PortPage.Values[0] := ExpandConstant('{param:PORT|8000}');

  TailscalePage := CreateCustomPage(PortPage.ID, 'Tailscale',
    'Acesso pelo celular, com HTTPS, sem abrir portas no roteador.');
  TsStatus := TNewStaticText.Create(TailscalePage);
  TsStatus.Parent := TailscalePage.Surface;
  TsStatus.WordWrap := True;
  TsStatus.AutoSize := False;
  TsStatus.Width := TailscalePage.SurfaceWidth;
  TsStatus.Height := ScaleY(72);
  TsAction := TNewButton.Create(TailscalePage);
  TsAction.Parent := TailscalePage.Surface;
  TsAction.Top := TsStatus.Top + TsStatus.Height + ScaleY(8);
  TsAction.Width := ScaleX(160);
  TsAction.Height := WizardForm.NextButton.Height;
  TsAction.OnClick := @TsActionClick;
  TsPanel := TNewButton.Create(TailscalePage);
  TsPanel.Parent := TailscalePage.Surface;
  TsPanel.Top := TsAction.Top;
  TsPanel.Width := ScaleX(160);
  TsPanel.Height := WizardForm.NextButton.Height;
  TsPanel.Caption := 'Abrir o painel';
  TsPanel.OnClick := @TsPanelClick;
  TsRefresh := TNewButton.Create(TailscalePage);
  TsRefresh.Parent := TailscalePage.Surface;
  TsRefresh.Top := TsAction.Top;
  TsRefresh.Left := TsAction.Left + TsAction.Width + ScaleX(8);
  TsRefresh.Width := ScaleX(160);
  TsRefresh.Height := WizardForm.NextButton.Height;
  TsRefresh.Caption := 'Verificar de novo';
  TsRefresh.OnClick := @TsRefreshClick;
  UpdateTailscalePage;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = DataPage.ID) or (PageID = PortPage.ID) then
    Result := IsUpdate
  else if PageID = TailscalePage.ID then
    Result := SkipTailscale or (IsUpdate and (TsState = 'ready'));
end;

procedure ShowFinished; forward;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = TailscalePage.ID then
    RefreshTailscale
  else if CurPageID = wpFinished then
    ShowFinished;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Port: Integer;
begin
  Result := True;
  if CurPageID = PortPage.ID then
  begin
    Port := StrToIntDef(Trim(PortPage.Values[0]), 0);
    if (Port < 1024) or (Port > 65535) then
    begin
      MsgBox('Use uma porta entre 1024 e 65535.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if (CurPageID = TailscalePage.ID) and (TsState <> 'ready') then
  begin
    MsgBox('Termine a configuração do Tailscale antes de continuar.', mbInformation, MB_OK);
    Result := False;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := '';
end;

{ --- instalação ---------------------------------------------------------------- }

procedure RunInstall;
var
  Params, Zip: String;
  ResultCode: Integer;
begin
  Zip := ExpandConstant('{app}\payload\{#ZipName}');
  Params := '-ZipPath "' + Zip + '" -QrPath "' + ExpandConstant('{app}\qr.bmp') + '"';
  if IsUpdate then
  begin
    if HasFlag('SIMULATEFAILURE') then
      Params := Params + ' -SimulateFailure';
    Params := EngineParams(ExpandConstant('{app}\engine\setup.ps1'), 'Update', Params);
  end
  else
    Params := EngineParams(ExpandConstant('{app}\engine\setup.ps1'), 'Install',
      Params + ' -DataRoot "' + Trim(DataPage.Values[0]) + '" -Port ' + Trim(PortPage.Values[0]));

  WizardForm.ProgressGauge.Style := npbstMarquee;
  ErrorText := '';
  LastStep := 'Preparando…';
  WizardForm.StatusLabel.Caption := LastStep;
  Succeeded := ExecAndLogOutput(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated,
    ResultCode, @OnEngineLog) and (ResultCode = 0);
  WizardForm.ProgressGauge.Style := npbstNormal;
  if not Succeeded then
  begin
    if ErrorText = '' then
      ErrorText := 'o instalador terminou com código ' + IntToStr(ResultCode) + '.';
    SuppressibleMsgBox(ErrorText + #13#10#13#10 + 'Log: ' + ResultLog, mbError, MB_OK, IDOK);
  end;
end;

{ Fecha o ícone da bandeja desta instalação (para trocar ou apagar o Stemma.exe). }
procedure CloseTray;
var
  ResultCode: Integer;
begin
  Exec(PowerShellExe, '-NoProfile -NonInteractive -Command "Get-Process Stemma -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -eq ''' + ExpandConstant('{app}\Stemma.exe') + ''' } | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure StartTray;
var
  ResultCode: Integer;
begin
  ExecAsOriginalUser(ExpandConstant('{app}\Stemma.exe'),
    '--root "' + GetRoot('') + '" --service "' + ServiceId + '"', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseTray;
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RunInstall;
    { Endereço lido pelo ícone da bandeja (Abrir o Stemma). }
    if Succeeded and (ResultUrl <> '') then
      SaveStringToFile(ExpandConstant('{app}\Stemma.url'),
        '[InternetShortcut]' + #13#10 + 'URL=' + ResultUrl + #13#10, False);
    { Ícone na bandeja, como o usuário (não elevado). Numa falha também: ele mostra o estado. }
    if Installed + ResultVersion <> '' then
      StartTray;
  end;
end;

procedure ShowFinished;
var
  Top: Integer;
begin
  if not Succeeded then
  begin
    WizardForm.FinishedHeadingLabel.Caption := 'Não deu certo';
    if IsUpdate then
      WizardForm.FinishedLabel.Caption := 'A atualização falhou: ' + ErrorText + #13#10#13#10 +
        'A versão anterior continua no ar. Log: ' + ResultLog
    else
      WizardForm.FinishedLabel.Caption := 'A instalação não terminou: ' + ErrorText + #13#10#13#10 +
        'Corrija e rode o instalador de novo. Log: ' + ResultLog;
    Exit;
  end;

  WizardForm.FinishedHeadingLabel.Caption := 'Stemma ' + ResultVersion + ' no ar';
  if Pos('https://', ResultUrl) = 1 then
    WizardForm.FinishedLabel.Caption := 'No celular, aponte a câmera para o QR code ou abra o endereço abaixo. ' +
      'No Chrome, use o menu ⋮ → Instalar app.' + #13#10#13#10 + ResultUrl
  else
    WizardForm.FinishedLabel.Caption := 'Sem o Tailscale, o Stemma abre só neste PC:' + #13#10#13#10 + ResultUrl;
  WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
    'Ele fica rodando em segundo plano. O ícone do Stemma perto do relógio mostra o estado e tem Abrir, QR para o celular e Parar/Iniciar.';
  WizardForm.FinishedLabel.AdjustHeight;
  Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(16);

  { O botão fica ao lado do QR (embaixo dele não cabe na página). }
  OpenButton := TNewButton.Create(WizardForm.FinishedPage);
  OpenButton.Parent := WizardForm.FinishedPage;
  OpenButton.Left := WizardForm.FinishedLabel.Left;
  OpenButton.Top := Top;
  OpenButton.Width := ScaleX(150);
  OpenButton.Height := ScaleY(30);
  OpenButton.Caption := 'Abrir o Stemma';
  OpenButton.OnClick := @OpenButtonClick;

  if (ResultQr <> '') and FileExists(ResultQr) then
  begin
    QrImage := TBitmapImage.Create(WizardForm.FinishedPage);
    QrImage.Parent := WizardForm.FinishedPage;
    QrImage.Left := WizardForm.FinishedLabel.Left;
    QrImage.Top := Top;
    QrImage.Width := ScaleX(150);
    QrImage.Height := ScaleY(150);
    QrImage.Stretch := True;
    QrImage.Bitmap.LoadFromFile(ResultQr);
    OpenButton.Left := QrImage.Left + QrImage.Width + ScaleX(16);
    OpenButton.Top := QrImage.Top + (QrImage.Height - OpenButton.Height) div 2;
  end;
end;

{ --- desinstalação -------------------------------------------------------------- }

function ReadDataRoot(const Root: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  if LoadStringsFromFile(Root + '\.env', Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos('STORAGE_ROOT=', Trim(Lines[I])) = 1 then
        Result := Copy(Trim(Lines[I]), 14, Length(Lines[I]));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Root, DataRoot, Params: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  CloseTray;
  Root := ExtractFileDir(ExpandConstant('{app}'));
  DataRoot := ReadDataRoot(Root);
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\engine\setup.ps1') +
    '" -Mode Uninstall -Root "' + Root + '" -Keep setup';
  if (DataRoot <> '') and DirExists(DataRoot) then
    if SuppressibleMsgBox('Apagar também os dados do Stemma (músicas, stems, exportações e banco)?' + #13#10#13#10 +
      DataRoot + #13#10#13#10 + 'Escolha Não para manter (padrão).', mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
      Params := Params + ' -RemoveData';
  if not Exec(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    SuppressibleMsgBox('A remoção do serviço ou das pastas não terminou (código ' + IntToStr(ResultCode) +
      '). O log fica em %TEMP%\setup-uninstall-*.log.', mbError, MB_OK, IDOK);
end;

; Instalador do Stemma (F5b, ADR 0014). Inno Setup 6.3+ (usa ExecAndLogOutput).
; Compilar: powershell -File installer\build.ps1 -ZipPath <stemma-vX.Y.Z.zip>
; Este arquivo só monta as telas e repassa parâmetros: toda a lógica fica em deploy\setup.ps1
; e deploy\StemmaDeploy.psm1.
;
; Linha de comando (além das do Inno):
;   /SIMULATEFAILURE   na atualização, faz o /health da versão nova falhar (teste do rollback)
;   /ROOT=, /SERVICEID=, /PORT=, /DATAROOT=, /SKIPTAILSCALE   ensaio numa instalação paralela
;   /NOTRAY            não abre o ícone da bandeja no fim (atualização pelo app, que roda como SYSTEM)
;   /RESULTFILE=<arq>  grava "ok|<versão>" ou "erro|<motivo>" (atualização pelo app, ADR 0015)
; Na falha, o instalador termina com código de saída 1 (útil com /VERYSILENT).

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
DisableReadyPage=no
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
brazilianportuguese.WelcomeLabel2=Vamos instalar o Stemma {#AppVersion} neste PC.%n%nO Stemma roda como um serviço do Windows e fica acessível no celular pelo Tailscale.%n%nLeva uns 3 minutos se os componentes (torch e companhia) já estiverem neste PC. Se não estiverem, some o tempo de baixar ~3 GB. Antes de começar, o assistente mostra quanto vai baixar e o espaço necessário.
brazilianportuguese.ReadyLabel1=Tudo pronto para começar.
brazilianportuguese.ReadyLabel2b=Confira o que vai ser feito e clique em Instalar.

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
; uv.lock da release (build.ps1): estimativa de download e espaço na tela "Pronto para instalar".
Source: "{#PayloadDir}\uv.lock"; Flags: dontcopy

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
  TailscalePage: TWizardPage;
  TsStatus: TNewStaticText;
  TsAction: TNewButton;
  TsRefresh: TNewButton;
  TsPanel: TNewButton;
  OpenButton: TNewButton;
  QrImage: TBitmapImage;
  { Resultado do motor (linhas ##RESULT). }
  Installed, HasService, CheckPort, CheckDataRoot, TsState, TsHost, Gpu: String;
  FreePort, PortUse, Serve443, Serve8443, Serve443State, Serve8443State: String;
  { Estimativa (modo Check com -LockPath), em MB. }
  DownloadMB, NeedRootMB: String;
  { Progresso da instalação: etapa ("Etapa 3 de 9: …") e avanço de 0 a 1000. }
  StageText: String;
  ProgressValue: Integer;
  { Porta local, escolhida sozinha (a primeira livre a partir da 8000; /PORT= para forçar). }
  LocalPort: String;
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

function NoTray: Boolean;
begin
  Result := HasFlag('NOTRAY');
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

{ Argumento entre aspas para a linha de comando: uma barra no fim (ex.: "D:\") escaparia a aspa. }
function Quote(const S: String): String;
begin
  Result := S;
  if (Result <> '') and (Result[Length(Result)] = '\') then
    Result := Result + '\';
  Result := '"' + Result + '"';
end;

function EngineParams(const Script, Mode, Extra: String): String;
begin
  Result := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + Quote(Script) + ' -Mode ' + Mode +
    ' -Root ' + Quote(GetRoot('')) + ' -ServiceId ' + Quote(ServiceId);
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
    else if Key = 'freeport' then FreePort := Value
    else if Key = 'portuse' then PortUse := Value
    else if Key = 'serve443' then Serve443 := Value
    else if Key = 'serve8443' then Serve8443 := Value
    else if Key = 'serve443state' then Serve443State := Value
    else if Key = 'serve8443state' then Serve8443State := Value
    else if Key = 'url' then ResultUrl := Value
    else if Key = 'qr' then ResultQr := Value
    else if Key = 'version' then ResultVersion := Value
    else if Key = 'log' then ResultLog := Value
    else if Key = 'downloadmb' then DownloadMB := Value
    else if Key = 'needrootmb' then NeedRootMB := Value;
  end
  else if Pos('##STAGE ', Line) = 1 then
    StageText := Copy(Line, 9, Length(Line))
  else if Pos('##PROGRESS ', Line) = 1 then
    ProgressValue := StrToIntDef(Copy(Line, 12, Length(Line)), ProgressValue)
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

function TempLock: String;
begin
  ExtractTemporaryFile('uv.lock');
  Result := ExpandConstant('{tmp}\uv.lock');
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

{ Instalação/atualização: a etapa numerada em cima, o detalhe (passo ou saída) embaixo e a barra
  com o avanço total. }
procedure OnEngineLog(const S: String; const Error, FirstLine: Boolean);
var
  Line: String;
begin
  Log(S);
  HandleLine(S);
  Line := Trim(S);
  if StageText <> '' then
    WizardForm.StatusLabel.Caption := StageText
  else
    WizardForm.StatusLabel.Caption := LastStep;
  if Pos('==> ', Line) = 1 then
    WizardForm.FilenameLabel.Caption := LastStep
  else if (Line <> '') and (Pos('##', Line) <> 1) then
    WizardForm.FilenameLabel.Caption := Line;
  WizardForm.ProgressGauge.Position := ProgressValue;
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
  RunEngineQuick('Check', '-Port ' + LocalPort);
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
  RunEngineQuick('Check', '-LockPath ' + Quote(TempLock));
  if Gpu <> 'ok' then
    SuppressibleMsgBox('Não achei a GPU NVIDIA (nvidia-smi). O Stemma funciona, mas a separação na CPU é bem mais lenta. Instale o driver da NVIDIA se o PC tiver uma placa.',
      mbInformation, MB_OK, IDOK);

  DataPage := CreateInputDirPage(wpWelcome, 'Pasta de dados',
    'Onde ficam músicas, stems, exportações e o banco do Stemma.',
    'Escolha uma pasta com espaço livre (cada música separada ocupa algumas dezenas de MB).',
    False, '');
  DataPage.Add('');
  DataPage.Values[0] := ExpandConstant('{param:DATAROOT|' + CheckDataRoot + '}');

  { Sem tela de porta (detalhe técnico): a primeira livre a partir da 8000, que o motor confere de
    novo ao instalar. }
  if FreePort = '' then
    FreePort := '8000';
  LocalPort := ExpandConstant('{param:PORT|' + FreePort + '}');
  { /PORT= (ensaio): só uma porta válida, e o que as portas HTTPS do Tailscale publicam é
    conferido para ela (o Check inicial olhou a porta livre sugerida). }
  if (not IsUpdate) and (LocalPort <> FreePort) then
  begin
    if (StrToIntDef(LocalPort, 0) < 1024) or (StrToIntDef(LocalPort, 0) > 65535) then
    begin
      SuppressibleMsgBox('/PORT=' + LocalPort + ' não é uma porta válida (de 1024 a 65535). Vou usar a ' + FreePort + '.',
        mbInformation, MB_OK, IDOK);
      LocalPort := FreePort;
    end
    else
      RunEngineQuick('CheckPort', '-Port ' + LocalPort);
  end;

  TailscalePage := CreateCustomPage(DataPage.ID, 'Tailscale',
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
  if PageID = DataPage.ID then
    Result := IsUpdate
  else if PageID = TailscalePage.ID then
    { Só aparece quando há o que fazer (instalar, entrar, ativar o HTTPS). }
    Result := SkipTailscale or (TsState = 'ready');
end;

{ Porta HTTPS do Tailscale: a 443 (endereço sem porta), a não ser que ela já publique outro app;
  aí a 8443. Nunca tira o endereço de outro app. 0 = as duas ocupadas por outros apps. }
function ChosenHttpsPort: Integer;
begin
  if SkipTailscale or (Serve443State <> 'other') then
    Result := 443
  else if Serve8443State <> 'other' then
    Result := 8443
  else
    Result := 0;
end;

function StemmaAddress: String;
begin
  if SkipTailscale then
    Result := 'http://127.0.0.1:' + LocalPort + ' (só neste PC, sem o Tailscale)'
  else if ChosenHttpsPort = 443 then
    Result := 'https://' + TsHost
  else
    Result := 'https://' + TsHost + ':' + IntToStr(ChosenHttpsPort);
end;

procedure ShowFinished; forward;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = TailscalePage.ID then
    RefreshTailscale
  else if (CurPageID = wpReady) and IsUpdate then
    WizardForm.NextButton.Caption := 'Atualizar'
  else if CurPageID = wpFinished then
    ShowFinished;
end;

{ --- espaço em disco ------------------------------------------------------------ }

function FormatMB(MB: Int64): String;
begin
  if MB >= 1024 then
    Result := IntToStr(MB div 1024) + ',' + IntToStr((MB mod 1024) * 10 div 1024) + ' GB'
  else
    Result := IntToStr(MB) + ' MB';
end;

{ Espaço livre (MB) no drive de um caminho que pode ainda não existir; -1 se não der para saber. }
function FreeMB(const Path: String): Int64;
var
  Free, Total: Int64;
begin
  Result := -1;
  if GetSpaceOnDisk64(AddBackslash(ExtractFileDrive(Path)), Free, Total) then
    Result := Free div (1024 * 1024);
end;

function DataRootChoice: String;
begin
  if IsUpdate then
    Result := CheckDataRoot
  else
    Result := Trim(DataPage.Values[0]);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Need, Free: Int64;
begin
  Result := True;
  if CurPageID = DataPage.ID then
  begin
    { A raiz de um drive não: o desinstalador apagaria o drive inteiro com "apagar os dados". }
    if RemoveBackslash(Trim(DataPage.Values[0])) = RemoveBackslash(ExtractFileDrive(Trim(DataPage.Values[0]))) then
    begin
      SuppressibleMsgBox('Escolha uma pasta para os dados (ex.: D:\stemma-data), não a raiz do drive.', mbError, MB_OK, IDOK);
      Result := False;
    end;
  end
  else if CurPageID = TailscalePage.ID then
  begin
    { Atualização pelo app (silenciosa): o Tailscale fora do ar não impede atualizar. }
    if (TsState <> 'ready') and not (WizardSilent and IsUpdate) then
    begin
      SuppressibleMsgBox('Termine a configuração do Tailscale antes de continuar.', mbInformation, MB_OK, IDOK);
      Result := False;
    end;
  end
  else if CurPageID = wpReady then
  begin
    if (not IsUpdate) and (not SkipTailscale) and (ChosenHttpsPort = 0) then
    begin
      SuppressibleMsgBox('Os dois endereços HTTPS do Tailscale deste PC (portas 443 e 8443) já são usados por outros apps.' + #13#10#13#10 +
        'Libere um deles (por exemplo: tailscale serve --https=8443 off) e rode o instalador de novo.', mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
    { Falta espaço no drive da raiz: não começa (pararia no meio do download). }
    Need := StrToInt64Def(NeedRootMB, 0);
    Free := FreeMB(GetRoot(''));
    if (Need > 0) and (Free >= 0) and (Free < Need) then
    begin
      SuppressibleMsgBox('Falta espaço em ' + ExtractFileDrive(GetRoot('')) + ': o Stemma precisa de ~' + FormatMB(Need) +
        ' e há ' + FormatMB(Free) + ' livres.' + #13#10#13#10 + 'Libere espaço e clique em Instalar de novo.', mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
    Free := FreeMB(DataRootChoice);
    if (Free >= 0) and (Free < 2048) then
      Result := SuppressibleMsgBox('O drive dos dados (' + ExtractFileDrive(DataRootChoice) + ') tem só ' + FormatMB(Free) +
        ' livres. Cada música ocupa ~50 MB, então cabem poucas.' + #13#10#13#10 + 'Continuar assim mesmo?',
        mbConfirmation, MB_YESNO, IDYES) = IDYES;
  end;
end;

{ Tela "Pronto para instalar": o que vai acontecer, quanto vai baixar e o espaço. }
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  Download, Need: Int64;
  Root, Data: String;
begin
  Root := GetRoot('');
  Data := DataRootChoice;
  Download := StrToInt64Def(DownloadMB, -1);
  Need := StrToInt64Def(NeedRootMB, -1);

  if IsUpdate then
    Result := 'Atualizar o Stemma ' + Installed + ' para a v{#AppVersion}.' + NewLine +
      Space + 'O Stemma fica fora do ar por cerca de 1 minuto. Se algo der errado, a versão atual volta sozinha.' + NewLine
  else
  begin
    Result := 'Instalar o Stemma {#AppVersion} em ' + Root + ', com os dados em ' + Data + '.' + NewLine +
      NewLine + 'Endereço' + NewLine + Space + StemmaAddress + NewLine;
    if (not SkipTailscale) and (ChosenHttpsPort = 8443) then
      Result := Result + Space + 'O endereço sem porta já é de outro app deste PC, que continua funcionando.' + NewLine;
  end;

  Result := Result + NewLine + 'Download' + NewLine;
  if Download < 0 then
    Result := Result + Space + 'Até ~3 GB, se os componentes ainda não estiverem neste PC.' + NewLine
  else if Download < 100 then
    Result := Result + Space + 'Quase nada (' + FormatMB(Download) + '): os componentes já estão neste PC.' + NewLine +
      Space + 'Tempo estimado: ~3 minutos.' + NewLine
  else
    Result := Result + Space + '~' + FormatMB(Download) + ' de componentes que ainda não estão neste PC.' + NewLine +
      Space + 'Tempo estimado: ~3 minutos mais o download (~' + IntToStr(Download div 300 + 1) + ' min a 5 MB/s).' + NewLine;

  Result := Result + NewLine + 'Espaço em disco' + NewLine;
  if Need >= 0 then
    Result := Result + Space + ExtractFileDrive(Root) + ' (programa e componentes): precisa de ~' + FormatMB(Need) +
      ', livre ' + FormatMB(FreeMB(Root)) + '.' + NewLine
  else
    Result := Result + Space + ExtractFileDrive(Root) + ' (programa e componentes): livre ' + FormatMB(FreeMB(Root)) + '.' + NewLine;
  Result := Result + Space + ExtractFileDrive(Data) + ' (dados): livre ' + FormatMB(FreeMB(Data)) + '.' + NewLine +
    Space + 'Cada música ocupa ~50 MB (de 40 a 100 MB), mais 80 MB do modelo de separação, uma vez.' + NewLine;
end;

{ --- instalação ---------------------------------------------------------------- }

procedure RunInstall;
var
  Params, Zip: String;
  ResultCode: Integer;
begin
  Zip := ExpandConstant('{app}\payload\{#ZipName}');
  Params := '-ZipPath ' + Quote(Zip) + ' -QrPath ' + Quote(ExpandConstant('{app}\qr.bmp'));
  if IsUpdate then
  begin
    if HasFlag('SIMULATEFAILURE') then
      Params := Params + ' -SimulateFailure';
    Params := EngineParams(ExpandConstant('{app}\engine\setup.ps1'), 'Update', Params);
  end
  else
    Params := EngineParams(ExpandConstant('{app}\engine\setup.ps1'), 'Install',
      Params + ' -DataRoot ' + Quote(Trim(DataPage.Values[0])) + ' -Port ' + LocalPort +
      ' -HttpsPort ' + IntToStr(ChosenHttpsPort));

  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Min := 0;
  WizardForm.ProgressGauge.Max := 1000;
  WizardForm.ProgressGauge.Position := 0;
  ErrorText := '';
  StageText := '';
  ProgressValue := 0;
  LastStep := 'Preparando…';
  WizardForm.StatusLabel.Caption := LastStep;
  WizardForm.FilenameLabel.Caption := '';
  Succeeded := ExecAndLogOutput(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated,
    ResultCode, @OnEngineLog) and (ResultCode = 0);
  if Succeeded then
    WizardForm.ProgressGauge.Position := 1000;
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
    '--root ' + Quote(GetRoot('')) + ' --service ' + Quote(ServiceId), '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

{ /RESULTFILE= (atualização pelo app): o resultado numa linha, para a tarefa agendada gravar no banco. }
procedure WriteResultFile;
var
  Path: String;
  Lines: TArrayOfString;
begin
  Path := ExpandConstant('{param:RESULTFILE|}');
  if Path = '' then
    Exit;
  SetArrayLength(Lines, 1);
  if Succeeded then
    Lines[0] := 'ok|' + ResultVersion
  else
    Lines[0] := 'erro|' + ErrorText;
  SaveStringsToUTF8File(Path, Lines, False);
end;

{ Código de saída 1 quando o motor falhou (o assistente chega ao fim mostrando o erro). }
function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if not Succeeded then
    Result := 1;
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
    WriteResultFile;
    { Ícone na bandeja, como o usuário (não elevado). Numa falha também: ele mostra o estado. }
    if (Installed + ResultVersion <> '') and not NoTray then
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
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + Quote(ExpandConstant('{app}\engine\setup.ps1')) +
    ' -Mode Uninstall -Root ' + Quote(Root) + ' -Keep setup';
  if (DataRoot <> '') and DirExists(DataRoot) then
    if SuppressibleMsgBox('Apagar também os dados do Stemma (músicas, stems, exportações e banco)?' + #13#10#13#10 +
      DataRoot + #13#10#13#10 + 'Escolha Não para manter (padrão).', mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
      Params := Params + ' -RemoveData';
  if not Exec(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    SuppressibleMsgBox('A remoção do serviço ou das pastas não terminou (código ' + IntToStr(ResultCode) +
      '). O log fica em %TEMP%\setup-uninstall-*.log.', mbError, MB_OK, IDOK);
end;

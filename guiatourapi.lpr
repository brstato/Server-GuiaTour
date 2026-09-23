program guiatourapi;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cmem,
  cthreads,
  cwstring,
  {$ENDIF}
  Classes, SysUtils,
  { you can add units after this }
  udata, uconfig, usecurityservice, uNetService, ugetdata, uJsonView,
  uguiatourview, CustApp, urouter, uTlogincontroller, utlojacontroller,
  uportifoliocontroller, uloginmodel, ulojamodel, uportifoliomodel,
  uvendedormodel, Horse
  ;

type

  { TGuiaTourAPI }

  TGuiaTourAPI = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

{ TGuiaTourAPI }
var
index_html: string;

procedure CarregarIndexMemoria;
var
  SL: TStringList;
  CaminhoArquivo: string;
begin
  // Aponta para o index.html na mesma pasta do executável (ou ajuste o caminho)
  CaminhoArquivo := ExtractFilePath(ParamStr(0)) + 'index.html';

  if FileExists(CaminhoArquivo) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(CaminhoArquivo);
      index_html := SL.Text;
    finally
      SL.Free;
    end;
  end
  else
    index_html := '<h1>Erro: index.html não encontrado no servidor.</h1>';
end;

procedure TGuiaTourAPI.DoRun;
var
  ErrorMsg: String;
begin
  // quick check parameters
  ErrorMsg:=CheckOptions('h', 'help');
  if ErrorMsg<>'' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h', 'help') then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  try
     WriteLn('GuiaTour');
     tAppRouter.load_routes();
     WriteLn('--------------------');
     WriteLn('Rotas carregadas');
     WriteLn('--------------------');
     CarregarIndexMemoria;
     WriteLn('Index carregado');
     WriteLn('--------------------');
     WriteLn('Servidor escutando na porta: 8100');
     WriteLn('--------------------');
     THorse.Listen(8100);
  except on e:exception do
     WriteLn('Erro ao iniciar: ' + e.Message);
  end;
  // stop program loop
  Terminate;
end;

constructor TGuiaTourAPI.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
end;

destructor TGuiaTourAPI.Destroy;
begin
  inherited Destroy;
end;

procedure TGuiaTourAPI.WriteHelp;
begin
  { add your help code here }
  writeln('Usage: ', ExeName, ' -h');
end;

var
  Application: TGuiaTourAPI;
begin
  Application:=TGuiaTourAPI.Create(nil);
  Application.Title:='Guia Tour';
  Application.Run;
  Application.Free;
end.


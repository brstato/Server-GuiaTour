unit udata;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  uconfig,
  IBConnection,
  ZConnection,
  ZDataset,
  ZConnectionGroup,
  ZGroupedConnection,
  LazJWT,
  Horse.JWT,
  fpjson,
  StrUtils;

type

  { TDataModule1 }

  TDataModule1 = class(TDataModule)
    ZConnection1: TZConnection;
    ZConnectionGroup1: TZConnectionGroup;
    ZGroupedConnection1: TZGroupedConnection;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
  public
    class function GetIdLoja(const auth: String): String;
    const token: string = '99617610add82b83fdf8b5c8f42b1ddf6d4d866b7a95f330b403900ec946e554';
  end;

var
  DataModule1: TDataModule1;


implementation

{$R *.lfm}

{ TDataModule1 }

class function TDataModule1.GetIdLoja(const auth: String): String;
var
  tokenSTR: string;
  Laz: ILazJWT;
  PayloadData: TJSONData;
begin
  Result := '';
  tokenSTR:= StringReplace(auth, 'Bearer ', '', [rfReplaceAll, rfIgnoreCase]);

  if tokenSTR <> '' then
  begin
    try
      laz := TLazJWT.New.UseCustomPayLoad(True).Token(tokenSTR);
      PayloadData := Laz.CustomPayLoad;

      if Assigned(PayloadData) and (PayloadData.JSONType = jtObject) then
        Result := TJSONObject(PayloadData).Get('id', '');
    except
      Result := '';
    end;
  end;
end;





procedure TDataModule1.DataModuleDestroy(Sender: TObject);
begin
  ZConnection1.Disconnect;
end;

procedure TDataModule1.DataModuleCreate(Sender: TObject);
var
  database:string;
begin
  //token := '';

  //database:='base_dev';
  database:='base';

  try
    ZConnection1.Database:=database;
    //ZConnection1.HostName:='127.0.0.1';
    ZConnection1.HostName:='100.72.176.93';
    ZConnection1.Properties.Add('ConnectionTimeout=60');
    ZConnection1.Properties.Add('MaxConnections=20');
    ZConnection1.Properties.Add('RawStringEncoding=DB_CP');
    ZConnection1.Properties.Add('Wait=True');
    ZConnection1.Connect;


    //token := trim(tconfig.ConfigValue('token', 'token', ''));
  except
    on E: Exception do
      WriteLn('Erro ao conectar ao banco (' + database + '): ' + E.Message);
  end;

end;

end.


unit uTlogincontroller;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  Horse,
  uloginmodel,
  uJsonView,
  udata,
  uNetService,
  fpjson,
  jsonscanner,
  Horse.JWT
  ;

type
  TLoginController = class
  private

  public
    class procedure RegisterRoutes();
  end;

implementation

procedure HandleRefreshToken(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  TokenData, RequestJson: TJSONObject;
  uuid, refreshToken: string;
  StringError: TStringList;
  status: integer;
begin
  status:=401;
  RequestJson := nil;
  TokenData := nil;

  try
    try
      try
        if Trim(req.Body) = '' then
        begin
          TJsonView.SendResponse(Res, TJSONObject(GetJSON('{"message":"Corpo da requisição está vazio."}')), 400);
          Exit;
        end;
        RequestJson := TJSONObject(GetJSON(req.Body));
      except on e:EScannerError do
      begin
        TJsonView.SendResponse(Res, TJSONObject(GetJSON('{"message":"JSON malformado."}')), 400);
      end;
      end;

      refreshToken := RequestJson.get('r_token', '');
      uuid         := RequestJson.get('uuid', ''   );

      if (refreshToken = '') or (uuid = '') then
         exit;

      TokenData := TJSONObject(GetJSON(TLoginModel.updateRefreshToken(refreshToken, uuid)));

      status:=TokenData.Find('status').AsInteger;

      TJsonView.SendResponse(Res, TokenData, status);

    except on e:Exception do
      begin
        StringError:= TStringList.Create;
        try
          StringError.Add(e.Message);
        finally
          StringError.Free;
        end;
      end;
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
    if Assigned(TokenData  ) then TokenData.Free;
  end;
end;


procedure HandleLogin_Google(req: THorseRequest; res: THorseResponse);
var
  RequestJson, LoginData: TJSONObject;
  Email, GoogleToken, nome, ads_id, r_token, response, GoogleCode: string;
  status: integer;
begin
  try
    try
      RequestJson := TJSONObject(GetJSON(Req.Body));

      //nome        := RequestJson.Find('g_name' ).AsString;
      //Email       := RequestJson.Find('g_email').AsString;
      //GoogleToken := RequestJson.Find('g_token').AsString;
      GoogleCode := RequestJson.get('g_code',  '');
      r_token    := RequestJson.get('r_token', '');

      if GoogleCode = '' then
      begin
        TJsonView.SendError(Res, 400, 'Código de autorização ausente.');
        Exit;
      end;

      LoginData := TJSONObject(
        GetJSON(
          TLoginModel.LoginGoogle(GoogleCode, status, r_token)
        )
      );

      TJsonView.SendResponse(Res, LoginData, status);

    except
      on E: Exception do
        TJsonView.SendError(Res, 500, e.Message);
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
    //if Assigned(LoginData) then LoginData.Free;
  end;

end;

class procedure TLoginController.RegisterRoutes();
begin
  THorse.Post('/api/v1/token/refresh', HandleRefreshToken);
  THorse.post('/api/v1/login_google', HandleLogin_Google);
end;

end.

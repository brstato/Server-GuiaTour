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
  lJSONData: TJSONData;
  uuid, refreshToken: string;
  status: integer;
begin
  RequestJson := nil;
  TokenData := nil;
  try
    try
      if Trim(req.Body) = '' then
      begin
        TJsonView.SendError(Res, 400, 'Corpo da requisição está vazio.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if lJSONData.JSONType <> jtObject then
      begin
        lJSONData.Free;
        TJsonView.SendError(Res, 400, 'JSON inválido.');
        Exit;
      end;
      RequestJson := TJSONObject(lJSONData);

      refreshToken := RequestJson.Get('r_token', '');
      uuid         := RequestJson.Get('uuid', '');

      if (refreshToken = '') or (uuid = '') then
      begin
        TJsonView.SendError(Res, 401, 'Sessão inválida.');
        Exit;
      end;

      TokenData := TJSONObject(GetJSON(TLoginModel.updateRefreshToken(refreshToken, uuid)));
      status := StrToIntDef(TokenData.Get('status', '401'), 401);

      TJsonView.SendResponse(Res, TokenData, status);
    except
      on e: Exception do
        TJsonView.SendErroInterno(Res, 'HandleRefreshToken', e);
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
    if Assigned(TokenData) then TokenData.Free;
  end;
end;


procedure HandleLogin_Google(req: THorseRequest; res: THorseResponse);
var
  RequestJson, LoginData: TJSONObject;
  Email, GoogleToken, nome, ads_id, r_token, response, GoogleCode: string;
  status: integer;
  lJSONData: TJSONData;
begin
  RequestJson := nil;
  LoginData := nil;
  try
    try
      lJSONData := GetJSON(Req.Body);
      if lJSONData.JSONType <> jtObject then
      begin
        lJSONData.Free;
        TJsonView.SendError(Res, 400, 'JSON inválido.');
        Exit;
      end;
      RequestJson := TJSONObject(lJSONData);

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
        TJsonView.SendErroInterno(Res, 'utlogincontroller', e);
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
    if Assigned(LoginData) then LoginData.Free;   // SendResponse não libera o objeto
  end;

end;

class procedure TLoginController.RegisterRoutes();
begin
  THorse.Post('/api/v1/token/refresh', HandleRefreshToken);
  THorse.post('/api/v1/login_google', HandleLogin_Google);
end;

end.

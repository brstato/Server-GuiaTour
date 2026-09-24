unit uloginmodel;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  BCrypt,
  sql_queries,
  uconfig,
  udata,
  fpjson,
  LazJWT,
  DateUtils,
  db,
  ugetdata,
  uNetService,
  ulojamodel,
  jsonparser,
  RESTRequest4D;

type
  TLoginDados = Record
    id,
    refreshToken,
    token,
    Url,
    vencimento,
    agora: string;
    expire: integer;
    bloqueado: boolean;
    dataValidade: TDateTime;
  end;

type
  TReturn = Record
    jsonString: string;
    json: TJSONObject;
    valido: Boolean;
  end;

type
  { TLoginModel }

  TLoginModel = Class
  private
      const GoogleCheckUrl: string = 'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=';
      class function TrocarCodeEEmailGoogle(const g_code: string;
              out g_mail, g_name: string; out status_code: integer): Boolean;      
    public
      class function updateRefreshToken(r_token, id: string):UTF8String;
      class function updateJWT(uuid: string; tipo: string = 'loja'): string;
      class function LoginGoogle(const g_code: string; out status_code: integer;
              r_token: string = ''): UTF8String;
      class function LoginGoogleVendedor(const g_code: string;
              out status_code: integer; r_token: string = ''): UTF8String;              
  end;

implementation


class function TLoginModel.TrocarCodeEEmailGoogle(const g_code: string;
        out g_mail, g_name: string; out status_code: integer): Boolean;
var
  JsonTokenReq, GoogleTokenRes, GoogleUserRes: TJSONObject;
  AccessToken: string;
  TokenResponse, UserInfoResponse: IResponse;
begin
  Result := False;
  g_mail := '';
  g_name := '';
  GoogleTokenRes := nil;
  GoogleUserRes  := nil;

  // -------------------------------------------------------------------------
  // ETAPA 1: Trocar o g_code pelo Access Token (Validação de Segurança)
  // -------------------------------------------------------------------------
  JsonTokenReq := TJSONObject.Create;
  try
    JsonTokenReq.Add('client_id',     TConfig.ConfigValue('google', 'client_id',     ''));
    JsonTokenReq.Add('client_secret', TConfig.ConfigValue('google', 'client_secret', ''));
    JsonTokenReq.Add('code',          g_code);
    JsonTokenReq.Add('grant_type',    'authorization_code');
    JsonTokenReq.Add('redirect_uri',  'postmessage'); // DEVE ser idêntico ao do frontend

    TokenResponse := TRequest.New.BaseURL('https://oauth2.googleapis.com/token')
      .ContentType('application/json')
      .AddBody(JsonTokenReq.AsJSON)
      .Post;

    if TokenResponse.StatusCode <> 200 then
    begin
      status_code := 401;
      Exit(False);
    end;

    GoogleTokenRes := TJSONObject(GetJSON(TokenResponse.Content));
    AccessToken := GoogleTokenRes.Get('access_token', '');
  finally
    JsonTokenReq.Free;
    if Assigned(GoogleTokenRes) then GoogleTokenRes.Free;
  end;

  // -------------------------------------------------------------------------
  // ETAPA 2: Obter dados do usuário (Email e Nome) com o Access Token
  // -------------------------------------------------------------------------
  UserInfoResponse := TRequest.New.BaseURL('https://www.googleapis.com/oauth2/v2/userinfo')
    .AddHeader('Authorization', 'Bearer ' + AccessToken)
    .Get;

  if UserInfoResponse.StatusCode <> 200 then
  begin
    status_code := 401;
    Exit(False);
  end;

  GoogleUserRes := TJSONObject(GetJSON(UserInfoResponse.Content));
  try
    g_mail := GoogleUserRes.Get('email', '');
    g_name := GoogleUserRes.Get('name', '');
  finally
    GoogleUserRes.Free;
  end;

  Result := g_mail <> '';
  if not Result then
    status_code := 401;
end;


function createRefreshToken: string;
var
   uuid: TGuid;
begin
  CreateGUID(uuid);
  Result := TBCrypt.GenerateHash(GUIDToString(uuid));
end;


class function TLoginModel.updateRefreshToken(r_token, id: string): UTF8String;
var
   queryData: TDataSet;
   refreshToken, token: string;
   jsonData: TJSONObject;
   recordcount, expire, agora: integer;

begin

   jsonData:=TJSONObject.Create;

   token:=updateJWT(id);
   refreshToken:=createRefreshToken;

   try
     queryData := TGetData.getData(
       sql_queries.verify_refresh_token,
       [r_token, id],
       True
     );

     recordcount:=queryData.RecordCount;

     expire:=queryData.FieldByName('expire').AsInteger;
     agora:=DateTimeToUnix(now);

     if (queryData.RecordCount = 1)  and
       (queryData.FieldByName('expire').AsInteger >= DateTimeToUnix(now)) then
     begin
      TGetData.getData(
        sql_queries.update_refresh_token,
        [
          refreshToken,
          DateTimeToUnix(IncMonth(now, 1)),
          id
        ],
        False
      );
       jsonData.Add('r_token',refreshToken);
       jsonData.Add('token', token);
       jsonData.Add('status','200');
     end
     else
     begin
       jsonData.Add('r_token','');
       jsonData.Add('token', '');
       jsonData.Add('status','401');
     end;
   finally
     queryData.Free;
     Result:=jsonData.AsJSON;
     jsonData.Free;
     //Result.jsonString:=refreshToken;
     //Result.json:=jsonData;
   end;
end;


class function TLoginModel.updateJWT(uuid: string; tipo: string = 'loja'): string;
var
   tokenString: string;
begin
  try
    tokenString := TLazJWT.New
           .SecretJWT(TConfig.Token)
           .Exp(DateTimeToUnix(IncHour(now, 1)))
           .AddClaim('id', uuid)
           .AddClaim('tipo', tipo)
           .AddClaim('Exp', DateTimeToUnix(IncMonth(now, 1)))
           .Token;

  finally
    Result:=tokenString;
  end;
end;


class function TLoginModel.LoginGoogle(const g_code: string; out status_code:
        integer; r_token: string = ''): UTF8String;
var
   dataset: TDataSet;
   jsonObject, JsonData, JsonTokenReq, GoogleTokenRes, GoogleUserRes: TJSONObject;
   LoginDados: TLoginDados;
   AccessToken, g_mail, g_name: string;
   TokenResponse, UserInfoResponse: IResponse;
begin
     LoginDados.bloqueado := false;
     jsonObject := TJSONObject.Create;
     try
       if not TrocarCodeEEmailGoogle(g_code, g_mail, g_name, status_code) then
       begin
         jsonObject.Add('message', 'Falha ao autenticar com o Google.');
         Exit(jsonObject.AsJSON);
       end;

       // ETAPA 3 em diante: igual ao que já existia (busca/cria loja pelo e-mail...)
       JsonData := TJSONObject.Create;
       try
         dataset := TGetData.getData('SELECT uuid, validade FROM loja WHERE email = :email', [g_mail], True);

         if dataset.IsEmpty then
         begin
           LoginDados.Id := TLojaModel.createloja(g_name, g_mail);
           jsonObject.Add('status', '200');
         end
         else
         begin
           LoginDados.Id := dataset.FieldByName('uuid').AsString;
           if DateOf(dataset.FieldByName('validade').AsDateTime) < DateOf(Now) then
           begin
             jsonObject.Add('status', '403');
             status_code := 403;
             LoginDados.Bloqueado := true;
           end
           else
             jsonObject.Add('status', '200');
         end;

         if not LoginDados.Bloqueado then
         begin
           JsonData.Add('id', LoginDados.Id);

           LoginDados.RefreshToken := createRefreshToken;
           LoginDados.Expire := DateTimeToUnix(IncMonth(Now, 1));

           TGetData.getData(
             'update loja set refresh_token = :token, expire = :expire, '+
             'google_refresh_token = :r_token where uuid = :uuid;',
             [LoginDados.RefreshToken, LoginDados.Expire, r_token, LoginDados.Id]
           );

           LoginDados.Token := updateJWT(LoginDados.Id);

           jsonObject.Add('token',    LoginDados.Token);
           jsonObject.Add('r_token',  LoginDados.RefreshToken);
           jsonObject.Add('message',  JsonData);
           jsonObject.Add('id_loja',  LoginDados.Id);

           status_code := 200;
         end;
       finally
         dataset.Free;
       end;

       Result := jsonObject.AsJSON;
     finally
       jsonObject.Free;
     end;
end;

class function TLoginModel.LoginGoogleVendedor(const g_code: string;
        out status_code: integer; r_token: string = ''): UTF8String;
var
   dataset: TDataSet;
   jsonObject, JsonTokenReq, GoogleTokenRes, GoogleUserRes: TJSONObject;
   AccessToken, g_mail, g_name: string;
   TokenResponse, UserInfoResponse: IResponse;
   idVendedor, refreshToken: string;
   token: string;
   expire: integer;
begin
     jsonObject := TJSONObject.Create;
     status_code := 401;
     try
       // Etapas 1 e 2 são idênticas ao LoginGoogle (trocar g_code por access_token,
       // buscar e-mail) — extraia para uma função privada compartilhada
       // TrocarCodeEEmailGoogle(g_code, AccessToken, g_mail) pra não duplicar.
       if not TrocarCodeEEmailGoogle(g_code, g_mail, g_name, status_code) then
       begin
         jsonObject.Add('message', 'Falha ao autenticar com o Google.');
         Exit(jsonObject.AsJSON);
       end;

       // Diferença chave: SEM auto-criação. Só quem já está cadastrado
       // manualmente em VENDEDOR, e ATIVO, consegue logar.
       dataset := TGetData.getData(
         'SELECT uuid FROM vendedor WHERE email = :email AND ativo = TRUE',
         [g_mail], True
       );

       if dataset.IsEmpty then
       begin
         status_code := 403;
         jsonObject.Add('message', 'E-mail não autorizado como vendedor.');
         Exit(jsonObject.AsJSON);
       end;

       idVendedor := dataset.FieldByName('uuid').AsString;
       refreshToken := createRefreshToken;
       expire := DateTimeToUnix(IncMonth(Now, 1));

       TGetData.getData(
         'update vendedor set refresh_token = :token, expire = :expire where uuid = :uuid;',
         [refreshToken, expire, idVendedor]
       );

       token := updateJWT(idVendedor, 'vendedor');

       jsonObject.Add('token', token);
       jsonObject.Add('r_token', refreshToken);
       jsonObject.Add('id_vendedor', idVendedor);
       status_code := 200;

       Result := jsonObject.AsJSON;
     finally
       jsonObject.Free;
     end;
end;

end.


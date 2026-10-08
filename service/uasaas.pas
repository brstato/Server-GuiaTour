unit uasaas;

{$mode objfpc}{$H+}

{
  Cliente da API Asaas v3 para o Guia Tour (Free Pascal, fphttpclient + fpjson).

  Configuração em resources/config.ini (mesmo arquivo do token JWT, já ignorado no git):

    [asaas]
    api_key=$aact_hmlg_...          ; sandbox: $aact_hmlg_  | produção: $aact_prod_
    env=sandbox                     ; sandbox | production
    user_agent=guiatour
    webhook_token=<32 a 255 caracteres, diferente da api_key>
    grace_days=3                    ; tolerância depois do ciclo pago

  Os planos (nome, valor, ciclo) ficam na tabela ASAAS_PLANO (ver asaas_planos.sql).

  Se a chave não estiver no config.ini, cai para a variável de ambiente ASAAS_<CHAVE>
  em maiúsculas (ex.: ASAAS_API_KEY).

  HTTPS: usa opensslsockets (precisa de libssl no servidor Linux).
}

interface

uses
  Classes, SysUtils, DateUtils, fpjson, jsonparser, fphttpclient,
  opensslsockets, uconfig;

type
  EAsaasError = class(Exception)
  public
    HttpStatus: Integer;
    Body: string;
    constructor Create(AStatus: Integer; const ABody, AMsg: string);
  end;

  { TAsaasClient }
  TAsaasClient = class
  private
    FApiKey: string;
    FBaseUrl: string;
    FUserAgent: string;
    function Request(const AMethod, APath: string; ABody: TJSONObject): TJSONObject;
  public
    constructor Create(const AApiKey, ABaseUrl, AUserAgent: string);
    class function FromConfig: TAsaasClient;

    function CreateCustomer(const AName, ACpfCnpj, AEmail, AMobilePhone,
      AExternalReference: string): TJSONObject;
    // ABillingType: BOLETO | CREDIT_CARD | PIX | UNDEFINED (cliente escolhe na fatura)
    // ANextDueDate: yyyy-mm-dd
    function CreateSubscription(const ACustomerId, ABillingType: string;
      AValue: Double; const ANextDueDate, ACycle, ADescription,
      AExternalReference: string): TJSONObject;
    function CancelSubscription(const AId: string): TJSONObject;
    function ListSubscriptionPayments(const AId: string): TJSONObject;
    // QR Code Pix da cobrança: encodedImage (base64), payload (copia e cola), expirationDate
    function GetPixQrCode(const APaymentId: string): TJSONObject;
  end;

{ Configuração }
function AsaasCfg(const AName, ADefault: string): string;
function AsaasCfgFloat(const AName: string; ADefault: Double): Double;
function AsaasCfgInt(const AName: string; ADefault: Integer): Integer;

{ Helpers JSON / texto / data (compartilhados com o model e o controller) }
function JsonStr(AObj: TJSONObject; const AName: string): string;
function JsonNum(AObj: TJSONObject; const AName: string): Double;
function JsonObj(AObj: TJSONObject; const AName: string): TJSONObject;
function IsoToDate(const S: string): TDateTime;          // 'yyyy-mm-dd' -> data (0 se inválido)
function DateToIso(ADate: TDateTime): string;
function OnlyDigits(const S: string): string;
function NormalizaCelular(const S: string): string;      // 10/11 dígitos ou ''
function SafeEquals(const A, B: string): Boolean;        // tempo constante
// Data em que termina o ciclo que começa em ADueDate (usa o calendário: 15/01 -> 15/02, 31/01 -> 28/02)
function FimDoCiclo(ADueDate: TDateTime; const ACycle: string): TDateTime;
function AsaasErrorText(E: EAsaasError): string;

implementation

constructor EAsaasError.Create(AStatus: Integer; const ABody, AMsg: string);
begin
  inherited Create(AMsg);
  HttpStatus := AStatus;
  Body := ABody;
end;

{ ---------------------------------------------------------------- configuração }

function AsaasCfg(const AName, ADefault: string): string;
begin
  Result := TConfig.ConfigValue('asaas', AName, '');
  if Result = '' then
    Result := GetEnvironmentVariable('ASAAS_' + UpperCase(AName));
  if Result = '' then
    Result := ADefault;
end;

function AsaasCfgFloat(const AName: string; ADefault: Double): Double;
var
  S: string;
  FS: TFormatSettings;
begin
  Result := ADefault;
  S := AsaasCfg(AName, '');
  if S = '' then Exit;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(S, Result, FS) then
    Result := ADefault;
end;

function AsaasCfgInt(const AName: string; ADefault: Integer): Integer;
begin
  if not TryStrToInt(AsaasCfg(AName, ''), Result) then
    Result := ADefault;
end;

{ ---------------------------------------------------------------------- helpers }

function JsonStr(AObj: TJSONObject; const AName: string): string;
var
  D: TJSONData;
begin
  Result := '';
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType = jtString) then
    Result := D.AsString;
end;

function JsonNum(AObj: TJSONObject; const AName: string): Double;
var
  D: TJSONData;
begin
  Result := 0;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType = jtNumber) then
    Result := D.AsFloat;
end;

function JsonObj(AObj: TJSONObject; const AName: string): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType = jtObject) then
    Result := TJSONObject(D);
end;

function IsoToDate(const S: string): TDateTime;
var
  Y, M, D: Integer;
begin
  Result := 0;
  if Length(S) < 10 then Exit;
  if not TryStrToInt(Copy(S, 1, 4), Y) then Exit;
  if not TryStrToInt(Copy(S, 6, 2), M) then Exit;
  if not TryStrToInt(Copy(S, 9, 2), D) then Exit;
  if not TryEncodeDate(Y, M, D, Result) then Result := 0;
end;

function DateToIso(ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', ADate);
end;

function OnlyDigits(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then
      Result := Result + S[I];
end;

function NormalizaCelular(const S: string): string;
begin
  Result := OnlyDigits(S);
  if (Length(Result) > 11) and (Copy(Result, 1, 2) = '55') then
    Delete(Result, 1, 2);
  if (Length(Result) <> 10) and (Length(Result) <> 11) then
    Result := '';
end;

function SafeEquals(const A, B: string): Boolean;
var
  I, Diff: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then Exit;
  Diff := 0;
  for I := 1 to Length(A) do
    Diff := Diff or (Ord(A[I]) xor Ord(B[I]));
  Result := Diff = 0;
end;

function FimDoCiclo(ADueDate: TDateTime; const ACycle: string): TDateTime;
begin
  if ACycle = 'WEEKLY' then Result := IncDay(ADueDate, 7)
  else if ACycle = 'BIWEEKLY' then Result := IncDay(ADueDate, 14)
  else if ACycle = 'MONTHLY' then Result := IncMonth(ADueDate, 1)
  else if ACycle = 'BIMONTHLY' then Result := IncMonth(ADueDate, 2)
  else if ACycle = 'QUARTERLY' then Result := IncMonth(ADueDate, 3)
  else if ACycle = 'SEMIANNUALLY' then Result := IncMonth(ADueDate, 6)
  else if ACycle = 'YEARLY' then Result := IncMonth(ADueDate, 12)
  else Result := IncMonth(ADueDate, 1);
end;

// Mensagem que vai para o painel. Só a "description" de erro de validação (HTTP 400)
// é mostrada ao lojista; o resto (chave inválida, HTML de 502...) fica só no log.
function AsaasErrorText(E: EAsaasError): string;
var
  D: TJSONData;
  Arr: TJSONArray;
  descricao: string;
begin
  Result := 'Falha no provedor de pagamento. Tente novamente em instantes.';
  if E.HttpStatus <> 400 then Exit;
  D := nil;
  try
    D := GetJSON(E.Body);
    if D is TJSONObject then
    begin
      if TJSONObject(D).Find('errors') is TJSONArray then
      begin
        Arr := TJSONArray(TJSONObject(D).Find('errors'));
        if (Arr.Count > 0) and (Arr.Items[0] is TJSONObject) then
        begin
          descricao := JsonStr(TJSONObject(Arr.Items[0]), 'description');
          if descricao <> '' then
            Result := descricao;
        end;
      end;
    end;
  except
    // corpo não é JSON: mantém a mensagem genérica
  end;
  D.Free;
end;

{ --------------------------------------------------------------- TAsaasClient }

constructor TAsaasClient.Create(const AApiKey, ABaseUrl, AUserAgent: string);
begin
  inherited Create;
  FApiKey := AApiKey;
  FBaseUrl := ABaseUrl;
  FUserAgent := AUserAgent;
end;

class function TAsaasClient.FromConfig: TAsaasClient;
var
  Key, Base: string;
begin
  Key := AsaasCfg('api_key', '');
  if Key = '' then
    raise Exception.Create('Asaas: api_key não configurada no config.ini [asaas]');

  if LowerCase(AsaasCfg('env', 'sandbox')) = 'production' then
    Base := 'https://api.asaas.com/v3'
  else
    Base := 'https://api-sandbox.asaas.com/v3';

  Result := TAsaasClient.Create(Key, Base, AsaasCfg('user_agent', 'guiatour'));
end;

function TAsaasClient.Request(const AMethod, APath: string;
  ABody: TJSONObject): TJSONObject;
var
  Http: TFPHTTPClient;
  Resp: TStringStream;
  Payload: TStringStream;
  Txt: string;
  Data: TJSONData;
begin
  Result := nil;
  Http := TFPHTTPClient.Create(nil);
  Resp := TStringStream.Create('');
  Payload := nil;
  try
    Http.ConnectTimeout := 10000;
    Http.IOTimeout := 20000;
    Http.AllowRedirect := False;
    Http.AddHeader('access_token', FApiKey);
    Http.AddHeader('User-Agent', FUserAgent);
    Http.AddHeader('Content-Type', 'application/json');
    Http.AddHeader('Accept', 'application/json');

    if ABody <> nil then
    begin
      Payload := TStringStream.Create(ABody.AsJSON);
      Http.RequestBody := Payload;
    end;

    // 4xx/5xx também precisam ser lidos: o Asaas devolve "errors" no corpo
    Http.HTTPMethod(AMethod, FBaseUrl + APath, Resp,
      [200, 201, 400, 401, 403, 404, 409, 429, 500, 502, 503]);

    Txt := Resp.DataString;

    if (Http.ResponseStatusCode < 200) or (Http.ResponseStatusCode > 299) then
      raise EAsaasError.Create(Http.ResponseStatusCode, Txt,
        Format('Asaas HTTP %d: %s', [Http.ResponseStatusCode, Txt]));

    if Trim(Txt) = '' then
      Exit(TJSONObject.Create);

    Data := GetJSON(Txt);
    if Data is TJSONObject then
      Result := TJSONObject(Data)
    else
    begin
      Data.Free;
      raise EAsaasError.Create(Http.ResponseStatusCode, Txt,
        'Resposta inesperada do Asaas');
    end;
  finally
    Payload.Free;
    Resp.Free;
    Http.Free;
  end;
end;

function TAsaasClient.CreateCustomer(const AName, ACpfCnpj, AEmail,
  AMobilePhone, AExternalReference: string): TJSONObject;
var
  B: TJSONObject;
begin
  B := TJSONObject.Create;
  try
    B.Add('name', AName);
    B.Add('cpfCnpj', ACpfCnpj);
    if AEmail <> '' then B.Add('email', AEmail);
    if AMobilePhone <> '' then B.Add('mobilePhone', AMobilePhone);
    if AExternalReference <> '' then B.Add('externalReference', AExternalReference);
    Result := Request('POST', '/customers', B);
  finally
    B.Free;
  end;
end;

function TAsaasClient.CreateSubscription(const ACustomerId, ABillingType: string;
  AValue: Double; const ANextDueDate, ACycle, ADescription,
  AExternalReference: string): TJSONObject;
var
  B: TJSONObject;
begin
  B := TJSONObject.Create;
  try
    B.Add('customer', ACustomerId);
    B.Add('billingType', ABillingType);
    B.Add('value', Round(AValue * 100) / 100);
    B.Add('nextDueDate', ANextDueDate);
    B.Add('cycle', ACycle);
    if ADescription <> '' then B.Add('description', ADescription);
    if AExternalReference <> '' then B.Add('externalReference', AExternalReference);
    Result := Request('POST', '/subscriptions', B);
  finally
    B.Free;
  end;
end;

function TAsaasClient.CancelSubscription(const AId: string): TJSONObject;
begin
  Result := Request('DELETE', '/subscriptions/' + AId, nil);
end;

function TAsaasClient.ListSubscriptionPayments(const AId: string): TJSONObject;
begin
  Result := Request('GET', '/subscriptions/' + AId + '/payments', nil);
end;

function TAsaasClient.GetPixQrCode(const APaymentId: string): TJSONObject;
begin
  Result := Request('GET', '/payments/' + APaymentId + '/pixQrCode', nil);
end;

end.

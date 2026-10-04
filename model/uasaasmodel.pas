unit uasaasmodel;

{$mode delphi}{$H+}

{
  Camada de dados da integração Asaas. Usa TGetData (mesmo padrão do resto do projeto):
  parâmetros posicionais, na ordem em que aparecem no SQL, e cada nome de parâmetro
  aparece UMA vez por comando (por isso :V e :V2 no UPDATE da validade).
}

interface

uses
  Classes, SysUtils, Variants, DateUtils, db, fpjson, ugetdata, uasaas;

type
  TLojaAsaas = record
    Found: Boolean;
    Id: Integer;
    Uuid, Nome, Email, Telefone, CustomerId: string;
    Validade: TDateTime; // 0 = sem validade
  end;

  TAssinaturaAsaas = record
    Found: Boolean;
    SubscriptionId, CustomerId, Status, Ciclo: string;
    Valor: Double;
  end;

  { TAsaasModel }

  TAsaasModel = class
  public
    class function GetLoja(const AUuid: string): TLojaAsaas;
    class procedure SalvarCustomerId(ALojaId: Integer; const ACustomerId: string);
    class function UltimaAssinatura(ALojaId: Integer): TAssinaturaAsaas;
    class procedure InserirAssinatura(ALojaId: Integer; const ACustomerId,
      ASubId: string; AValor: Double; const ACiclo: string);
    class procedure SetStatusAssinatura(const ASubId, AStatus: string);
    class procedure UpsertPagamento(APay: TJSONObject);
    class procedure EstenderValidade(const ASubId: string; ADueDate: TDateTime);
    class function EventoProcessado(const AEventId: string): Boolean;
    class procedure RegistrarEvento(const AEventId, ATipo: string);
    class function StatusJson(ALojaId: Integer; AValidade: TDateTime): TJSONObject;
    // Aplica um evento do webhook (PAYMENT_* / SUBSCRIPTION_*)
    class procedure ProcessarEvento(const AEvent: string; ARoot: TJSONObject);
  end;

implementation

{ TAsaasModel }

class function TAsaasModel.GetLoja(const AUuid: string): TLojaAsaas;
var
  ds: TDataSet;
begin
  Result := Default(TLojaAsaas);
  ds := TGetData.getData(
    'SELECT id, uuid, nome, email, telefone, asaas_customer_id, validade ' +
    'FROM loja WHERE uuid = :uuid',
    [AUuid], True);
  try
    if ds.IsEmpty then Exit;
    Result.Found := True;
    Result.Id := ds.FieldByName('id').AsInteger;
    Result.Uuid := ds.FieldByName('uuid').AsString;
    Result.Nome := ds.FieldByName('nome').AsString;
    Result.Email := ds.FieldByName('email').AsString;
    Result.Telefone := ds.FieldByName('telefone').AsString;
    Result.CustomerId := ds.FieldByName('asaas_customer_id').AsString;
    if not ds.FieldByName('validade').IsNull then
      Result.Validade := ds.FieldByName('validade').AsDateTime;
  finally
    ds.Free;
  end;
end;

class procedure TAsaasModel.SalvarCustomerId(ALojaId: Integer;
  const ACustomerId: string);
begin
  TGetData.getData(
    'UPDATE loja SET asaas_customer_id = :c WHERE id = :id',
    [ACustomerId, ALojaId], False);
end;

class function TAsaasModel.UltimaAssinatura(ALojaId: Integer): TAssinaturaAsaas;
var
  ds: TDataSet;
begin
  Result := Default(TAssinaturaAsaas);
  ds := TGetData.getData(
    'SELECT FIRST 1 asaas_subscription_id, asaas_customer_id, status, ciclo, valor ' +
    'FROM asaas_assinatura WHERE loja_id = :l ORDER BY id DESC',
    [ALojaId], True);
  try
    if ds.IsEmpty then Exit;
    Result.Found := True;
    Result.SubscriptionId := ds.FieldByName('asaas_subscription_id').AsString;
    Result.CustomerId := ds.FieldByName('asaas_customer_id').AsString;
    Result.Status := ds.FieldByName('status').AsString;
    Result.Ciclo := ds.FieldByName('ciclo').AsString;
    Result.Valor := ds.FieldByName('valor').AsFloat;
  finally
    ds.Free;
  end;
end;

class procedure TAsaasModel.InserirAssinatura(ALojaId: Integer; const ACustomerId,
  ASubId: string; AValor: Double; const ACiclo: string);
begin
  TGetData.getData(
    'INSERT INTO asaas_assinatura (loja_id, asaas_customer_id, ' +
    'asaas_subscription_id, valor, ciclo, billing_type, status) ' +
    'VALUES (:l, :c, :s, :v, :ci, ''UNDEFINED'', ''PENDENTE'')',
    [ALojaId, ACustomerId, ASubId, AValor, ACiclo], False);
end;

class procedure TAsaasModel.SetStatusAssinatura(const ASubId, AStatus: string);
begin
  TGetData.getData(
    'UPDATE asaas_assinatura SET status = :st, atualizado_em = CURRENT_TIMESTAMP ' +
    'WHERE asaas_subscription_id = :sub',
    [AStatus, ASubId], False);
end;

class procedure TAsaasModel.UpsertPagamento(APay: TJSONObject);
var
  venc, pago: TDateTime;
  vVenc, vPago: Variant;
begin
  if JsonStr(APay, 'id') = '' then Exit;

  venc := IsoToDate(JsonStr(APay, 'dueDate'));
  pago := IsoToDate(JsonStr(APay, 'paymentDate'));
  if venc = 0 then vVenc := Null else vVenc := venc;
  if pago = 0 then vPago := Null else vPago := pago;

  TGetData.getData(
    'UPDATE OR INSERT INTO asaas_pagamento ' +
    '(asaas_payment_id, asaas_subscription_id, valor, vencimento, data_pagamento, ' +
    ' billing_type, status, invoice_url, atualizado_em) ' +
    'VALUES (:id, :sub, :valor, :venc, :pago, :bt, :st, :url, CURRENT_TIMESTAMP) ' +
    'MATCHING (asaas_payment_id)',
    [JsonStr(APay, 'id'), JsonStr(APay, 'subscription'), JsonNum(APay, 'value'),
     vVenc, vPago, JsonStr(APay, 'billingType'), JsonStr(APay, 'status'),
     JsonStr(APay, 'invoiceUrl')], False);
end;

// Validade absoluta = vencimento da cobrança + ciclo + tolerância. Nunca diminui, e
// processar PAYMENT_CONFIRMED e depois PAYMENT_RECEIVED da mesma cobrança dá o mesmo valor.
class procedure TAsaasModel.EstenderValidade(const ASubId: string;
  ADueDate: TDateTime);
var
  ds: TDataSet;
  ciclo: string;
  nova: TDateTime;
begin
  ds := TGetData.getData(
    'SELECT ciclo FROM asaas_assinatura WHERE asaas_subscription_id = :sub',
    [ASubId], True);
  try
    if ds.IsEmpty then Exit;
    ciclo := ds.FieldByName('ciclo').AsString;
  finally
    ds.Free;
  end;

  if ADueDate = 0 then ADueDate := DateOf(Now);
  nova := IncDay(ADueDate, CycleDays(ciclo) + AsaasCfgInt('grace_days', 3));

  TGetData.getData(
    'UPDATE loja SET validade = :v WHERE id = ' +
    '(SELECT loja_id FROM asaas_assinatura WHERE asaas_subscription_id = :sub) ' +
    'AND (validade IS NULL OR validade < :v2)',
    [nova, ASubId, nova], False);
end;

class function TAsaasModel.EventoProcessado(const AEventId: string): Boolean;
var
  ds: TDataSet;
begin
  ds := TGetData.getData(
    'SELECT 1 FROM asaas_evento WHERE event_id = :id', [AEventId], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

class procedure TAsaasModel.RegistrarEvento(const AEventId, ATipo: string);
begin
  TGetData.getData(
    'UPDATE OR INSERT INTO asaas_evento (event_id, tipo) VALUES (:id, :tipo) ' +
    'MATCHING (event_id)',
    [AEventId, ATipo], False);
end;

class function TAsaasModel.StatusJson(ALojaId: Integer;
  AValidade: TDateTime): TJSONObject;
var
  ass: TAssinaturaAsaas;
  ds: TDataSet;
  arr: TJSONArray;
  p: TJSONObject;
begin
  Result := TJSONObject.Create;
  if AValidade = 0 then
    Result.Add('validade', TJSONNull.Create)
  else
    Result.Add('validade', DateToIso(AValidade));

  ass := UltimaAssinatura(ALojaId);
  if not ass.Found then
  begin
    Result.Add('assinatura', TJSONNull.Create);
    Result.Add('status', 'SEM_ASSINATURA');
    Exit;
  end;

  Result.Add('assinatura', ass.SubscriptionId);
  Result.Add('status', ass.Status);
  Result.Add('valor', ass.Valor);
  Result.Add('ciclo', ass.Ciclo);

  arr := TJSONArray.Create;
  ds := TGetData.getData(
    'SELECT FIRST 6 asaas_payment_id, valor, vencimento, data_pagamento, status, ' +
    'invoice_url FROM asaas_pagamento WHERE asaas_subscription_id = :s ' +
    'ORDER BY vencimento DESC',
    [ass.SubscriptionId], True);
  try
    while not ds.Eof do
    begin
      p := TJSONObject.Create;
      p.Add('id', ds.FieldByName('asaas_payment_id').AsString);
      p.Add('valor', ds.FieldByName('valor').AsFloat);
      if ds.FieldByName('vencimento').IsNull then p.Add('vencimento', TJSONNull.Create)
      else p.Add('vencimento', DateToIso(ds.FieldByName('vencimento').AsDateTime));
      if ds.FieldByName('data_pagamento').IsNull then p.Add('pago_em', TJSONNull.Create)
      else p.Add('pago_em', DateToIso(ds.FieldByName('data_pagamento').AsDateTime));
      p.Add('status', ds.FieldByName('status').AsString);
      p.Add('invoice_url', ds.FieldByName('invoice_url').AsString);
      arr.Add(p);
      ds.Next;
    end;
  finally
    ds.Free;
  end;
  Result.Add('cobrancas', arr);
end;

class procedure TAsaasModel.ProcessarEvento(const AEvent: string;
  ARoot: TJSONObject);
var
  pay, sub: TJSONObject;
  subId: string;
begin
  if Copy(AEvent, 1, 8) = 'PAYMENT_' then
  begin
    pay := JsonObj(ARoot, 'payment');
    subId := JsonStr(pay, 'subscription');
    // cobrança avulsa (sem assinatura) não é do Guia Tour: ignora
    if (pay = nil) or (subId = '') then Exit;

    UpsertPagamento(pay);

    // Cartão: CONFIRMED vem na hora e RECEIVED só ~32 dias depois; boleto/Pix: RECEIVED.
    // Liberar em CONFIRMED ou RECEIVED cobre os três meios de pagamento.
    if (AEvent = 'PAYMENT_CONFIRMED') or (AEvent = 'PAYMENT_RECEIVED') then
    begin
      EstenderValidade(subId, IsoToDate(JsonStr(pay, 'dueDate')));
      SetStatusAssinatura(subId, 'ATIVA');
    end
    else if AEvent = 'PAYMENT_OVERDUE' then
      SetStatusAssinatura(subId, 'INADIMPLENTE');
    // PAYMENT_REFUNDED / PAYMENT_CHARGEBACK_*: só ficam registrados em asaas_pagamento.
    // Decida a regra de negócio (revogar validade?) antes de automatizar.
    Exit;
  end;

  if Copy(AEvent, 1, 13) = 'SUBSCRIPTION_' then
  begin
    sub := JsonObj(ARoot, 'subscription');
    subId := JsonStr(sub, 'id');
    if subId = '' then Exit;
    if (AEvent = 'SUBSCRIPTION_DELETED') or (AEvent = 'SUBSCRIPTION_INACTIVATED') then
      SetStatusAssinatura(subId, 'CANCELADA');
  end;
end;

end.

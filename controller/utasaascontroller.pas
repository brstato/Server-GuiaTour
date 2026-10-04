unit utasaascontroller;

{$mode delphi}{$H+}

{
  Rotas:
    POST api/v1/assinatura/checkout   (JWT)  cria cliente + assinatura, devolve link da fatura
    GET  api/v1/assinatura            (JWT)  situação da assinatura, validade e últimas cobranças
    POST api/v1/assinatura/cancelar   (JWT)  cancela a assinatura (acesso segue até a validade)
    POST api/v1/webhooks/asaas        (PÚBLICA) eventos do Asaas, autenticada pelo header
                                      asaas-access-token (config.ini [asaas] webhook_token)

  Quem pode chamar as rotas com JWT:
    - tipo "loja":     age sempre sobre a PRÓPRIA loja (UUID do token); id_loja é ignorado.
    - tipo "vendedor": informa id_loja (UUID) no corpo ou na query e só passa se
                       TVendedorModel.DonoDaLoja(vendedor, loja) for verdadeiro.
  Como a loja vencida leva 403 no login, o caminho normal de cobrança é o vendedor gerar
  o checkout e mandar o invoice_url para o comerciante (WhatsApp).
}

interface

uses
  Classes, SysUtils, Horse, Horse.JWT, fpjson, jsonparser, DateUtils,
  udata, uconfig, uJsonView, uvendedormodel, uasaas, uasaasmodel;

type

  { TAsaasController }

  TAsaasController = class
  public
    class procedure RegisterRoutes();
  end;

implementation

const
  CICLO_PADRAO = 'MONTHLY';

procedure LogAsaas(const AMsg: string);
begin
  WriteLn(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', Now) + ' [asaas] ' + AMsg);
end;

// Descobre qual loja (UUID) a requisição pode operar. False = já respondeu 4xx.
function ResolverLoja(Req: THorseRequest; Res: THorseResponse;
  ABody: TJSONObject; out AUuidLoja: string): Boolean;
var
  auth, tipo, idToken: string;
begin
  Result := False;
  AUuidLoja := '';

  auth := Req.Headers['Authorization'];
  idToken := TDataModule1.GetIdLoja(auth);
  tipo := TDataModule1.GetTipoUsuario(auth);

  if idToken = '' then
  begin
    TJsonView.SendError(Res, 401, 'Não autenticado.');
    Exit;
  end;

  if tipo = 'vendedor' then
  begin
    if ABody <> nil then
      AUuidLoja := ABody.Get('id_loja', '');
    if AUuidLoja = '' then
      AUuidLoja := Req.Query['id_loja'];

    if AUuidLoja = '' then
    begin
      TJsonView.SendError(Res, 400, 'Informe o id_loja.');
      Exit;
    end;
    if not TVendedorModel.DonoDaLoja(idToken, AUuidLoja) then
    begin
      TJsonView.SendError(Res, 403, 'Esta loja não pertence a este vendedor.');
      Exit;
    end;
  end
  else
    AUuidLoja := idToken;

  Result := True;
end;

function ParseBody(Req: THorseRequest): TJSONObject;
var
  d: TJSONData;
begin
  Result := nil;
  if Trim(Req.Body) = '' then Exit;
  try
    d := GetJSON(Req.Body);
  except
    Exit;
  end;
  if d is TJSONObject then
    Result := TJSONObject(d)
  else
    d.Free;
end;

{ ----------------------------------------------------------------- checkout }

procedure HandleCheckout(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  body, cust, subResp, pays, outJson: TJSONObject;
  uuid, cpfCnpj, customerId, subId, invoiceUrl, desc: string;
  loja: TLojaAsaas;
  atual: TAssinaturaAsaas;
  valor: Double;
  vencimento: TDateTime;
  client: TAsaasClient;
  arr: TJSONArray;
begin
  body := ParseBody(Req);
  client := nil;
  try
    if body = nil then
    begin
      TJsonView.SendError(Res, 400, 'JSON inválido.');
      Exit;
    end;

    if not ResolverLoja(Req, Res, body, uuid) then Exit;

    // o valor é do servidor (config.ini), nunca vem do cliente
    valor := AsaasCfgFloat('plan_value', 0);
    if valor <= 0 then
    begin
      LogAsaas('plan_value não configurado');
      TJsonView.SendError(Res, 500, 'Plano não configurado.');
      Exit;
    end;

    cpfCnpj := OnlyDigits(body.Get('cpf_cnpj', ''));
    if (Length(cpfCnpj) <> 11) and (Length(cpfCnpj) <> 14) then
    begin
      TJsonView.SendError(Res, 400, 'Informe um CPF ou CNPJ válido.');
      Exit;
    end;

    try
      loja := TAsaasModel.GetLoja(uuid);
      if not loja.Found then
      begin
        TJsonView.SendError(Res, 404, 'Loja não encontrada.');
        Exit;
      end;

      // evita assinatura duplicada (duplo clique / retry)
      atual := TAsaasModel.UltimaAssinatura(loja.Id);
      if atual.Found and ((atual.Status = 'PENDENTE') or (atual.Status = 'ATIVA')
         or (atual.Status = 'INADIMPLENTE')) then
      begin
        TJsonView.SendError(Res, 409, 'Já existe uma assinatura em andamento.');
        Exit;
      end;

      client := TAsaasClient.FromConfig;

      customerId := loja.CustomerId;
      if customerId = '' then
      begin
        cust := client.CreateCustomer(loja.Nome, cpfCnpj, loja.Email,
          NormalizaCelular(loja.Telefone), loja.Uuid);
        try
          customerId := JsonStr(cust, 'id');
        finally
          cust.Free;
        end;
        if customerId = '' then
          raise Exception.Create('Asaas não retornou o id do cliente');
        TAsaasModel.SalvarCustomerId(loja.Id, customerId);
      end;

      // 1º vencimento = hoje ou o fim da validade atual (não desperdiça o período já pago/teste)
      vencimento := DateOf(Now);
      if (loja.Validade <> 0) and (DateOf(loja.Validade) > vencimento) then
        vencimento := DateOf(loja.Validade);

      desc := AsaasCfg('plan_desc', 'Mensalidade Guia Tour');

      // UNDEFINED: o comerciante escolhe Pix, boleto ou cartão na página da fatura
      subResp := client.CreateSubscription(customerId, 'UNDEFINED', valor,
        DateToIso(vencimento), CICLO_PADRAO, desc, loja.Uuid);
      try
        subId := JsonStr(subResp, 'id');
      finally
        subResp.Free;
      end;
      if subId = '' then
        raise Exception.Create('Asaas não retornou o id da assinatura');

      TAsaasModel.InserirAssinatura(loja.Id, customerId, subId, valor, CICLO_PADRAO);

      // link da primeira fatura (se ainda não existir, o painel consulta GET api/v1/assinatura)
      invoiceUrl := '';
      pays := client.ListSubscriptionPayments(subId);
      try
        if pays.Find('data') is TJSONArray then
        begin
          arr := TJSONArray(pays.Find('data'));
          if (arr.Count > 0) and (arr.Items[0] is TJSONObject) then
          begin
            invoiceUrl := JsonStr(TJSONObject(arr.Items[0]), 'invoiceUrl');
            TAsaasModel.UpsertPagamento(TJSONObject(arr.Items[0]));
          end;
        end;
      finally
        pays.Free;
      end;

      outJson := TJSONObject.Create;
      outJson.Add('assinatura', subId);
      outJson.Add('status', 'PENDENTE');
      outJson.Add('invoice_url', invoiceUrl);
      TJsonView.SendResponseJsonObject(Res, outJson, 201);
    except
      on E: EAsaasError do
      begin
        LogAsaas('checkout loja ' + uuid + ': ' + E.Message);
        TJsonView.SendError(Res, 502, AsaasErrorText(E));
      end;
      on E: Exception do
      begin
        LogAsaas('checkout loja ' + uuid + ': ' + E.Message);
        TJsonView.SendError(Res, 500, 'Falha ao criar assinatura.');
      end;
    end;
  finally
    client.Free;
    body.Free;
  end;
end;

{ ------------------------------------------------------------------ status }

procedure HandleStatus(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  uuid: string;
  loja: TLojaAsaas;
  outJson: TJSONObject;
begin
  if not ResolverLoja(Req, Res, nil, uuid) then Exit;
  try
    loja := TAsaasModel.GetLoja(uuid);
    if not loja.Found then
    begin
      TJsonView.SendError(Res, 404, 'Loja não encontrada.');
      Exit;
    end;
    outJson := TAsaasModel.StatusJson(loja.Id, loja.Validade);
    TJsonView.SendResponseJsonObject(Res, outJson, 200);
  except
    on E: Exception do
    begin
      LogAsaas('status loja ' + uuid + ': ' + E.Message);
      TJsonView.SendError(Res, 500, 'Falha ao consultar assinatura.');
    end;
  end;
end;

{ ---------------------------------------------------------------- cancelar }

procedure HandleCancel(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  body, r: TJSONObject;
  uuid: string;
  loja: TLojaAsaas;
  atual: TAssinaturaAsaas;
  client: TAsaasClient;
begin
  body := ParseBody(Req);
  client := nil;
  try
    if not ResolverLoja(Req, Res, body, uuid) then Exit;
    try
      loja := TAsaasModel.GetLoja(uuid);
      if not loja.Found then
      begin
        TJsonView.SendError(Res, 404, 'Loja não encontrada.');
        Exit;
      end;

      atual := TAsaasModel.UltimaAssinatura(loja.Id);
      if (not atual.Found) or (atual.Status = 'CANCELADA') then
      begin
        TJsonView.SendError(Res, 404, 'Nenhuma assinatura ativa.');
        Exit;
      end;

      client := TAsaasClient.FromConfig;
      r := client.CancelSubscription(atual.SubscriptionId);
      r.Free;

      // a loja continua com acesso até loja.validade (já pago)
      TAsaasModel.SetStatusAssinatura(atual.SubscriptionId, 'CANCELADA');
      TJsonView.SendSuccess(Res, 'Assinatura cancelada.');
    except
      on E: EAsaasError do
      begin
        LogAsaas('cancelar loja ' + uuid + ': ' + E.Message);
        TJsonView.SendError(Res, 502, AsaasErrorText(E));
      end;
      on E: Exception do
      begin
        LogAsaas('cancelar loja ' + uuid + ': ' + E.Message);
        TJsonView.SendError(Res, 500, 'Falha ao cancelar.');
      end;
    end;
  finally
    client.Free;
    body.Free;
  end;
end;

{ ---------------------------------------------------------------- webhook }

procedure HandleWebhook(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  expected, received, eventId, eventType: string;
  root: TJSONObject;
begin
  expected := AsaasCfg('webhook_token', '');
  received := Req.Headers['asaas-access-token'];

  if (expected = '') or (not SafeEquals(expected, received)) then
  begin
    LogAsaas('webhook rejeitado: token inválido');
    TJsonView.SendError(Res, 401, 'Token inválido.');
    Exit;
  end;

  root := ParseBody(Req);
  try
    if root = nil then
    begin
      TJsonView.SendError(Res, 400, 'Payload inválido.');
      Exit;
    end;

    eventId := JsonStr(root, 'id');
    eventType := JsonStr(root, 'event');

    try
      // entrega "at least once": o mesmo evento pode chegar mais de uma vez
      if (eventId <> '') and TAsaasModel.EventoProcessado(eventId) then
      begin
        TJsonView.SendSuccess(Res, 'Evento já processado.');
        Exit;
      end;

      TAsaasModel.ProcessarEvento(eventType, root);

      if eventId <> '' then
        TAsaasModel.RegistrarEvento(eventId, eventType);

      TJsonView.SendSuccess(Res, 'OK');
    except
      on E: Exception do
      begin
        // 500 faz o Asaas reenviar. Falhas repetidas pausam a fila de webhooks:
        // acompanhe este log.
        LogAsaas('erro processando ' + eventType + ' ' + eventId + ': ' + E.Message);
        TJsonView.SendError(Res, 500, 'Falha ao processar.');
      end;
    end;
  finally
    root.Free;
  end;
end;

{ ---------------------------------------------------------------- rotas }

class procedure TAsaasController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/assinatura/checkout', HandleCheckout);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Get('api/v1/assinatura', HandleStatus);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/assinatura/cancelar', HandleCancel);

  // pública: a autenticação é o header asaas-access-token
  THorse.Post('api/v1/webhooks/asaas', HandleWebhook);
end;

end.

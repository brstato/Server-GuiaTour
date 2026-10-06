unit utasaascontroller;

{$mode delphi}{$H+}

{
  Rotas:
    GET  api/v1/assinatura/planos     (JWT)  catálogo de planos (tabela ASAAS_PLANO)
    POST api/v1/assinatura/checkout   (JWT)  corpo: plano, forma_pagamento, cpf_cnpj?, id_loja?
                                             cria cliente + assinatura; devolve link da fatura
                                             e, se for Pix, o QR Code já na resposta
    GET  api/v1/assinatura            (JWT)  status, validade, últimas cobranças
    GET  api/v1/assinatura/pix        (JWT)  QR Code Pix da cobrança em aberto
    POST api/v1/assinatura/cancelar   (JWT)  cancela a assinatura (acesso segue até a validade)
    POST api/v1/webhooks/asaas        (PÚBLICA) eventos do Asaas, autenticada pelo header
                                      asaas-access-token (config.ini [asaas] webhook_token)

  Quem pode chamar as rotas com JWT:
    - tipo "loja":     age sempre sobre a PRÓPRIA loja (UUID do token); id_loja é ignorado.
    - tipo "vendedor": informa id_loja (UUID) no corpo (POST) ou na query (GET). Precisa estar
                       ATIVO e: ser o DONO da loja (TVendedorModel.DonoDaLoja) OU ser
                       ADMINISTRADOR (VENDEDOR.ADM = TRUE), que opera qualquer loja em
                       checkout, status e pix. O cancelamento continua só para o dono.
                       Quando o administrador age em loja de outro vendedor, a ação fica em
                       LOG_ACAO_VENDEDOR antes de o Asaas ser chamado.

  Formas de pagamento aceitas: PIX, BOLETO, CREDIT_CARD. O cartão é digitado na página da
  fatura do Asaas (invoice_url): o servidor nunca recebe dados de cartão.
}

interface

uses
  Classes, SysUtils, SyncObjs, Horse, Horse.JWT, fpjson, jsonparser, DateUtils,
  udata, uconfig, uJsonView, uvendedormodel, uautorizacao, uratelimit, uasaas, uasaasmodel;

type

  { TAsaasController }

  TAsaasController = class
  public
    class procedure RegisterRoutes();
  end;

implementation

procedure LogAsaas(const AMsg: string);
begin
  WriteLn(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', Now) + ' [asaas] ' + AMsg);
end;

function FormaPagamentoValida(const AForma: string): Boolean;
begin
  Result := (AForma = 'PIX') or (AForma = 'BOLETO') or (AForma = 'CREDIT_CARD');
end;

var
  // Lojas com um checkout em andamento neste processo. Sem isso, duplo clique ou duas
  // pessoas gerando cobrança ao mesmo tempo passam juntas pela checagem de "assinatura em
  // andamento" e criam DUAS assinaturas no Asaas (cobrança em dobro para o comerciante).
  GCheckoutLock: TCriticalSection;
  GCheckoutLojas: TStringList;

// True = esta chamada ganhou a vez para a loja. Quem ganhar DEVE chamar SairCheckout.
function EntrarCheckout(const AUuidLoja: string): Boolean;
begin
  GCheckoutLock.Enter;
  try
    Result := GCheckoutLojas.IndexOf(AUuidLoja) < 0;
    if Result then
      GCheckoutLojas.Add(AUuidLoja);
  finally
    GCheckoutLock.Leave;
  end;
end;

procedure SairCheckout(const AUuidLoja: string);
var
  i: Integer;
begin
  GCheckoutLock.Enter;
  try
    i := GCheckoutLojas.IndexOf(AUuidLoja);
    if i >= 0 then
      GCheckoutLojas.Delete(i);
  finally
    GCheckoutLock.Leave;
  end;
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

// Monta {payload, qr_base64, expira_em} a partir da resposta do Asaas; nil se não vier QR
function PixJson(AClient: TAsaasClient; const APaymentId: string): TJSONObject;
var
  qr: TJSONObject;
begin
  Result := nil;
  if APaymentId = '' then Exit;
  try
    qr := AClient.GetPixQrCode(APaymentId);
    try
      if JsonStr(qr, 'payload') = '' then Exit;
      Result := TJSONObject.Create;
      Result.Add('payload', JsonStr(qr, 'payload'));
      Result.Add('qr_base64', JsonStr(qr, 'encodedImage'));
      Result.Add('expira_em', JsonStr(qr, 'expirationDate'));
    finally
      qr.Free;
    end;
  except
    on E: Exception do
    begin
      // sem QR o front cai no link da fatura (que também mostra o Pix)
      LogAsaas('pixQrCode ' + APaymentId + ': ' + E.Message);
      FreeAndNil(Result);
    end;
  end;
end;

{ ------------------------------------------------------------------- planos }

procedure HandlePlanos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  outJson: TJSONObject;
begin
  try
    outJson := TAsaasModel.ListarPlanos;
    TJsonView.SendResponseJsonObject(Res, outJson, 200);
  except
    on E: Exception do
    begin
      LogAsaas('planos: ' + E.Message);
      TJsonView.SendError(Res, 500, 'Falha ao listar planos.');
    end;
  end;
end;

{ ----------------------------------------------------------------- checkout }

procedure HandleCheckout(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  body, cust, subResp, pays, firstPay, outJson, planoJson, pix: TJSONObject;
  uuid, cpfCnpj, customerId, subId, invoiceUrl, paymentId, forma, codigoPlano: string;
  loja: TLojaAsaas;
  atual: TAssinaturaAsaas;
  plano: TPlanoAsaas;
  vencimento: TDateTime;
  client: TAsaasClient;
  arr: TJSONArray;
  comoAdmin, emCheckout: Boolean;
begin
  body := ParseBody(Req);
  client := nil;
  emCheckout := False;
  try
    if body = nil then
    begin
      TJsonView.SendError(Res, 400, 'JSON inválido.');
      Exit;
    end;

    if not TAutorizacao.ResolverLoja(Req, Res, body, True, uuid, comoAdmin) then Exit;

    // uma cobrança por vez por loja (ver GCheckoutLojas)
    if not EntrarCheckout(uuid) then
    begin
      TJsonView.SendError(Res, 409, 'Já existe uma cobrança sendo gerada para esta loja. Aguarde alguns segundos.');
      Exit;
    end;
    emCheckout := True;

    // plano e forma de pagamento são validados no servidor; o VALOR vem da tabela ASAAS_PLANO
    forma := UpperCase(body.Get('forma_pagamento', ''));
    if not FormaPagamentoValida(forma) then
    begin
      TJsonView.SendError(Res, 400, 'Escolha a forma de pagamento: PIX, BOLETO ou CREDIT_CARD.');
      Exit;
    end;

    codigoPlano := body.Get('plano', '');
    try
      plano := TAsaasModel.GetPlano(codigoPlano);
      if not plano.Found then
      begin
        TJsonView.SendError(Res, 400, 'Plano inválido.');
        Exit;
      end;

      loja := TAsaasModel.GetLoja(uuid);
      if not loja.Found then
      begin
        TJsonView.SendError(Res, 404, 'Loja não encontrada.');
        Exit;
      end;

      // CPF/CNPJ só é exigido na primeira vez (quando o cliente ainda não existe no Asaas)
      cpfCnpj := OnlyDigits(body.Get('cpf_cnpj', ''));
      if (loja.CustomerId = '') and (Length(cpfCnpj) <> 11) and (Length(cpfCnpj) <> 14) then
      begin
        TJsonView.SendError(Res, 400, 'Informe um CPF ou CNPJ válido.');
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

      // No máximo 1 cobrança a cada 3 s por usuário: trava disparo em massa (cada cobrança
      // faz o Asaas notificar o comerciante). Só conta quando vai mesmo chamar o Asaas.
      if not TDedupe.Permitir('checkout:' + TDataModule1.GetIdLoja(Req.Headers['Authorization']), 3000) then
      begin
        TJsonView.SendError(Res, 429, 'Muitas tentativas. Aguarde alguns segundos.');
        Exit;
      end;

      // Ação financeira em loja de OUTRO vendedor: registra ANTES de chamar o Asaas. Se o
      // registro falhar, cai no except abaixo e a cobrança não é criada (falha fechada).
      if comoAdmin then
        TVendedorModel.RegistrarLog(TDataModule1.GetIdLoja(Req.Headers['Authorization']),
          loja.Uuid, 'adm_iniciou_cobranca');

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

      subResp := client.CreateSubscription(customerId, forma, plano.Valor,
        DateToIso(vencimento), plano.Ciclo, 'Guia Tour - ' + plano.Nome, loja.Uuid);
      try
        subId := JsonStr(subResp, 'id');
      finally
        subResp.Free;
      end;
      if subId = '' then
        raise Exception.Create('Asaas não retornou o id da assinatura');

      TAsaasModel.InserirAssinatura(loja.Id, customerId, subId, plano.Valor,
        plano.Ciclo, forma, plano.Codigo);

      // 1ª cobrança: link da fatura (+ QR Code se for Pix)
      invoiceUrl := '';
      paymentId := '';
      pays := client.ListSubscriptionPayments(subId);
      try
        if pays.Find('data') is TJSONArray then
        begin
          arr := TJSONArray(pays.Find('data'));
          if (arr.Count > 0) and (arr.Items[0] is TJSONObject) then
          begin
            firstPay := TJSONObject(arr.Items[0]);
            paymentId := JsonStr(firstPay, 'id');
            invoiceUrl := JsonStr(firstPay, 'invoiceUrl');
            TAsaasModel.UpsertPagamento(firstPay);
          end;
        end;
      finally
        pays.Free;
      end;

      outJson := TJSONObject.Create;
      outJson.Add('assinatura', subId);
      outJson.Add('status', 'PENDENTE');
      outJson.Add('forma_pagamento', forma);
      outJson.Add('invoice_url', invoiceUrl);

      planoJson := TJSONObject.Create;
      planoJson.Add('codigo', plano.Codigo);
      planoJson.Add('nome', plano.Nome);
      planoJson.Add('valor', plano.Valor);
      planoJson.Add('ciclo', plano.Ciclo);
      outJson.Add('plano', planoJson);

      if forma = 'PIX' then
      begin
        pix := PixJson(client, paymentId);
        if pix <> nil then
          outJson.Add('pix', pix);
      end;

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
    if emCheckout then
      SairCheckout(uuid);
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
  comoAdmin: Boolean;
begin
  if not TAutorizacao.ResolverLoja(Req, Res, nil, True, uuid, comoAdmin) then Exit;
  try
    loja := TAsaasModel.GetLoja(uuid);
    if not loja.Found then
    begin
      TJsonView.SendError(Res, 404, 'Loja não encontrada.');
      Exit;
    end;
    outJson := TAsaasModel.StatusJson(loja.Id, loja.Validade);
    // o front só pede CPF/CNPJ quando o cliente ainda não existe no Asaas
    outJson.Add('precisa_documento', loja.CustomerId = '');
    TJsonView.SendResponseJsonObject(Res, outJson, 200);
  except
    on E: Exception do
    begin
      LogAsaas('status loja ' + uuid + ': ' + E.Message);
      TJsonView.SendError(Res, 500, 'Falha ao consultar assinatura.');
    end;
  end;
end;

{ --------------------------------------------------------------------- pix }

procedure HandlePix(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  uuid, paymentId: string;
  loja: TLojaAsaas;
  atual: TAssinaturaAsaas;
  client: TAsaasClient;
  pix: TJSONObject;
  comoAdmin: Boolean;
begin
  if not TAutorizacao.ResolverLoja(Req, Res, nil, True, uuid, comoAdmin) then Exit;
  client := nil;
  try
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
        TJsonView.SendError(Res, 404, 'Nenhuma assinatura em andamento.');
        Exit;
      end;

      paymentId := TAsaasModel.PagamentoEmAberto(atual.SubscriptionId);
      if paymentId = '' then
      begin
        TJsonView.SendError(Res, 404, 'Nenhuma cobrança em aberto.');
        Exit;
      end;

      client := TAsaasClient.FromConfig;
      pix := PixJson(client, paymentId);
      if pix = nil then
      begin
        TJsonView.SendError(Res, 502, 'Não foi possível gerar o QR Code Pix agora.');
        Exit;
      end;
      TJsonView.SendResponseJsonObject(Res, pix, 200);
    except
      on E: Exception do
      begin
        LogAsaas('pix loja ' + uuid + ': ' + E.Message);
        TJsonView.SendError(Res, 500, 'Falha ao obter o QR Code.');
      end;
    end;
  finally
    client.Free;
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
  comoAdmin: Boolean;
begin
  body := ParseBody(Req);
  client := nil;
  try
    // cancelar é destrutivo: continua restrito ao dono da loja (AAdminPode = False)
    if not TAutorizacao.ResolverLoja(Req, Res, body, False, uuid, comoAdmin) then Exit;
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
    .Get('api/v1/assinatura/planos', HandlePlanos);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/assinatura/checkout', HandleCheckout);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Get('api/v1/assinatura/pix', HandlePix);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Get('api/v1/assinatura', HandleStatus);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/assinatura/cancelar', HandleCancel);

  // pública: a autenticação é o header asaas-access-token
  THorse.Post('api/v1/webhooks/asaas', HandleWebhook);
end;

initialization
  GCheckoutLock := TCriticalSection.Create;
  GCheckoutLojas := TStringList.Create;

finalization
  GCheckoutLojas.Free;
  GCheckoutLock.Free;

end.

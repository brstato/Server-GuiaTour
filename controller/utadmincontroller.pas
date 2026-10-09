unit utadmincontroller;

{$mode delphi}{$H+}

{
  Administração geral — SOMENTE vendedores administradores (VENDEDOR.ATIVO = TRUE e
  VENDEDOR.ADM = TRUE). Vendedor terceirizado (ADM = FALSE) recebe 403.

  Rotas (todas GET, com JWT):
    api/v1/vendedor/perfil             devolve adm true ou false, para o front decidir se
                                       mostra o botão da administração (vendedor qualquer,
                                       sem 403)
    api/v1/admin/lojas                 todas as lojas cadastradas (de todos os vendedores)
    api/v1/admin/pontos-turisticos     todos os pontos turísticos (de todos os vendedores)
    api/v1/admin/mensalidades?dias=7   lojas vencidas e lojas por vencer sem pagamento
                                       recorrente (dias = janela de aviso, 1..60, padrão 7)

  Autorização (ExigirVendedorAdmin):
    1. o token precisa ser do tipo "vendedor" (token sem claim "tipo" vale como "loja"
       em GetTipoUsuario, então nunca passa);
    2. o vendedor do token precisa existir, estar ATIVO e ter ADM = TRUE no banco AGORA
       (não confia só no JWT, que pode ter sido emitido antes da mudança).

  As respostas trazem dados de todos os comércios (e-mail, telefone), por isso saem com
  Cache-Control: no-store.
}

interface

uses
  Classes, SysUtils, Horse, Horse.JWT, fpjson, udata, uconfig, uJsonView,
  uadminmodel, uautorizacao, ueventomodel;

type

  { TAdminController }

  TAdminController = class
  public
    class procedure RegisterRoutes();
  end;

implementation

// Responde 403 e devolve False quando o chamador não é um vendedor administrador.
function ExigirVendedorAdmin(Req: THorseRequest; Res: THorseResponse;
  out AIdVendedor: string): Boolean;
var
  auth: string;
begin
  Result := False;
  AIdVendedor := '';

  auth := Req.Headers['Authorization'];

  if TDataModule1.GetTipoUsuario(auth) <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a administradores.');
    Exit;
  end;

  AIdVendedor := TDataModule1.GetIdLoja(auth); // claim "id" = UUID do vendedor

  if not TAdminModel.VendedorAdmin(AIdVendedor) then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a administradores.');
    Exit;
  end;

  Result := True;
end;

// Qualquer vendedor pode perguntar se é administrador (200 sempre, nunca 403 por não
// ser adm): o front usa isso só para mostrar ou esconder o botão da administração.
procedure HandlerPerfilVendedor(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  auth: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    auth := Req.Headers['Authorization'];
    if TDataModule1.GetTipoUsuario(auth) <> 'vendedor' then
    begin
      TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
      Exit;
    end;

    jsonRes := TJSONObject.Create;
    jsonRes.Add('adm', TAdminModel.VendedorAdmin(TDataModule1.GetIdLoja(auth)));

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerPerfilVendedor - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminLojas(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    arrayItens := TAdminModel.ListarLojas(idVendedor);

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);
    arrayItens := nil; // agora pertence a jsonRes

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerAdminLojas - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminPontos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    arrayItens := TAdminModel.ListarPontos;

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);
    arrayItens := nil; // agora pertence a jsonRes

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerAdminPontos - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminMensalidades(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  dias: Integer;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    dias := StrToIntDef(Trim(Req.Query['dias']), 7); // o model limita a 1..60

    jsonRes := TAdminModel.ListarMensalidades(idVendedor, dias);

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerAdminMensalidades - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

// ?dias=: só 7, 30 ou 90. Qualquer outro valor vira 30.
function DiasMetricas(Req: THorseRequest): Integer;
begin
  Result := StrToIntDef(Trim(Req.Query['dias']), 30);
  if (Result <> 7) and (Result <> 30) and (Result <> 90) then
    Result := 30;
end;

// GET api/v1/vendedor/metricas?dias=7|30|90
// Soma as lojas do vendedor do token. O vendedor nunca escolhe o escopo.
procedure HandlerMetricasVendedor(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    if not TAutorizacao.ExigirVendedorAtivo(Req, Res, idVendedor) then Exit;

    jsonRes := TEventoModel.MetricasRede(idVendedor, DiasMetricas(Req));
    if not Assigned(jsonRes) then
    begin
      TJsonView.SendError(Res, 404, 'Vendedor não encontrado.');
      Exit;
    end;

    Res.AddHeader('Cache-Control', 'private, max-age=60');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);  // libera jsonRes
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      TJsonView.SendErroInterno(Res, 'HandlerMetricasVendedor', e);
    end;
  end;
end;

// GET api/v1/admin/metricas?dias=7|30|90
// Soma a rede inteira. Só vendedor administrador (ativo e ADM no banco agora).
procedure HandlerAdminMetricas(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    jsonRes := TEventoModel.MetricasRede('', DiasMetricas(Req));

    Res.AddHeader('Cache-Control', 'private, max-age=60');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);  // libera jsonRes
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      TJsonView.SendErroInterno(Res, 'HandlerAdminMetricas', e);
    end;
  end;
end;

class procedure TAdminController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/metricas', HandlerMetricasVendedor);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/metricas', HandlerAdminMetricas);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/perfil', HandlerPerfilVendedor);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/lojas', HandlerAdminLojas);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/pontos-turisticos', HandlerAdminPontos);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/mensalidades', HandlerAdminMensalidades);
end;

end.

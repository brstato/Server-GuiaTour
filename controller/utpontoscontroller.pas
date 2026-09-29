unit utPontoscontroller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, uJsonView, fpjson,
  udata, uconfig, usecurityservice, upontoturisticomodel, Horse.JWT;

type

  { TPontoTuristicoController }

  TPontoTuristicoController = class
  private
  public
    class procedure RegisterRoutes();
  end;

implementation

{ TPontoTuristicoController }

function ExigirVendedor(Req: THorseRequest; Res: THorseResponse;
        out idVendedor: string): Boolean;
var
  tipo: string;
begin
  Result := False;
  tipo := TDataModule1.GetTipoUsuario(Req.Headers['Authorization']);

  if tipo <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
    Exit;
  end;

  idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']); // claim 'id'
  Result := True;
end;

function ExigirDonoDoPonto(Req: THorseRequest; Res: THorseResponse;
        const uuidPonto: string; out idVendedor: string): Boolean;
begin
  Result := False;

  if not ExigirVendedor(Req, Res, idVendedor) then
    Exit;

  if Trim(uuidPonto) = '' then
  begin
    TJsonView.SendError(Res, 400, 'Ponto turístico não informado.');
    Exit;
  end;

  if not TPontoTuristicoModel.DonoDoPonto(idVendedor, uuidPonto) then
  begin
    TJsonView.SendError(Res, 403, 'Você não tem acesso a este ponto turístico.');
    Exit;
  end;

  Result := True;
end;

procedure PreencherDadosDoBody(RequestJson: TJSONObject; out dados: TPontoTuristicoData);
begin
  with dados do
  begin
    nome         := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome',      '')));
    slug         := TSecurityService.SanitizeInput(Trim(RequestJson.Get('slug',      '')));
    resumo       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('resumo',    '')));
    historia     := TSecurityService.SanitizeInput(Trim(RequestJson.Get('historia',  '')));

    latitude     := TSecurityService.SanitizeInput(Trim(RequestJson.Get('latitude',  '')));
    longitude    := TSecurityService.SanitizeInput(Trim(RequestJson.Get('longitude', '')));
    cep          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('cep',       '')));
    endereco     := TSecurityService.SanitizeInput(Trim(RequestJson.Get('endereco',  '')));
    numero       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('numero',    '')));
    bairro       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('bairro',    '')));
    cidade       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('cidade',    '')));
    estado       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('estado',    '')));

    nome_arquivo_capa := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome_arquivo_capa', '')));
    capa              := RequestJson.Get('capa', ''); // base64, sem sanitizar (binário)
    galeria           := RequestJson.Get('galeria', ''); // JSON string: [{nome_arquivo, itemFoto}, ...]

    dados.id_categoria := RequestJson.Get('id_categoria', 0);
  end;
end;

procedure HandlerCriarPonto(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  RequestJson: TJSONObject;
  dados: TPontoTuristicoData;
  idVendedor, uuidPonto: string;
begin
  RequestJson := nil;
  try
    try
      if not ExigirVendedor(Req, Res, idVendedor) then Exit;

      if Trim(Req.Body) = '' then
      begin
        TJsonView.SendError(Res, 400, 'Corpo da requisição está vazio.');
        Exit;
      end;

      RequestJson := TJSONObject(GetJSON(Req.Body));
      PreencherDadosDoBody(RequestJson, dados);
      dados.idVendedor := idVendedor;

      if dados.id_categoria <= 0 then
      begin
        TJsonView.SendError(Res, 400, 'Categoria é obrigatória.');
        Exit;
      end;

      if (dados.nome = '') or (dados.latitude = '') or (dados.longitude = '') then
      begin
        TJsonView.SendError(Res, 400, 'Nome, latitude e longitude são obrigatórios.');
        Exit;
      end;

      uuidPonto := TPontoTuristicoModel.CriarPonto(dados);

      TJsonView.SendResponse(Res,
        TJSONObject(GetJSON('{"uuid":"' + uuidPonto + '"}')), 201);
    except on e: Exception do
      begin
        WriteLn('Erro em: HandlerCriarPonto - ' + e.Message);
        TJsonView.SendError(Res, 500, 'Erro interno.');
      end;
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
  end;
end;

procedure HandlerListarPontos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    if not ExigirVendedor(Req, Res, idVendedor) then Exit;

    arrayItens := TPontoTuristicoModel.ListarPontos(idVendedor);

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerListarPontos - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerGetPontoVendedor(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor, uuidPonto: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    uuidPonto := Req.Params['uuid'];

    if not ExigirDonoDoPonto(Req, Res, uuidPonto, idVendedor) then Exit;

    jsonRes := TPontoTuristicoModel.GetPontoPorUuid(uuidPonto);

    if not Assigned(jsonRes) then
    begin
      TJsonView.SendError(Res, 404, 'Ponto turístico não encontrado.');
      Exit;
    end;

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerGetPontoVendedor - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAtualizarPonto(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  RequestJson: TJSONObject;
  dados: TPontoTuristicoData;
  idVendedor, uuidPonto: string;
begin
  RequestJson := nil;
  try
    try
      uuidPonto := Req.Params['uuid'];

      if not ExigirDonoDoPonto(Req, Res, uuidPonto, idVendedor) then Exit;

      if Trim(Req.Body) = '' then
      begin
        TJsonView.SendError(Res, 400, 'Corpo da requisição está vazio.');
        Exit;
      end;

      RequestJson := TJSONObject(GetJSON(Req.Body));
      PreencherDadosDoBody(RequestJson, dados);
      dados.idVendedor := idVendedor;

      if dados.id_categoria <= 0 then
      begin
        TJsonView.SendError(Res, 400, 'Categoria é obrigatória.');
        Exit;
      end;

      if not TPontoTuristicoModel.AtualizarPonto(uuidPonto, dados) then
      begin
        TJsonView.SendError(Res, 404, 'Ponto turístico não encontrado.');
        Exit;
      end;

      TJsonView.SendSuccess(Res, 'Ponto turístico atualizado com sucesso.');
    except on e: Exception do
      begin
        WriteLn('Erro em: HandlerAtualizarPonto - ' + e.Message);
        TJsonView.SendError(Res, 500, 'Erro interno.');
      end;
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
  end;
end;

// Rota pública — dados do ponto pra montar a página (JSON por enquanto;
// troca pra TJsonView.SendHtml quando o template/view estiver pronto).
procedure HandlerGetPontoPublico(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  slug: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    slug := Req.Params['slug'];

    if Trim(slug) = '' then
    begin
      TJsonView.SendError(Res, 400, 'Ponto turístico não informado.');
      Exit;
    end;

    jsonRes := TPontoTuristicoModel.GetBySlug(slug);

    if not Assigned(jsonRes) then
    begin
      TJsonView.SendError(Res, 404, 'Ponto turístico não encontrado.');
      Exit;
    end;

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerGetPontoPublico - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

// Comércios num raio ao redor do ponto — raio efetivo já leva em conta
// o PLANO_DESTAQUE do comércio (plano pago amplia o raio de visibilidade
// e prioriza a ordenação), resolvido dentro do model.
procedure HandlerComerciosProximos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  slug: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    slug := Req.Params['slug'];

    if Trim(slug) = '' then
    begin
      TJsonView.SendError(Res, 400, 'Ponto turístico não informado.');
      Exit;
    end;

    arrayItens := TPontoTuristicoModel.GetComerciosProximos(slug);

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerComerciosProximos - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

// 1. Handler para pontos turísticos próximos
procedure HandlerPontosProximos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  slug: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    slug := Req.Params['slug'];
    if Trim(slug) = '' then
    begin
      TJsonView.SendError(Res, 400, 'Ponto turístico não informado.');
      Exit;
    end;

    arrayItens := TPontoTuristicoModel.GetPontosProximos(slug);
    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em HandlerPontosProximos: ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

// 2. Handler para detecção de contexto via Cloudflare / Proxy
procedure HandlerContextoVisitante(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  ip, cidade, uf: string;
  jsonRes: TJSONObject;
begin
  // Prioriza headers injetados pelo Cloudflare / Nginx
  ip := Req.Headers['CF-Connecting-IP'];
  if ip = '' then
    ip := Req.Headers['X-Forwarded-For'];
  if ip = '' then
    ip := Req.RawWebRequest.RemoteAddr;

  // Cloudflare injeta localização geográfica direta nos headers
  cidade := Req.Headers['CF-IPCity'];
  uf     := Req.Headers['CF-IPRegion'];

  jsonRes := TJSONObject.Create;
  try
    jsonRes.Add('ip', ip);
    jsonRes.Add('cidade', cidade);
    jsonRes.Add('uf', uf);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except
    jsonRes.Free;
    raise;
  end;
end;

procedure HandlerPontosPorGPS(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  lat, lng, raio: Double;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    lat  := StrToFloatDef(StringReplace(Req.Query['lat'],  ',', '.', []), 0);
    lng  := StrToFloatDef(StringReplace(Req.Query['lng'],  ',', '.', []), 0);
    raio := StrToFloatDef(StringReplace(Req.Query['raio'], ',', '.', []), 30);

    if (lat = 0) or (lng = 0) then
    begin
      TJsonView.SendError(Res, 400, 'Coordenadas (lat, lng) são obrigatórias.');
      Exit;
    end;

    arrayItens := TPontoTuristicoModel.GetPontosPorGPS(lat, lng, raio);
    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em HandlerPontosPorGPS: ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerListarCategorias(req: THorseRequest; res: THorseResponse);
var
  arrayItens: TJSONArray;
begin
  arrayItens := nil;
  try
    try
      arrayItens := TPontoTuristicoModel.ListarCategorias;

      TJsonView.SendT(Res, arrayItens.AsJSON);
    except on e: Exception do
      begin
        WriteLn('Erro em HandlerPontosPorGPS: ' + e.Message);
        TJsonView.SendError(Res, 500, 'Erro interno.');
      end;
    end;
  finally
    FreeAndNil(arrayItens);
  end;
end;

class procedure TPontoTuristicoController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/vendedor/ponto-turistico', HandlerCriarPonto);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/pontos-turisticos', HandlerListarPontos);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/ponto-turistico/:uuid', HandlerGetPontoVendedor);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Put('api/v1/vendedor/ponto-turistico/:uuid', HandlerAtualizarPonto);

  // --- Público (sem JWT) ---
  THorse.Get('api/v1/ponto/:slug', HandlerGetPontoPublico);
  THorse.Get('api/v1/ponto/:slug/comercios-proximos', HandlerComerciosProximos);
  THorse.Get('api/v1/ponto/:slug/proximos', HandlerPontosProximos);
  THorse.Get('api/v1/visitante/contexto', HandlerContextoVisitante);
  THorse.Get('api/v1/explorar/pontos', HandlerPontosPorGPS);
  THorse.Get('api/v1/explorar/categorias', HandlerListarCategorias);
end;

end.

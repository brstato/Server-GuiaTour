unit uportifoliocontroller;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  Horse,
  uportifolioview,
  uJsonView,
  uportifoliomodel,
  udata,
  Horse.JWT,
  fpjson,
  LazJWT,
  StrUtils,
  usecurityservice,
  uconfig,
  upontoturisticomodel,
  uguiatourpontoview,
  uautorizacao,
  uadminmodel,
  uguiatourutils,
  uratelimit;

type

  { TPortifolioController }

  TPortifolioController = class
    public
      class procedure RegisterRoutes();
  end;

implementation

{ TPortifolioController }

procedure ServirHome(req: THorseRequest; res: THorseResponse);
var
  fs: TFormatSettings;
  lat, lng: Double;
  arr: TJSONArray;
  ponto: TJSONObject;
  slugPonto: string;
begin
  ponto := nil;
  arr := nil;
  try
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    lat := StrToFloatDef(Trim(req.Headers['CF-IPLatitude']),  0, fs);
    lng := StrToFloatDef(Trim(req.Headers['CF-IPLongitude']), 0, fs);

    if (lat = 0) and (lng = 0) then
    begin
      lat := -23.0067;
      lng := -44.3181;
    end;

    // ponto turístico mais próximo (50 km)
    arr := TPontoTuristicoModel.GetPontosPorGPS(lat, lng, 20000, 1);

    slugPonto := TJSONObject(arr.Items[0]).Get('slug', '');

    ponto := TPontoTuristicoModel.GetBySlug(slugPonto);
    if not Assigned(ponto) then
    begin
      TJsonView.SendHtml(res, 404, '<h1>Ponto turístico não encontrado.</h1>');
      Exit;
    end;

    res.AddHeader('Cache-Control', 'private, no-cache');
    TJsonView.SendHtml(res, 200, TPontoView.Render(ponto, slugPonto));
  finally
    arr.Free;
    ponto.Free;
  end;
end;

function verifica_slug(const slug: string): Boolean;
const
  RESERVADOS: array[0..7] of string = (
    'localhost', 'app', 'api', 'www', 'admin', 'painel', 'loja', 'imagens'
  );
var
  i: Integer;
begin
  Result := True; // assume inválido até provar o contrário

  if Trim(slug) = '' then Exit;
  if Length(slug) > 100 then Exit;

  for i := 1 to Length(slug) do
    if not (slug[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-']) then Exit;

  if IndexText(slug, RESERVADOS) <> -1 then Exit;

  Result := False;
end;

procedure HandlerPortifolioGet(req: THorseRequest; res: THorseResponse);
var
  Slug, HostStr: string;
  PosPonto: Integer;
  Perfil: TComercioPerfil;
  HTMLFinal, lat, lng, cidade: string;
begin
  if not req.Params.TryGetValue('slug', slug) then Slug := '';

  if Trim(Slug) = '' then
  begin
    HostStr := req.Headers['Host'];

    if (HostStr = 'guiatour.online') or (HostStr = 'www.guiatour.online') or
       (HostStr.StartsWith('api.')) then
    begin
      lat := Req.Headers['CF-IPLatitude'];
      lng := Req.Headers['CF-IPLongitude'];
      cidade := Req.Headers['CF-IPCity'];

      ServirHome(req, res);
      Exit;
    end;

    PosPonto := Pos('.', HostStr);
    if PosPonto > 0 then
      Slug := Copy(HostStr, 1, PosPonto - 1)
    else
      Slug := HostStr;
  end;

  if verifica_slug(Slug) then
  begin
    TJsonView.SendHtml(res, 404, '<h1>Página não encontrada</h1>');
    Exit;
  end;

  try
    Perfil := TProtifolioModel.GetBySlug(Slug);
    if not Perfil.Encontrado then
    begin
      TJsonView.SendHtml(res, 404, '<h1>Loja não encontrada.</h1><p>Verifique o endereço.</p>');
      Exit;
    end;

    HTMLFinal := TGuiatourView.Render(Perfil, Slug);

    TJsonView.SendHtml(res, 200, HTMLFinal);
  except
    on E: Exception do
    begin
      TJsonView.SendHtml(
        res,
        500,
        '<h1>Erro interno do servidor</h1><p>Tente novamente mais tarde.</p>'
      );
    end;
  end;

end;

procedure HandlePortifolioUpdate(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  jsonreq, jsonres: TJSONObject;
  id_loja, titulo, subtitulo, avatar, foto_bio, bio, url_video: string;
  id_site: integer;
  lJSONData, f: TJSONData;
  url_video_enviado: Boolean;
begin
  jsonreq := nil;
  jsonres := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;
      titulo    := TSecurityService.SanitizeInput(jsonreq.Get('titulo',    ''));
      subtitulo := TSecurityService.SanitizeInput(jsonreq.Get('subtitulo', ''));
      avatar    := TSecurityService.SanitizeInput(jsonreq.Get('avatar',    ''));
      foto_bio  := TSecurityService.SanitizeInput(jsonreq.Get('foto_bio',  ''));
      bio       := TSecurityService.SanitizeInput(jsonreq.Get('bio',       ''));
      id_site   := jsonreq.Get('id_site', 0);

      url_video := Trim(jsonreq.Get('url_video', ''));
      f := jsonreq.Find('url_video');
      url_video_enviado := Assigned(f) and (f.JSONType in [jtString, jtNull]);

      if (id_loja = '') then
      begin
        TJsonView.SendError(res, 400, 'O ID da Loja é obrigatório.');
        Exit;
      end;

      if url_video_enviado and not UrlVideoValida(url_video) then
      begin
        TJsonView.SendError(res, 400, 'URL de vídeo inválida. Use um link de vídeo do YouTube.');
        Exit;
      end;

      TProtifolioModel.SavePortfolio(
        id_loja,
        titulo,
        subtitulo,
        avatar,
        foto_bio,
        bio
      );

      if url_video_enviado then
        TProtifolioModel.AtualizarUrlVideo(id_loja, url_video);

      jsonres := TJSONObject.Create;

      jsonres.Add('id_portfolio', id_site);

      TJsonView.SendResponseJsonObject(res, jsonres, 200);
    except
      on e:exception do
      begin
        TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
        if Assigned(jsonres) then jsonres.Free;
      end;
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandlerPortifolioGetInfo(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  jsonres: TJSONObject;
  id_loja: string;
  status: Boolean;
begin
  jsonres := nil;
  try
    if not TAutorizacao.ResolverLojaDono(req, res, nil, id_loja) then Exit;

    jsonres := TProtifolioModel.GetPortfolio(id_loja);

    if Assigned(jsonres) = True then
      TJsonView.SendResponseJsonObject(res, jsonres, 200)
    else
      begin
        TJsonView.SendError(res, 404, 'Portfólio não encontrado!');
        if Assigned(jsonres) then jsonres.Free;
      end;
  except
    on e:exception do
    begin
      TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
      if Assigned(jsonres) then jsonres.Free;
    end;
  end;
end;

procedure HandleRemoveItem(req: THorseRequest; Res: THorseResponse;
  next: TNextProc);
var
  id: integer;
  str_id: string;
  jsonreq: TJSONObject;
  lJSONData, f: TJSONData;
begin
  jsonreq := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if lJSONData.JSONType <> jtObject then
      begin
        lJSONData.Free;
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;
      jsonreq := TJSONObject(lJSONData);

      // o painel manda id_foto como número; aceita texto também
      f := jsonreq.Find('id_foto');
      if Assigned(f) and (f.JSONType in [jtNumber, jtString]) then
        id := StrToIntDef(f.AsString, 0)
      else
        id := 0;
      if id = 0 then
      begin
        TJsonView.SendError(res, 400, 'Id da foto não informado.');
        exit;
      end;

      if not TAutorizacao.ExigirAcessoAFoto(req, res, id) then Exit;

      TProtifolioModel.RemoveItem(id);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
    end;
  finally
    FreeAndNil(jsonreq);
  end;
end;

procedure HandleUploadFoto(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq: TJSONObject;
  id_loja, base64_str, nome_arquivo: string;
  id_site: integer;
  lJSONData: TJSONData;
  DM: TDataModule1;
begin
  jsonreq := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;

      id_site      := jsonreq.Get('id_site', 0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if base64_str = '' then
      begin
        TJsonView.SendError(res, 400, 'Dados inválidos.');
        Exit;
      end;

      if not TAdminModel.SiteDaLoja(id_site, id_loja) then
      begin
        TJsonView.SendError(res, 403, 'Este site não pertence a esta loja.');
        Exit;
      end;

      TProtifolioModel.UploadFoto(id_site, nome_arquivo, base64_str, id_loja);

      TJsonView.SendSuccess(res);
    except
      on e: exception do
        TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandleGetGaleria(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  id_portfolio: integer;
  jsonres: TJSONObject;
begin
  jsonres := nil;
  try
    id_portfolio := StrToInt(req.Params['id_portfolio']);

    jsonres := TProtifolioModel.GetGaleria(id_portfolio);

    TJsonView.SendResponseJsonObject(res, jsonres, 200);
  except
    on EConvertError do
      TJsonView.SendError(res, 400, 'id inválido');
    on e:exception do
    begin
      TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
      if Assigned(jsonres) then jsonres.Free;
    end;
  end;
end;

procedure HandleUpdateAvatar(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq, jsonres: TJSONObject;
  id_loja, nome_arquivo, base64_str: string;
  id_site: integer;
  lJSONData: TJSONData;
  DM: TDataModule1;
begin
  jsonreq := nil;
  jsonres := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;

      id_site      := jsonreq.Get('id_site', 0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if base64_str = '' then
      begin
        TJsonView.SendError(res, 400, 'Dados inválidos.');
        Exit;
      end;

      id_site := TProtifolioModel.UpdateAvatar(id_site, nome_arquivo, id_loja, base64_str);

      jsonres := TJSONObject.Create;

      jsonres.Add('id_portfolio', id_site);

      TJsonView.SendResponseJsonObject(res, jsonres, 200);
    except on e:exception do
    begin
      TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
      if Assigned(jsonres) then jsonres.Free;
    end;
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandleUpdateFotoBio(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq, jsonres: TJSONObject;
  id_loja, nome_arquivo, base64_str: string;
  id_site: integer;
  lJSONData: TJSONData;
begin
  jsonreq := nil;
  jsonres := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;

      id_site      := jsonreq.Get('id_site',        0);
      nome_arquivo := jsonreq.Get('nome_arquivo',  '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if base64_str = '' then
      begin
        TJsonView.SendError(res, 400, 'Dados inválidos.');
        Exit;
      end;

      id_site := TProtifolioModel.UpdateFotoBio(id_site, nome_arquivo, id_loja, base64_str);

      jsonres := TJSONObject.Create;
      jsonres.Add('id_portfolio', id_site);

      TJsonView.SendResponseJsonObject(res, jsonres, 200);
    except on e:exception do
    begin
      TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
      if Assigned(jsonres) then jsonres.Free;
    end;
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandlePortifolioUpdateBasico(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja, titulo, subtitulo, bio, url_video: string;
  json_req: TJSONObject;
  f, lJSONData: TJSONData;
  url_video_enviado: Boolean;
begin
  json_req := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if lJSONData.JSONType <> jtObject then
      begin
        lJSONData.Free;
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;
      json_req := TJSONObject(lJSONData);

      if not TAutorizacao.ResolverLojaDono(req, res, json_req, id_loja) then Exit;

      // os três campos são obrigatórios: se faltar um, recusa (não grava vazio por cima)
      if not (Assigned(json_req.Find('titulo')) and
              Assigned(json_req.Find('subtitulo')) and
              Assigned(json_req.Find('bio'))) then
      begin
        TJsonView.SendError(res, 400, 'Informe titulo, subtitulo e bio.');
        exit;
      end;

      titulo   := TSecurityService.SanitizeInput(json_req.Get('titulo',    ''));
      subtitulo:= TSecurityService.SanitizeInput(json_req.Get('subtitulo', ''));
      bio      := TSecurityService.SanitizeInput(json_req.Get('bio',       ''));

      url_video := Trim(json_req.Get('url_video', ''));
      f := json_req.Find('url_video');
      url_video_enviado := Assigned(f) and (f.JSONType in [jtString, jtNull]);

      if url_video_enviado and not UrlVideoValida(url_video) then
      begin
        TJsonView.SendError(res, 400, 'URL de vídeo inválida. Use um link de vídeo do YouTube.');
        Exit;
      end;

      TProtifolioModel.PortifolioUpdateBasico(id_loja, titulo, subtitulo, bio);

      if url_video_enviado then
        TProtifolioModel.AtualizarUrlVideo(id_loja, url_video);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno.');
        WriteLn('Erro em HandlePortifolioUpdateBasico: ' + e.Message);
      end;
    end;
  finally
    if Assigned(json_req) then FreeAndNil(json_req);
  end;
end;


procedure HandleUpdateFotoCapa(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  jsonreq, jsonres: TJSONObject;
  id_loja, nome_arquivo, base64_str: string;
  id_site: integer;
  lJSONData: TJSONData;
begin
  jsonreq := nil;
  jsonres := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;

      id_site      := jsonreq.Get('id_site',       0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64','');

      if base64_str = '' then
      begin
        TJsonView.SendError(res, 400, 'Dados inválidos.');
        Exit;
      end;

      id_site := TProtifolioModel.UpdateFotoCapa(nome_arquivo, id_loja, base64_str);

      jsonres := TJSONObject.Create;
      jsonres.Add('id_portfolio', id_site);

      TJsonView.SendResponseJsonObject(res, jsonres, 200);
    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno.');
        WriteLn('Erro em: HandleUpdateFotoCapa ' + e.Message);
        if Assigned(jsonres) then FreeAndNil(jsonres);
      end;
    end;
  finally
    if Assigned(jsonreq) then FreeAndNil(jsonreq);
  end;
end;


procedure HandleDepoimentoCreate(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  jsonreq, jsonres: TJSONObject;
  slug, nome, texto, foto_base64, extensao_foto, id_loja, err, ip: string;
  nota, id_depoimento: integer;
  lJSONData: TJSONData;
begin
  jsonreq := nil;
  jsonres := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if not (Assigned(lJSONData) and (lJSONData.JSONType = jtObject)) then
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;
      jsonreq := TJSONObject(lJSONData);

      slug        := TSecurityService.SanitizeInput(jsonreq.Get('slug', ''));
      nome        := TSecurityService.SanitizeInput(jsonreq.Get('nome', ''));
      texto       := TSecurityService.SanitizeInput(jsonreq.Get('texto',''));
      id_loja     := jsonreq.Get('id_comercio', '');
      nota        := jsonreq.Get('nota', 0);
      foto_base64 := jsonreq.Get('foto_base64', '');

      if (slug = '') or (nome = '') or (texto = '') then
      begin
        TJsonView.SendError(res, 400, 'Nome, nota e depoimento são obrigatórios.');
        Exit;
      end;

      if (nota < 1) or (nota > 5) then
      begin
        TJsonView.SendError(res, 400, 'Nota inválida.');
        Exit;
      end;

      // tamanhos das colunas (NOME 120, TEXTO 1000): corta em vez de dar erro no banco
      nome  := Utf8Corta(nome, 120);
      texto := Utf8Corta(texto, 1000);

      // a loja precisa existir, estar no ar e bater com o slug da página
      if not TProtifolioModel.LojaAceitaDepoimento(id_loja, slug) then
      begin
        TJsonView.SendError(res, 404, 'Loja não encontrada.');
        Exit;
      end;

      // 1 depoimento por IP + loja a cada 60 s (spam e enchimento do disco)
      ip := req.Headers['CF-Connecting-IP'];
      if ip = '' then ip := req.Headers['X-Forwarded-For'];
      if ip = '' then ip := 'desconhecido';
      if not TDedupe.Permitir('depoimento:' + ip + '|' + id_loja, 60000) then
      begin
        TJsonView.SendError(res, 429, 'Aguarde um minuto antes de enviar outro depoimento.');
        Exit;
      end;

      extensao_foto := '';
      if foto_base64 <> '' then
      begin
        if not TProtifolioModel.FotoValidaDepoimento(foto_base64, extensao_foto) then
        begin
          TJsonView.SendError(res, 400, 'Formato de imagem não suportado ou arquivo muito grande.');
          Exit;
        end;
      end;

      id_depoimento := TProtifolioModel.SaveDepoimento(id_loja, nome, texto,
        nota, foto_base64, extensao_foto);

      jsonres := TJSONObject.Create;
      jsonres.Add('id_depoimento', id_depoimento);

      TJsonView.SendResponseJsonObject(res, jsonres, 201);
    except
      on e: exception do
      begin
        TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
        err := e.Message;
        if Assigned(jsonres) then jsonres.Free;
      end;
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandleGetDepoimentosPendentes(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  id_loja, json_str: string;
  arrayRes: TJSONArray;
begin
  arrayRes := nil;
  try
    try
      id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Não autorizado.');
        Exit;
      end;

      arrayRes := TProtifolioModel.GetDepoimentosPendentesJson(id_loja);
      TJsonView.SendText(res, 200, arrayRes.AsJSON);
    except
      on e: exception do
      begin
        WriteLn('Erro em: HandleGetDepoimentosPendentes ' + e.Message);
        TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
      end;
    end;
  finally
    FreeAndNil(arrayRes);
  end;
end;

procedure HandleAprovarDepoimento(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq: TJSONObject;
  id_depoimento: integer;
  lJSONData: TJSONData;
  id_loja: string;
begin
  jsonreq := nil;
  try
    try
      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;

      id_depoimento := jsonreq.Get('id_depoimento', 0);

      if id_depoimento <= 0 then
      begin
        TJsonView.SendError(res, 400, 'ID do depoimento inválido.');
        Exit;
      end;

      if not TProtifolioModel.AprovarDepoimento(id_depoimento, id_loja) then
      begin
        TJsonView.SendError(res, 404, 'Depoimento não encontrado.');
        Exit;
      end;

      TJsonView.SendSuccess(res);
    except
      on e: exception do
        TJsonView.SendErroInterno(res, 'uportifoliocontroller', e);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

class procedure TPortifolioController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/update_portifolio_basico', HandlePortifolioUpdateBasico);

  // DESATIVADA (sem uso no painel; gravava avatar/foto_bio como texto livre)
  // THorse.AddCallback(HorseJWT(TConfig.Token))
  // .Post('api/v1/portfolio/update', HandlePortifolioUpdate);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/portfolio/info', HandlerPortifolioGetInfo);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/remove', HandleRemoveItem);

  // DESATIVADA (sem uso no painel; não conferia o dono da galeria)
  // THorse.AddCallback(HorseJWT(TConfig.Token))
  // .Get('api/v1/portfolio/galeria/:id_portfolio', HandleGetGaleria);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/avatar', HandleUpdateAvatar);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/foto-bio', HandleUpdateFotoBio);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/foto-capa', HandleUpdateFotoCapa);

  THorse.Get('/loja/:slug', HandlerPortifolioGet);
  THorse.get('/', HandlerPortifolioGet);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/portfolio/upload', HandleUploadFoto);

  THorse.Post('api/v1/depoimentos', HandleDepoimentoCreate);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Get('api/v1/depoimentos/pendentes', HandleGetDepoimentosPendentes);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Put('api/v1/depoimentos/aprovar', HandleAprovarDepoimento);
end;

end.

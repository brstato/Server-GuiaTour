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
  uconfig;

type

  { TPortifolioController }

  TPortifolioController = class
    public
      class procedure RegisterRoutes();
  end;

implementation

{ TPortifolioController }

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
  HTMLFinal: string;
begin
  if not req.Params.TryGetValue('slug', slug) then Slug := '';

  if Trim(Slug) = '' then
  begin
    HostStr := req.Headers['Host'];

    if (HostStr = 'guiatour.online') or (HostStr = 'www.guiatour.online') or
       (HostStr.StartsWith('api.')) then
    begin
      TJsonView.SendHtml(
        res,
        404,
        '<h1>Página inicial do Guiatour (em construção)</h1>'
      );
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
  id_loja, titulo, subtitulo, avatar, foto_bio, bio: string;
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

      id_loja   := TSecurityService.SanitizeInput(jsonreq.Get('id_loja',   ''));
      titulo    := TSecurityService.SanitizeInput(jsonreq.Get('titulo',    ''));
      subtitulo := TSecurityService.SanitizeInput(jsonreq.Get('subtitulo', ''));
      avatar    := TSecurityService.SanitizeInput(jsonreq.Get('avatar',    ''));
      foto_bio  := TSecurityService.SanitizeInput(jsonreq.Get('foto_bio',  ''));
      bio       := TSecurityService.SanitizeInput(jsonreq.Get('bio',       ''));
      id_site   := jsonreq.Get('id_site', 0);

      if (id_loja = '') then
      begin
        TJsonView.SendError(res, 400, 'O ID da Loja é obrigatório.');
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

      jsonres := TJSONObject.Create;

      jsonres.Add('id_portfolio', id_site);

      TJsonView.SendResponseJsonObject(res, jsonres, 200);
    except
      on e:exception do
      begin
        TJsonView.SendError(res, 500, e.Message);
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
    id_loja := req.Params['id_loja'];

    if Trim(id_loja) = '' then
    begin
      TJsonView.SendError(res, 400, 'Parâmetro id_loja é obrigatório.');
      Exit;
    end;

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
      TJsonView.SendError(res, 500, e.Message);
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
begin
  jsonreq := nil;
  try
    try
      jsonreq := TJSONObject(GetJSON(req.Body));
      if not Assigned(jsonreq) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      id := StrToIntDef(jsonreq.find('id_foto').AsString, 0);
      if id = 0 then
      begin
        TJsonView.SendError(res, 400, 'Id da foto não informado.');
        exit;
      end;

      TProtifolioModel.RemoveItem(id);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
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
      try
        DM := TDataModule1.Create(nil);
        id_loja := DM.GetIdLoja(req.Headers['Authorization']);
      except
        on E: Exception do
        begin
          TJsonView.SendError(res, 500, 'Erro ao ler token: ' + E.Message);
          Exit;
        end;
      end;

      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Token inválido ou sem id_loja.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      id_site      := jsonreq.Get('id_site', 0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if (id_loja = '') or (base64_str = '') then
      begin
        TJsonView.SendError(res, 400, 'Dados inválidos.');
        Exit;
      end;

      TProtifolioModel.UploadFoto(id_site, nome_arquivo, base64_str, id_loja);

      TJsonView.SendSuccess(res);
    except
      on e: exception do
        TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
    DM.Free;
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
      TJsonView.SendError(res, 500, e.Message);
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
      try
        id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro ao ler token: ' + E.Message);
        Exit;
      end;
      end;

      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Token inválido ou sem id_loja.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      id_site      := jsonreq.Get('id_site', 0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if (id_loja = '') or (base64_str = '') then
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
      TJsonView.SendError(res, 500, e.Message);
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
      try
        id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro ao ler token: ' + E.Message);
        Exit;
      end;
      end;

      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Token inválido ou sem id_loja.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      id_site      := jsonreq.Get('id_site',        0);
      nome_arquivo := jsonreq.Get('nome_arquivo',  '');
      base64_str   := jsonreq.Get('imagem_base64', '');

      if (id_loja = '') or (base64_str = '') then
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
      TJsonView.SendError(res, 500, e.Message);
      if Assigned(jsonres) then jsonres.Free;
    end;
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

procedure HandlerRobotsGet(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  HostStr, RobotsStr: string;
begin
  HostStr := req.Headers['Host'];

  RobotsStr := 'User-agent: *' + sLineBreak +
               'Allow: /' + sLineBreak +
               'Sitemap: https://' + HostStr + '/sitemap.xml';

  TJsonView.SendText(res, 200, RobotsStr);
end;

procedure HandlerSitemapGet(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  HostStr, Slug, XMLStr, UrlFotoAbsoluta: string;
  PosPonto, i: Integer;
  Perfil: TComercioPerfil;
begin
  HostStr := req.Headers['Host'];
  PosPonto := Pos('.', HostStr);

  if PosPonto > 0 then
    Slug := Copy(HostStr, 1, PosPonto - 1)
  else
    Slug := HostStr;

  if verifica_slug(Slug) then
  begin
    TJsonView.SendHtml(res, 404, 'Not found');
    Exit;
  end;

  try
    Perfil := TProtifolioModel.GetBySlug(Slug);
    if not Perfil.Encontrado then
    begin
      TJsonView.SendHtml(res, 404, 'Not found');
      Exit;
    end;

    // Cabeçalho XML com suporte a imagens
    XMLStr := '<?xml version="1.0" encoding="UTF-8"?>' + sLineBreak +
              '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ' +
              'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">' + sLineBreak;

    // URL da página do artista
    XMLStr := XMLStr + '  <url>' + sLineBreak +
                       '    <loc>https://' + HostStr + '/</loc>' + sLineBreak +
                       '    <changefreq>weekly</changefreq>' + sLineBreak +
                       '    <priority>1.0</priority>' + sLineBreak;

    // Loop inserindo as fotos do portfólio no sitemap
    for i := 0 to High(Perfil.FotosGaleria) do
    begin
      UrlFotoAbsoluta := Perfil.FotosGaleria[i];
      if Pos('/', UrlFotoAbsoluta) <> 1 then UrlFotoAbsoluta := '/' + UrlFotoAbsoluta;
      UrlFotoAbsoluta := 'https://' + HostStr + UrlFotoAbsoluta;

      XMLStr := XMLStr + '    <image:image>' + sLineBreak +
                         '      <image:loc>' + UrlFotoAbsoluta + '</image:loc>' + sLineBreak +
                         '      <image:title>Tatuagem por ' + Perfil.Titulo + '</image:title>' + sLineBreak +
                         '    </image:image>' + sLineBreak;
    end;

    XMLStr := XMLStr + '  </url>' + sLineBreak +
                       '</urlset>';

    res.ContentType('application/xml; charset=utf-8').Send(XMLStr);
  except
    on E: Exception do
      TJsonView.SendHtml(res, 500, 'Internal Server Error');
  end;
end;


procedure HandlePortifolioUpdateBasico(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja, titulo, subtitulo, bio: string;
  json_req: TJSONObject;
begin
  json_req := nil;
  try
    try
      id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      if Id_Loja = '' then
      begin
        TJsonView.SendError(res, 400, 'Id não encontrado.');
        exit;
      end;

      json_req := TJSONObject(GetJSON(req.Body));
      if not Assigned(json_req) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      titulo   := TSecurityService.SanitizeInput(json_req.find('titulo'   ).AsString);
      subtitulo:= TSecurityService.SanitizeInput(json_req.find('subtitulo').AsString);
      bio      := TSecurityService.SanitizeInput(json_req.find('bio'      ).AsString);

      TProtifolioModel.PortifolioUpdateBasico(id_loja, titulo, subtitulo, bio);

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
      try
        id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro ao ler token: ' + E.Message);
        Exit;
      end;
      end;

      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Token inválido ou sem id_loja.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if Assigned(lJSONData) and (lJSONData.JSONType = jtObject) then
        jsonreq := TJSONObject(lJSONData)
      else
      begin
        TJsonView.SendError(res, 400, 'JSON inválido.');
        if Assigned(lJSONData) then lJSONData.Free;
        Exit;
      end;

      id_site      := jsonreq.Get('id_site',       0);
      nome_arquivo := jsonreq.Get('nome_arquivo', '');
      base64_str   := jsonreq.Get('imagem_base64','');

      if (id_loja = '') or (base64_str = '') then
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
  slug, nome, texto, foto_base64, extensao_foto, id_loja, err: string;
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
        TJsonView.SendError(res, 500, e.Message);
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
        TJsonView.SendError(res, 500, e.Message);
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

      id_depoimento := jsonreq.Get('id_depoimento', 0);

      if id_depoimento <= 0 then
      begin
        TJsonView.SendError(res, 400, 'ID do depoimento inválido.');
        Exit;
      end;

      TProtifolioModel.AprovarDepoimento(id_depoimento);

      TJsonView.SendSuccess(res);
    except
      on e: exception do
        TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
  end;
end;

class procedure TPortifolioController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/update_portifolio_basico', HandlePortifolioUpdateBasico);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/update', HandlePortifolioUpdate);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/portfolio/info/:id_loja', HandlerPortifolioGetInfo);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/remove', HandleRemoveItem);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/portfolio/galeria/:id_portfolio', HandleGetGaleria);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/avatar', HandleUpdateAvatar);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/foto-bio', HandleUpdateFotoBio);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/foto-capa', HandleUpdateFotoCapa);

  THorse.Get('/loja/:slug', HandlerPortifolioGet);
  THorse.get('/', HandlerPortifolioGet);

  THorse.Get('/robots.txt', HandlerRobotsGet);
  THorse.Get('/sitemap.xml', HandlerSitemapGet);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Post('api/v1/portfolio/upload', HandleUploadFoto);

  THorse.Post('api/v1/depoimentos', HandleDepoimentoCreate);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Get('api/v1/depoimentos/pendentes', HandleGetDepoimentosPendentes);

  THorse.AddCallback(HorseJWT(TConfig.Token))
    .Put('api/v1/depoimentos/aprovar', HandleAprovarDepoimento);
end;

end.


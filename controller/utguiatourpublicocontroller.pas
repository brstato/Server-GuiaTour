unit utguiatourpublicocontroller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Horse, fpjson, jsonparser, uJsonView,
  uguiatourutils, uratelimit, uguiatourpontoview,
  upontoturisticomodel, ubuscamodel, ueventomodel, uguiatourseo;

type

  { TGuiaTourPublicoController }

  TGuiaTourPublicoController = class
  public
    class procedure RegisterRoutes();
  end;

implementation

const
  TIPOS_EVENTO: array[0..4] of string = ('card', 'pin', 'ver', 'whats', 'rota');

// GET /api/v1/explorar/buscar?q=
procedure HandlerBuscar(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  jsonRes: TJSONObject;
begin
  try
    // TBuscaModel.Buscar já libera o que criou se falhar;
    // SendResponseJsonObject libera jsonRes ao terminar.
    jsonRes := TBuscaModel.Buscar(LimparTermo(Req.Query['q']));
    Res.AddHeader('Cache-Control', 'public, max-age=30, s-maxage=60');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except
    on E: Exception do
    begin
      WriteLn('Erro em: HandlerBuscar - ' + E.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

// GET /ponto/:slug  (HTML renderizado no servidor)
procedure HandlerPaginaPonto(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  slug, html: string;
  ponto: TJSONObject;
begin
  ponto := nil;
  try
    try
      slug := Req.Params['slug'];

      if not SlugValido(slug) then
      begin
        TJsonView.SendHtml(Res, 404, '<h1>Ponto turístico não encontrado.</h1>');
        Exit;
      end;

      ponto := TPontoTuristicoModel.GetBySlug(slug);
      if not Assigned(ponto) then
      begin
        TJsonView.SendHtml(Res, 404, '<h1>Ponto turístico não encontrado.</h1>');
        Exit;
      end;

      html := TPontoView.Render(ponto, slug);

      Res.AddHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
      TJsonView.SendHtml(Res, 200, html);
    except
      on E: Exception do
      begin
        WriteLn('Erro em: HandlerPaginaPonto - ' + E.Message);
        TJsonView.SendHtml(Res, 500,
          '<h1>Erro interno do servidor</h1><p>Tente novamente mais tarde.</p>');
      end;
    end;
  finally
    ponto.Free;
  end;
end;

// POST /api/v1/evento  — sempre responde 204 (nunca revela o que foi aceito)
procedure HandlerEvento(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  jsonData: TJSONData;
  body: TJSONObject;
  lojaSlug, pontoSlug, tipo, ip: string;
begin
  body := nil;
  try
    try
      if EhBot(Req.Headers['User-Agent']) then Exit;
      if (Trim(Req.Body) = '') or (Length(Req.Body) > 2048) then Exit;

      jsonData := GetJSON(Req.Body);
      if jsonData.JSONType <> jtObject then
      begin
        jsonData.Free;
        Exit;
      end;
      body := TJSONObject(jsonData);

      lojaSlug  := body.Get('loja', '');
      pontoSlug := body.Get('ponto', '');
      tipo      := LowerCase(body.Get('tipo', ''));

      if not SlugValido(lojaSlug) then Exit;
      if (pontoSlug <> '') and not SlugValido(pontoSlug) then pontoSlug := '';
      if IndexStr(tipo, TIPOS_EVENTO) < 0 then Exit;

      ip := Req.Headers['CF-Connecting-IP'];
      if ip = '' then ip := Req.Headers['X-Forwarded-For'];
      if ip = '' then ip := 'desconhecido';

      // 1 evento por IP + loja + tipo a cada 30 s
      if not TDedupe.Permitir(ip + '|' + lojaSlug + '|' + tipo, 30000) then Exit;

      TEventoModel.Registrar(lojaSlug, pontoSlug, tipo);
    except
      on E: Exception do
        WriteLn('Erro em: HandlerEvento - ' + E.Message);   // não propaga ao visitante
    end;
  finally
    body.Free;
    Res.Status(204).Send('');
  end;
end;

// GET /robots.txt
procedure HandlerRobots(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  Res.AddHeader('Cache-Control', 'public, max-age=3600');
  TJsonView.SendText(Res, 200, TGuiaTourSeo.Robots(Req.Headers['Host']));
end;

// Sitemaps (XML). O host api.* não publica sitemap.
procedure EnviarSitemap(Req: THorseRequest; Res: THorseResponse; Tipo: Integer);
var
  xml: string;
begin
  try
    if Pos('api.', LowerCase(Trim(Req.Headers['Host']))) = 1 then
    begin
      TJsonView.SendText(Res, 404, 'Not found');
      Exit;
    end;

    case Tipo of
      0: xml := TGuiaTourSeo.SitemapIndex;
      1: xml := TGuiaTourSeo.SitemapPontos;
    else
      xml := TGuiaTourSeo.SitemapLojas;
    end;

    Res.AddHeader('Cache-Control', 'public, max-age=3600, s-maxage=3600');
    Res.Status(200).ContentType('application/xml; charset=utf-8').Send(xml);
  except
    on E: Exception do
    begin
      WriteLn('Erro em: Sitemap - ' + E.Message);
      TJsonView.SendText(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerSitemapIndex(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  EnviarSitemap(Req, Res, 0);
end;

procedure HandlerSitemapPontos(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  EnviarSitemap(Req, Res, 1);
end;

procedure HandlerSitemapLojas(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  EnviarSitemap(Req, Res, 2);
end;

{ TGuiaTourPublicoController }

class procedure TGuiaTourPublicoController.RegisterRoutes();
begin
  THorse.Get('api/v1/explorar/buscar', HandlerBuscar);
  THorse.Get('/ponto/:slug', HandlerPaginaPonto);
  THorse.Post('api/v1/evento', HandlerEvento);
  THorse.Get('/robots.txt', HandlerRobots);
  THorse.Get('/sitemap.xml', HandlerSitemapIndex);
  THorse.Get('/sitemap-pontos.xml', HandlerSitemapPontos);
  THorse.Get('/sitemap-lojas.xml', HandlerSitemapLojas);
end;

end.

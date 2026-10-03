unit uguiatourseo;

{$mode delphi}{$H+}

// robots.txt e sitemaps do GuiaTour, gerados a partir do banco a cada consulta
// (com cache curto em memória). Pontos e comércios novos entram sozinhos.
//
//   /robots.txt            -> aponta para o índice
//   /sitemap.xml           -> índice (lista os sitemaps abaixo)
//   /sitemap-pontos.xml    -> /ponto/:slug   (ativo = TRUE) + fotos
//   /sitemap-lojas.xml     -> /loja/:slug    (validade >= hoje) + fotos
//
// Para acrescentar outro sitemap no futuro (ex.: cidades): crie a função que
// gera o XML, registre a rota e inclua a linha em SitemapIndex.

interface

uses
  Classes, SysUtils, db, syncobjs, Generics.Collections, uguiatourutils, ugetdata;

const
  SEO_BASE_URL       = 'https://guiatour.online';
  SEO_CACHE_SEGUNDOS = 300;    // pontos/comércios novos aparecem em até 5 min
  SEO_MAX_URLS       = 50000;  // limite do protocolo por arquivo de sitemap
  SEO_MAX_FOTOS_URL  = 10;     // fotos por página no sitemap de imagens

type
  TGuiaTourSeo = class
  public
    class function Robots(const Host: string): string;
    class function SitemapIndex: string;
    class function SitemapPontos: string;
    class function SitemapLojas: string;

    // Montagem do XML a partir de datasets (separada do acesso ao banco para
    // poder ser testada sem Firebird).
    //   Pontos : campos id, slug, capa            Galeria: id_ponto, url_foto
    //   Lojas  : campos slug, site_id, avatar, foto_capa   Galeria: id_site, url_foto
    class function MontarPontosXml(Pontos, Galeria: TDataSet): string;
    class function MontarLojasXml(Lojas, Galeria: TDataSet): string;

    // Esquece o cache (pode ser chamado depois de criar/editar ponto ou loja).
    class procedure LimparCache;
  end;

implementation

type
  TCacheItem = record
    Texto: string;
    Expira: TDateTime;
  end;

var
  Lock: TCriticalSection;
  Cache: array[0..1] of TCacheItem;   // 0 = pontos, 1 = lojas

const
  XML_CAB = '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding;
  XML_URLSET = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ' +
    'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">' + LineEnding;

// ---------- helpers ----------

function CacheLer(Idx: Integer; out Texto: string): Boolean;
begin
  Lock.Enter;
  try
    Result := (Cache[Idx].Texto <> '') and (Now < Cache[Idx].Expira);
    if Result then Texto := Cache[Idx].Texto else Texto := '';
  finally
    Lock.Leave;
  end;
end;

procedure CacheGravar(Idx: Integer; const Texto: string);
begin
  Lock.Enter;
  try
    Cache[Idx].Texto  := Texto;
    Cache[Idx].Expira := Now + SEO_CACHE_SEGUNDOS / 86400;
  finally
    Lock.Leave;
  end;
end;

// Foto relativa vira absoluta; endereço externo só se for http(s). Vazio = ignorar.
function FotoAbsoluta(const U: string): string;
var
  s: string;
begin
  Result := '';
  s := Trim(U);
  if s = '' then Exit;
  if (Pos('https://', s) = 1) or (Pos('http://', s) = 1) then
    Result := s
  else
  begin
    if s[1] <> '/' then s := '/' + s;
    if (Length(s) > 1) and (s[2] = '/') then Exit;   // "//host/..." não é caminho nosso
    Result := SEO_BASE_URL + s;
  end;
end;

procedure AddFoto(Fotos: TStringList; const U: string);
var
  f: string;
begin
  f := FotoAbsoluta(U);
  if (f <> '') and (Fotos.IndexOf(f) < 0) and (Fotos.Count < SEO_MAX_FOTOS_URL) then
    Fotos.Add(f);
end;

function UrlXml(const Caminho: string; Fotos: TStringList): string;
var
  i: Integer;
begin
  Result := '  <url>' + LineEnding +
            '    <loc>' + HtmlEsc(SEO_BASE_URL + Caminho) + '</loc>' + LineEnding;
  for i := 0 to Fotos.Count - 1 do
    Result := Result + '    <image:image><image:loc>' + HtmlEsc(Fotos[i]) +
      '</image:loc></image:image>' + LineEnding;
  Result := Result + '  </url>' + LineEnding;
end;

// Guarda as fotos de cada página (chave = id), no máximo SEO_MAX_FOTOS_URL por chave.
function LerGaleria(Galeria: TDataSet; const CampoId: string): TObjectDictionary<Integer, TStringList>;
var
  id: Integer;
  lista: TStringList;
begin
  Result := TObjectDictionary<Integer, TStringList>.Create([doOwnsValues]);
  if (Galeria = nil) or Galeria.IsEmpty then Exit;
  Galeria.First;
  while not Galeria.EOF do
  begin
    id := Galeria.FieldByName(CampoId).AsInteger;
    if not Result.TryGetValue(id, lista) then
    begin
      lista := TStringList.Create;
      Result.Add(id, lista);
    end;
    AddFoto(lista, Galeria.FieldByName('url_foto').AsString);
    Galeria.Next;
  end;
end;

// ---------- montagem do XML ----------

class function TGuiaTourSeo.MontarPontosXml(Pontos, Galeria: TDataSet): string;
var
  gal: TObjectDictionary<Integer, TStringList>;
  fotos, extra: TStringList;
  slug: string;
  n, i: Integer;
begin
  Result := XML_CAB + XML_URLSET;
  gal := LerGaleria(Galeria, 'id_ponto');
  fotos := TStringList.Create;
  try
    n := 0;
    if (Pontos <> nil) and (not Pontos.IsEmpty) then
    begin
      Pontos.First;
      while (not Pontos.EOF) and (n < SEO_MAX_URLS) do
      begin
        slug := Pontos.FieldByName('slug').AsString;
        if SlugValido(slug) then   // só o que a rota /ponto/:slug aceita
        begin
          fotos.Clear;
          AddFoto(fotos, Pontos.FieldByName('capa').AsString);
          if gal.TryGetValue(Pontos.FieldByName('id').AsInteger, extra) then
            for i := 0 to extra.Count - 1 do
              if (fotos.IndexOf(extra[i]) < 0) and (fotos.Count < SEO_MAX_FOTOS_URL) then
                fotos.Add(extra[i]);
          Result := Result + UrlXml('/ponto/' + slug, fotos);
          Inc(n);
        end;
        Pontos.Next;
      end;
    end;
  finally
    fotos.Free;
    gal.Free;
  end;
  Result := Result + '</urlset>' + LineEnding;
end;

class function TGuiaTourSeo.MontarLojasXml(Lojas, Galeria: TDataSet): string;
var
  gal: TObjectDictionary<Integer, TStringList>;
  fotos, extra: TStringList;
  slug: string;
  n, i: Integer;
begin
  Result := XML_CAB + XML_URLSET;
  gal := LerGaleria(Galeria, 'id_site');
  fotos := TStringList.Create;
  try
    n := 0;
    if (Lojas <> nil) and (not Lojas.IsEmpty) then
    begin
      Lojas.First;
      while (not Lojas.EOF) and (n < SEO_MAX_URLS) do
      begin
        slug := Lojas.FieldByName('slug').AsString;
        if SlugValido(slug) then
        begin
          fotos.Clear;
          AddFoto(fotos, Lojas.FieldByName('foto_capa').AsString);
          AddFoto(fotos, Lojas.FieldByName('avatar').AsString);
          if (not Lojas.FieldByName('site_id').IsNull) and
             gal.TryGetValue(Lojas.FieldByName('site_id').AsInteger, extra) then
            for i := 0 to extra.Count - 1 do
              if (fotos.IndexOf(extra[i]) < 0) and (fotos.Count < SEO_MAX_FOTOS_URL) then
                fotos.Add(extra[i]);
          Result := Result + UrlXml('/loja/' + slug, fotos);
          Inc(n);
        end;
        Lojas.Next;
      end;
    end;
  finally
    fotos.Free;
    gal.Free;
  end;
  Result := Result + '</urlset>' + LineEnding;
end;

// ---------- acesso ao banco (com cache) ----------

class function TGuiaTourSeo.SitemapPontos: string;
var
  dsPontos, dsGaleria: TDataSet;
begin
  if CacheLer(0, Result) then Exit;
  dsPontos := nil;
  dsGaleria := nil;
  try
    // Mesmo critério de TPontoTuristicoModel.GetBySlug: ativo = TRUE.
    dsPontos := TGetData.getData(
      'SELECT p.id, p.slug, p.capa FROM ponto_turistico p ' +
      'WHERE p.ativo = TRUE AND p.slug IS NOT NULL ' +
      'ORDER BY p.id ROWS ' + IntToStr(SEO_MAX_URLS) + ';',
      [],
      True
    );
    dsGaleria := TGetData.getData(
      'SELECT g.id_ponto, g.url_foto FROM ponto_turistico_galeria g ' +
      'JOIN ponto_turistico p ON p.id = g.id_ponto ' +
      'WHERE p.ativo = TRUE ' +
      'ORDER BY g.id_ponto, g.ordem, g.id;',
      [],
      True
    );
    Result := MontarPontosXml(dsPontos, dsGaleria);
    CacheGravar(0, Result);
  finally
    dsPontos.Free;
    dsGaleria.Free;
  end;
end;

class function TGuiaTourSeo.SitemapLojas: string;
var
  dsLojas, dsGaleria: TDataSet;
begin
  if CacheLer(1, Result) then Exit;
  dsLojas := nil;
  dsGaleria := nil;
  try
    // Mesmo critério de TProtifolioModel.GetBySlug: loja com validade em dia.
    dsLojas := TGetData.getData(
      'SELECT l.slug, s.id AS site_id, s.avatar, s.foto_capa FROM loja l ' +
      'LEFT JOIN site s ON s.id_loja_ex = l.uuid ' +
      'WHERE l.slug IS NOT NULL AND l.validade >= CURRENT_DATE ' +
      'ORDER BY l.id ROWS ' + IntToStr(SEO_MAX_URLS) + ';',
      [],
      True
    );
    dsGaleria := TGetData.getData(
      'SELECT g.id_site, g.url_foto FROM site_galeria g ' +
      'JOIN site s ON s.id = g.id_site ' +
      'JOIN loja l ON l.uuid = s.id_loja_ex ' +
      'WHERE l.slug IS NOT NULL AND l.validade >= CURRENT_DATE ' +
      'ORDER BY g.id_site, g.id DESC;',
      [],
      True
    );
    Result := MontarLojasXml(dsLojas, dsGaleria);
    CacheGravar(1, Result);
  finally
    dsLojas.Free;
    dsGaleria.Free;
  end;
end;

class function TGuiaTourSeo.SitemapIndex: string;
begin
  Result := XML_CAB +
    '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + LineEnding +
    '  <sitemap><loc>' + SEO_BASE_URL + '/sitemap-pontos.xml</loc></sitemap>' + LineEnding +
    '  <sitemap><loc>' + SEO_BASE_URL + '/sitemap-lojas.xml</loc></sitemap>' + LineEnding +
    '</sitemapindex>' + LineEnding;
end;

class function TGuiaTourSeo.Robots(const Host: string): string;
begin
  // api.guiatour.online atende o painel: nada ali deve ser indexado.
  if Pos('api.', LowerCase(Trim(Host))) = 1 then
    Result := 'User-agent: *' + LineEnding + 'Disallow: /' + LineEnding
  else
    Result := 'User-agent: *' + LineEnding +
              'Allow: /' + LineEnding + LineEnding +
              'Sitemap: ' + SEO_BASE_URL + '/sitemap.xml' + LineEnding;
end;

class procedure TGuiaTourSeo.LimparCache;
var
  i: Integer;
begin
  Lock.Enter;
  try
    for i := Low(Cache) to High(Cache) do
    begin
      Cache[i].Texto  := '';
      Cache[i].Expira := 0;
    end;
  finally
    Lock.Leave;
  end;
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  Lock.Free;

end.

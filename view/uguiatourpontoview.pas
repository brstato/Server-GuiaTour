unit uguiatourpontoview;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, fpjson, StrUtils, Generics.Collections, uguiatourutils,
  upontoturisticomodel;

type

  { TPontoView }

  TPontoView = class
  public
    // Lê templates/ponto.html (ao lado do executável), busca comércios e pontos
    // próximos e renderiza a página completa.
    class function Render(Ponto: TJSONObject; const Slug: string): string;
    // Renderiza a partir de um template já carregado (útil para testes).
    // Comercios e Proximos são opcionais; a view NÃO assume a posse deles.
    class function RenderTemplate(const Tpl: string; Ponto: TJSONObject;
      const Slug: string; Comercios: TJSONArray = nil;
      Proximos: TJSONArray = nil; Categorias: TJSONArray = nil): string;
  end;

implementation

const
  BASE_URL = 'https://guiatour.online';
  REL_DESTAQUE = ' rel="sponsored"';
  MAX_FOTOS_GRADE = 7;

function UrlAbsoluta(const Caminho: string): string;
begin
  if Caminho = '' then Exit('');
  if (Pos('http://', Caminho) = 1) or (Pos('https://', Caminho) = 1) then
    Exit(Caminho);
  if Caminho[1] = '/' then
    Result := BASE_URL + Caminho
  else
    Result := BASE_URL + '/' + Caminho;
end;

// Cada linha não vazia vira um <p> já escapado.
function HistoriaParaHtml(const S: string): string;
var
  L: TStringList;
  i: Integer;
  linha: string;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := S;
    for i := 0 to L.Count - 1 do
    begin
      linha := Trim(L[i]);
      if linha <> '' then
        Result := Result + '<p>' + HtmlEsc(linha) + '</p>';
    end;
  finally
    L.Free;
  end;
end;

function Resumir(const S: string; Max: Integer): string;
begin
  Result := Trim(S);
  if Utf8Len(Result) > Max then
    Result := Utf8Corta(Result, Max - 1) + '…';
end;

// Só caminho absoluto do próprio site ou http(s); qualquer outra coisa vira ''.
function UrlSegura(const U: string): string;
begin
  Result := '';
  if U = '' then Exit;
  if ((U[1] = '/') and not ((Length(U) > 1) and (U[2] = '/'))) or
     (Pos('http://', U) = 1) or (Pos('https://', U) = 1) then
    Result := U;
end;

function FmtVirgula(V: Double; Casas: Integer): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := ',';
  Result := Format('%.*f', [Casas, V], fs);
end;

// Mesma regra do JavaScript: até 15 min a pé mostra minutos, depois km.
function FmtDist(Km: Double): string;
var
  m: Double;
  min: Integer;
begin
  m := Km * 1000;
  if m / 80 <= 15 then
  begin
    min := Round(m / 80);
    if min < 1 then min := 1;
    Result := IntToStr(min) + ' min a pé';
  end
  else if Km >= 10 then
    Result := IntToStr(Round(Km)) + ' km'
  else
    Result := FmtVirgula(Km, 1) + ' km';
end;

function EstrelasHtml(Nota: Double; Total: Integer): string;
var
  nt: string;
begin
  Result := '';
  if Total <= 0 then Exit;
  if Nota < 0 then Nota := 0;
  if Nota > 5 then Nota := 5;
  nt := FmtVirgula(Nota, 1);
  Result := '<span class="rate"><span class="stars" role="img" aria-label="Nota ' + nt +
    ' de 5, ' + IntToStr(Total) + IfThen(Total = 1, ' avaliação', ' avaliações') +
    '" style="--p:' + IntToStr(Round(Nota / 5 * 100)) + '%"></span>' + nt +
    '<small>(' + IntToStr(Total) + ')</small></span>';
end;

// Grade de fotos: botões com <img> já escritos no HTML (o JavaScript só liga o clique).
function GaleriaParaHtml(Galeria: TJSONArray; const Nome, Cidade: string): string;
var
  i, n, total: Integer;
  url, alt: string;
begin
  Result := '';
  if Galeria = nil then Exit;
  total := 0;
  for i := 0 to Galeria.Count - 1 do
    if (Galeria.Items[i].JSONType = jtObject) and
       (UrlSegura(TJSONObject(Galeria.Items[i]).Get('url', '')) <> '') then
      Inc(total);
  n := 0;
  for i := 0 to Galeria.Count - 1 do
  begin
    if Galeria.Items[i].JSONType <> jtObject then Continue;
    url := UrlSegura(TJSONObject(Galeria.Items[i]).Get('url', ''));
    if url = '' then Continue;
    if n >= MAX_FOTOS_GRADE then Break;
    alt := 'Foto ' + IntToStr(n + 1) + ' de ' + Nome;
    if Cidade <> '' then alt := alt + ' em ' + Cidade;
    Result := Result + '<button type="button" data-i="' + IntToStr(n) +
      '" aria-label="Ampliar foto ' + IntToStr(n + 1) + '"><img src="' + HtmlEsc(url) +
      '" alt="' + HtmlEsc(alt) + '" loading="lazy" decoding="async">';
    if (n = MAX_FOTOS_GRADE - 1) and (total > MAX_FOTOS_GRADE) then
      Result := Result + '<span class="more">+' + IntToStr(total - MAX_FOTOS_GRADE) + '</span>';
    Result := Result + '</button>';
    Inc(n);
  end;
end;

// Cards dos comércios com link real para a página de cada um.
function ComerciosParaHtml(Arr: TJSONArray; LatPonto, LngPonto: Double): string;
var
  i: Integer;
  o: TJSONObject;
  slug, nome, categoria, avatar, uuid, rel, rota, lat, lng: string;
  destacado: Boolean;
  fs: TFormatSettings;
begin
  if (Arr = nil) or (Arr.Count = 0) then
    Exit('<li class="info">Ainda não há comércios cadastrados por aqui. ' +
         'Veja outros lugares logo abaixo.</li>');
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := '';
  for i := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[i].JSONType <> jtObject then Continue;
    o := TJSONObject(Arr.Items[i]);
    slug := o.Get('slug', '');
    if not SlugValido(slug) then Continue;
    uuid      := o.Get('uuid', '');
    nome      := o.Get('nome', '');
    categoria := o.Get('categoria', '');
    avatar    := UrlSegura(o.Get('avatar', ''));
    destacado := o.Get('destacado', False);
    if destacado then rel := REL_DESTAQUE else rel := '';

    Result := Result + '<li data-id="' + HtmlEsc(uuid) + '"><button class="pick" type="button">';
    if avatar <> '' then
      Result := Result + '<img class="av" src="' + HtmlEsc(avatar) + '" alt="" loading="lazy">'
    else
      Result := Result + '<span class="av">' + HtmlEsc(Utf8Corta(nome, 1)) + '</span>';
    Result := Result + '<span><span class="nm">' + HtmlEsc(nome);
    if destacado then Result := Result + '<span class="tag">Destaque</span>';
    Result := Result + '</span><span class="ct">' + HtmlEsc(categoria) + '</span>' +
      EstrelasHtml(o.Get('nota_media', 0.0), o.Get('total_avaliacoes', 0)) +
      '<span class="ds">' + FmtDist(o.Get('distancia_km', 0.0)) + '</span></span></button>' +
      '<div class="act"><a class="btn" href="/loja/' + HtmlEsc(slug) + '"' + rel + '>Ver página</a>';

    lat := FloatToStr(o.Get('latitude', 0.0), fs);
    lng := FloatToStr(o.Get('longitude', 0.0), fs);
    if (o.Get('latitude', 0.0) <> 0) or (o.Get('longitude', 0.0) <> 0) then
    begin
      rota := 'https://www.google.com/maps/dir/?api=1&origin=' + FloatToStr(LatPonto, fs) + ',' +
        FloatToStr(LngPonto, fs) + '&destination=' + lat + ',' + lng + '&travelmode=walking';
      Result := Result + '<a class="btn alt" href="' + HtmlEsc(rota) +
        '" target="_blank" rel="noopener">Como chegar</a>';
    end;
    Result := Result + '</div></li>';
  end;
  if Result = '' then Result := '<li class="info">Ainda não há comércios cadastrados por aqui.</li>';
end;

// Cards de categoria (filtro). O JavaScript liga o clique e desenha o ícone.
function CategoriasParaHtml(Arr: TJSONArray): string;
var
  i, qtd: Integer;
  o: TJSONObject;
  slug, sub: string;
begin
  Result := '';
  if (Arr = nil) or (Arr.Count < 2) then Exit;
  Result := '<button type="button" class="cc" data-cat="" aria-pressed="true">' +
    '<i class="ic" aria-hidden="true"></i><span><span class="cn">Tudo</span>' +
    '<span class="cs">Todos os tipos</span></span></button>';
  for i := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[i].JSONType <> jtObject then Continue;
    o := TJSONObject(Arr.Items[i]);
    slug := o.Get('slug', '');
    if not SlugValido(slug) then Continue;
    qtd := o.Get('qtd_regiao', 0);
    if qtd > 0 then
      sub := IntToStr(qtd) + ' por perto'
    else
      sub := 'a ' + FmtDist(o.Get('distancia_min_km', 0.0));
    Result := Result + '<button type="button" class="cc" data-cat="' + HtmlEsc(slug) +
      '" aria-pressed="false"><i class="ic" aria-hidden="true"></i><span><span class="cn">' +
      HtmlEsc(o.Get('nome', '')) + '</span><span class="cs">' + HtmlEsc(sub) +
      '</span></span></button>';
  end;
end;

// "Mais lugares para conhecer": links entre os pontos (malha interna).
function ProximosParaHtml(Arr: TJSONArray): string;
var
  i: Integer;
  o: TJSONObject;
  slug, nome, capa: string;
begin
  if (Arr = nil) or (Arr.Count = 0) then
    Exit('<li class="info">Ainda não há outros lugares cadastrados nesta região.</li>');
  Result := '';
  for i := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[i].JSONType <> jtObject then Continue;
    o := TJSONObject(Arr.Items[i]);
    slug := o.Get('slug', '');
    if not SlugValido(slug) then Continue;
    nome := o.Get('nome', '');
    capa := UrlSegura(o.Get('capa', ''));
    Result := Result + '<li><a href="/ponto/' + HtmlEsc(slug) + '"><div class="ph">';
    if capa <> '' then
      Result := Result + '<img src="' + HtmlEsc(capa) + '" alt="' + HtmlEsc('Foto de ' + nome) +
        '" loading="lazy" decoding="async">';
    Result := Result + '</div><span class="nm">' + HtmlEsc(nome) + '</span><span class="ct">' +
      HtmlEsc(o.Get('categoria', '')) + '</span><span class="ds">a ' +
      FmtDist(o.Get('distancia_km', 0.0)) + '</span></a></li>';
  end;
  if Result = '' then
    Result := '<li class="info">Ainda não há outros lugares cadastrados nesta região.</li>';
end;

// Substituição em passada única. Só é placeholder o padrão {{NOME}} com NOME
// formado por A-Z, 0-9 e "_". Qualquer outro "{{" (ex.: dentro de uma string JS)
// é mantido como texto. O valor inserido NUNCA é reinterpretado.
function SubstituirPlaceholders(const Tpl: string;
  Vars: TDictionary<string, string>): string;
var
  ss: TStringStream;
  i, j, len: Integer;
  nome, valor: string;
begin
  ss := TStringStream.Create('');
  try
    len := Length(Tpl);
    i := 1;
    while i <= len do
    begin
      if (Tpl[i] = '{') and (i < len) and (Tpl[i + 1] = '{') then
      begin
        j := i + 2;
        while (j <= len) and (Tpl[j] in ['A'..'Z', '0'..'9', '_']) do Inc(j);
        if (j > i + 2) and (j < len) and (Tpl[j] = '}') and (Tpl[j + 1] = '}') then
        begin
          nome := Copy(Tpl, i + 2, j - i - 2);
          if not Vars.TryGetValue(nome, valor) then valor := '';
          ss.WriteString(valor);
          i := j + 2;
          Continue;
        end;
      end;
      ss.WriteString(Tpl[i]);
      Inc(i);
    end;
    Result := ss.DataString;
  finally
    ss.Free;
  end;
end;

function MontarSchema(Ponto: TJSONObject; const UrlCanonica, UrlCapa: string): string;
var
  o, geo, addr: TJSONObject;
  imgs: TJSONArray;
  galeria: TJSONArray;
  i: Integer;
  u: string;
begin
  o := TJSONObject.Create;
  try
    o.Add('@context', 'https://schema.org');
    o.Add('@type', 'TouristAttraction');
    o.Add('name', Ponto.Get('nome', ''));
    o.Add('description', Ponto.Get('resumo', ''));
    o.Add('url', UrlCanonica);
    // imagens: capa + até 5 fotos da galeria
    imgs := TJSONArray.Create;
    if UrlCapa <> '' then imgs.Add(UrlCapa);
    galeria := Ponto.Get('galeria', TJSONArray(nil));
    if galeria <> nil then
      for i := 0 to galeria.Count - 1 do
      begin
        if imgs.Count >= 6 then Break;
        if galeria.Items[i].JSONType <> jtObject then Continue;
        u := UrlAbsoluta(UrlSegura(TJSONObject(galeria.Items[i]).Get('url', '')));
        if u <> '' then imgs.Add(u);
      end;
    if imgs.Count > 0 then o.Add('image', imgs) else imgs.Free;

    geo := TJSONObject.Create;
    geo.Add('@type', 'GeoCoordinates');
    geo.Add('latitude',  Ponto.Get('latitude',  0.0));
    geo.Add('longitude', Ponto.Get('longitude', 0.0));
    o.Add('geo', geo);

    addr := TJSONObject.Create;
    addr.Add('@type', 'PostalAddress');
    addr.Add('addressLocality', Ponto.Get('cidade', ''));
    addr.Add('addressRegion',   Ponto.Get('uf', ''));
    addr.Add('addressCountry',  'BR');
    o.Add('address', addr);

    Result := JsonParaScript(o.AsJSON);
  finally
    o.Free;
  end;
end;

{ TPontoView }

class function TPontoView.RenderTemplate(const Tpl: string; Ponto: TJSONObject;
  const Slug: string; Comercios: TJSONArray; Proximos: TJSONArray;
  Categorias: TJSONArray): string;
var
  Vars: TDictionary<string, string>;
  nome, resumo, cidade, uf, categoria: string;
  urlCanonica, urlCapa, descricao, galeriaHtml: string;
  galeria: TJSONArray;
begin
  nome      := Ponto.Get('nome', '');
  resumo    := Ponto.Get('resumo', '');
  cidade    := Ponto.Get('cidade', '');
  uf        := Ponto.Get('uf', '');
  categoria := Ponto.Get('categoria_nome', '');

  urlCanonica := BASE_URL + '/ponto/' + Slug;
  urlCapa     := UrlAbsoluta(Ponto.Get('capa', ''));
  descricao   := Resumir(resumo, 155);

  galeria     := Ponto.Get('galeria', TJSONArray(nil));
  galeriaHtml := GaleriaParaHtml(galeria, nome, cidade);

  Vars := TDictionary<string, string>.Create;
  try
    Vars.Add('PAGE_TITLE',          HtmlEsc(nome + ' em ' + cidade + ' | GuiaTour'));
    Vars.Add('META_DESCRIPTION',    HtmlEsc(descricao));
    Vars.Add('CANONICAL_URL',       HtmlEsc(urlCanonica));
    Vars.Add('OG_TITLE',            HtmlEsc(nome));
    Vars.Add('OG_DESCRIPTION',      HtmlEsc(descricao));
    Vars.Add('OG_IMAGE_URL',        HtmlEsc(urlCapa));

    Vars.Add('PONTO_SLUG',          HtmlEsc(Slug));
    Vars.Add('PONTO_NOME',          HtmlEsc(nome));
    Vars.Add('PONTO_CATEGORIA',     HtmlEsc(categoria));
    Vars.Add('PONTO_CIDADE',        HtmlEsc(cidade + ' - ' + uf));
    Vars.Add('PONTO_RESUMO',        HtmlEsc(resumo));
    Vars.Add('PONTO_HISTORIA_HTML', HistoriaParaHtml(Ponto.Get('historia', '')));
    Vars.Add('PONTO_CAPA_URL',      HtmlEsc(urlCapa));

    // Blocos já escritos no HTML (SEO): fotos, comércios e pontos vizinhos.
    Vars.Add('PONTO_GALERIA_HTML',    galeriaHtml);
    Vars.Add('GAL_HIDDEN',            IfThen(galeriaHtml = '', 'hidden', ''));
    Vars.Add('CATEGORIAS_HTML',       CategoriasParaHtml(Categorias));
    Vars.Add('COMERCIOS_HTML',        ComerciosParaHtml(Comercios,
      Ponto.Get('latitude', 0.0), Ponto.Get('longitude', 0.0)));
    Vars.Add('PONTOS_PROXIMOS_HTML',  ProximosParaHtml(Proximos));

    Vars.Add('SCHEMA_JSON', MontarSchema(Ponto, urlCanonica, urlCapa));
    Vars.Add('PONTO_JSON',  JsonParaScript(Ponto.AsJSON));

    Result := SubstituirPlaceholders(Tpl, Vars);
  finally
    Vars.Free;
  end;
end;

class function TPontoView.Render(Ponto: TJSONObject; const Slug: string): string;
var
  Tpl: TStringList;
  Comercios, Proximos, Categorias: TJSONArray;
begin
  Comercios := nil;
  Proximos := nil;
  Categorias := nil;
  Tpl := TStringList.Create;
  try
    Tpl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'templates/ponto.html');
    // Se uma das consultas falhar, a página sai sem esse bloco (o JavaScript completa).
    try Comercios  := TPontoTuristicoModel.GetComerciosProximos(Slug); except Comercios := nil; end;
    try Proximos   := TPontoTuristicoModel.GetPontosProximos(Slug, 6); except Proximos := nil; end;
    try Categorias := TPontoTuristicoModel.GetCategoriasProximas(Slug); except Categorias := nil; end;
    Result := RenderTemplate(Tpl.Text, Ponto, Slug, Comercios, Proximos, Categorias);
  finally
    Comercios.Free;
    Proximos.Free;
    Categorias.Free;
    Tpl.Free;
  end;
end;

end.

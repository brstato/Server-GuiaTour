unit uguiatourpontoview;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, fpjson, StrUtils, Generics.Collections, uguiatourutils;

type

  { TPontoView }

  TPontoView = class
  public
    // Lê ponto.html (ao lado do executável) e renderiza.
    class function Render(Ponto: TJSONObject; const Slug: string): string;
    // Renderiza a partir de um template já carregado (útil para testes).
    class function RenderTemplate(const Tpl: string; Ponto: TJSONObject;
      const Slug: string): string;
  end;

implementation

const
  BASE_URL = 'https://guiatour.online';

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
begin
  o := TJSONObject.Create;
  try
    o.Add('@context', 'https://schema.org');
    o.Add('@type', 'TouristAttraction');
    o.Add('name', Ponto.Get('nome', ''));
    o.Add('description', Ponto.Get('resumo', ''));
    o.Add('url', UrlCanonica);
    if UrlCapa <> '' then o.Add('image', UrlCapa);

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
  const Slug: string): string;
var
  Vars: TDictionary<string, string>;
  nome, resumo, cidade, uf, categoria: string;
  urlCanonica, urlCapa, descricao: string;
begin
  nome      := Ponto.Get('nome', '');
  resumo    := Ponto.Get('resumo', '');
  cidade    := Ponto.Get('cidade', '');
  uf        := Ponto.Get('uf', '');
  categoria := Ponto.Get('categoria_nome', '');

  urlCanonica := BASE_URL + '/ponto/' + Slug;
  urlCapa     := UrlAbsoluta(Ponto.Get('capa', ''));
  descricao   := Resumir(resumo, 155);

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
begin
  Tpl := TStringList.Create;
  try
    Tpl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'ponto.html');
    Result := RenderTemplate(Tpl.Text, Ponto, Slug);
  finally
    Tpl.Free;
  end;
end;

end.

unit uportifolioview;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  uportifoliomodel,
  //uguiatourdata,
  httpprotocol,
  fpjson,
  uguiatourutils;

type

  { TGuiatourView }

  TGuiatourView = class
    public
      class function Render(Perfil: TComercioPerfil; const Slug: string): string;
  end;

implementation

{ TGuiatourView }

// Caminho de imagem salvo no banco ("/imagens/..."). Só aceita letras, números e / . _ - :
// Qualquer outra coisa (aspas, espaços, < >) vira "" e a imagem não é exibida.
function CaminhoSeguro(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if not (S[i] in ['a'..'z', 'A'..'Z', '0'..'9', '/', '.', '_', '-', ':']) then Exit;
  Result := S;
end;

// URL absoluta da imagem a partir do caminho salvo (vazio se o caminho for inválido).
function UrlImagem(const BaseUrl, Caminho: string): string;
var
  c: string;
begin
  c := CaminhoSeguro(Caminho);
  if c = '' then Exit('');
  if Pos('/', c) <> 1 then c := '/' + c;
  Result := BaseUrl + c;
end;

function SchemaTypePorCategoria(const CategoriaSlug: string): string;
begin
  if CategoriaSlug = 'pousada' then
    Result := 'LodgingBusiness'
  else if CategoriaSlug = 'restaurante' then
    Result := 'Restaurant'
  else if CategoriaSlug = 'passeio' then
    Result := 'TouristAttraction'
  else
    Result := 'LocalBusiness'; // fallback seguro pra categoria não mapeada
end;

class function TGuiatourView.Render(Perfil: TComercioPerfil; const Slug: string): string;
var
  TemplateList: TStringList;
  HTMLFinal: string;
  BaseUrl, UrlAbsolutaAvatar, UrlAbsolutaFotoBio, UrlAbsolutaCapa: string;
  EnderecoCompleto, MapsUrl, WhatsLimpo, UrlCanonica: string;
  CarrosselHtml, UrlFotoAbsoluta: string;
  SchemaAggregateRating: string;
  VideoJson: TJSONObject;
  i, p: Integer;
begin
  // 1. Carrega o template HTML
  TemplateList := TStringList.Create;
  try
    TemplateList.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'index.html');
    HTMLFinal := TemplateList.Text;
  finally
    TemplateList.Free;
  end;

  // 2. URLs — path fixo, sem subdomínio (diferente do Inkers)
  BaseUrl     := 'https://guiatour.online';
  UrlCanonica := 'https://guiatour.online/loja/' + Slug;   // Slug já passou por verifica_slug

  // Caminhos de imagem: só caracteres seguros (servem em atributo HTML e no JSON-LD)
  UrlAbsolutaAvatar  := UrlImagem(BaseUrl, Perfil.Avatar);
  UrlAbsolutaFotoBio := UrlImagem(BaseUrl, Perfil.FotoBio);
  UrlAbsolutaCapa    := UrlImagem(BaseUrl, Perfil.foto_capa);

  // 3. Telefone: só dígitos (vai em href do WhatsApp e no JSON-LD)
  WhatsLimpo := SoDigitos(Perfil.WhatsApp);

  EnderecoCompleto := Perfil.Logradouro + ', ' + Perfil.Numero;
  if Perfil.Complemento <> '' then
    EnderecoCompleto := EnderecoCompleto + ' - ' + Perfil.Complemento;
  EnderecoCompleto := EnderecoCompleto + ' - ' + Perfil.Bairro + ', ' + Perfil.Cidade + ' - ' + Perfil.UF + ', ' + Perfil.CEP;

  // endereço codificado para URL (o HtmlEsc na hora de inserir cuida do atributo)
  MapsUrl := 'https://maps.google.com/maps?q=' + HTTPEncode(EnderecoCompleto) + '&t=&z=15&ie=UTF8&iwloc=&output=embed';

  // 4. Carrossel — sem alt "Tatuagem por", genérico pro comércio
  CarrosselHtml := '';
  for i := 0 to High(Perfil.FotosGaleria) do
  begin
    UrlFotoAbsoluta := UrlImagem(BaseUrl, Perfil.FotosGaleria[i]);
    if UrlFotoAbsoluta = '' then Continue;

    CarrosselHtml := CarrosselHtml +
      '<div class="carousel-item">' +
      '  <a href="' + UrlFotoAbsoluta + '" data-pswp-width="1200" data-pswp-height="1500" target="_blank">' +
      '    <img src="' + UrlFotoAbsoluta + '" alt="Foto de ' + HtmlEsc(Perfil.Titulo) + '" loading="lazy">' +
      '  </a>' +
      '</div>';
  end;

  // 5. Motor de substituição de tags
  //    HtmlEsc  -> texto e atributos HTML
  //    JsEsc    -> dentro de string do JSON-LD (<script type="application/ld+json">)
  //    *Seguro  -> IDs de rastreio, que vão dentro de string JavaScript
  HTMLFinal := StringReplace(HTMLFinal, '{{PAGE_TITLE}}', HtmlEsc(Perfil.slug), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{META_DESCRIPTION}}', HtmlEsc(Copy(Perfil.Bio, 1, 150) + '...'), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{META_AUTHOR}}', HtmlEsc(Perfil.Titulo), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{CANONICAL_URL}}', UrlCanonica, [rfReplaceAll]);

  HTMLFinal := StringReplace(HTMLFinal, '{{OG_DESCRIPTION}}', HtmlEsc(Copy(Perfil.Bio, 1, 150) + '...'), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{OG_IMAGE_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);

  // Schema.org JSON-LD — tipo varia por categoria, diferente do Inkers
  // (que era sempre TattooParlor fixo)
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_TYPE}}', SchemaTypePorCategoria(Perfil.CategoriaSlug), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_NOME}}', JsEsc(Perfil.Titulo), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_TELEFONE}}', WhatsLimpo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_LOGRADOURO}}', JsEsc(Perfil.Logradouro + ', ' + Perfil.Numero), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_CIDADE}}', JsEsc(Perfil.Cidade), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_UF}}', JsEsc(Perfil.Uf), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_CEP}}', JsEsc(Perfil.CEP), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{LATITUDE}}', JsEsc(Perfil.Latitude), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{LONGITUDE}}', JsEsc(Perfil.Longitude), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_DIAS}}', Perfil.SchemaDias, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_ABRE}}', JsEsc(Perfil.SchemaAbre), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_FECHA}}', JsEsc(Perfil.SchemaFecha), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_INSTAGRAM_URL}}', JsEsc(Perfil.Insta), [rfReplaceAll]);

  // aggregateRating — só entra no JSON-LD se houver ao menos 1 depoimento aprovado
  // (o schema.org/Google exige reviewCount >= 1 quando o campo existe)
  if Perfil.RatingCount > 0 then
    SchemaAggregateRating :=
      ',' + sLineBreak +
      '    "aggregateRating": {' + sLineBreak +
      '        "@type": "AggregateRating",' + sLineBreak +
      '        "ratingValue": "' + JsEsc(Perfil.RatingValue) + '",' + sLineBreak +
      '        "reviewCount": "' + IntToStr(Perfil.RatingCount) + '"' + sLineBreak +
      '    }'
  else
    SchemaAggregateRating := '';

  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_AGGREGATE_RATING}}', SchemaAggregateRating, [rfReplaceAll]);

  // Trackers: vão dentro de string JavaScript. Só passa ID no formato certo; o resto vira "".
  HTMLFinal := StringReplace(HTMLFinal, '{{META_PIXEL_ID}}', MetaPixelSeguro(Perfil.meta_pixel), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{GOOGLE_TAG_ID}}', GoogleTagSeguro(Perfil.google_id), [rfReplaceAll]);

  // Estrutura visual — "COMERCIO_*"
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_ID}}', HtmlEsc(Perfil.UUid), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_SLUG}}', HtmlEsc(Perfil.slug), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_NOME}}', HtmlEsc(Perfil.slug), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_BIO}}', HtmlEsc(Perfil.Subtitulo), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_BIO_LONGA}}', HtmlEsc(Perfil.Bio), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CIDADE}}', HtmlEsc(Perfil.Cidade + ' - ' + Perfil.Uf), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CAPA_URL}}', UrlAbsolutaCapa, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CATEGORIA_NOME}}', HtmlEsc(Perfil.CategoriaNome), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CATEGORIA_SLUG}}', HtmlEsc(Perfil.CategoriaSlug), [rfReplaceAll]);

  HTMLFinal := StringReplace(HTMLFinal, '{{ALT_FOTO_PERFIL}}', HtmlEsc('Foto de perfil de ' + Perfil.Titulo), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ALT_FOTO_BIO}}', HtmlEsc('Foto de ' + Perfil.Titulo), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_FULL_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_FULL_BIO_URL}}', UrlAbsolutaFotoBio, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_BIO_URL}}', UrlAbsolutaFotoBio, [rfReplaceAll]);

  // Contato e localização
  HTMLFinal := StringReplace(HTMLFinal, '{{WHATSAPP_NUMERO}}', WhatsLimpo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ENDERECO_COMPLETO}}', HtmlEsc(EnderecoCompleto), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ENDERECO_URL}}', HtmlEsc(HTTPEncode(EnderecoCompleto)), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{MAPS_EMBED_URL}}', HtmlEsc(MapsUrl), [rfReplaceAll]);

  // Componentes dinâmicos
  HTMLFinal := StringReplace(HTMLFinal, '{{CARROSSEL_ITENS}}', CarrosselHtml, [rfReplaceAll]);

  // JSON dentro de <script type="application/json">: "<" escapado para nunca fechar o </script>
  HTMLFinal := StringReplace(HTMLFinal, '{{DEPOIMENTOS_JSON}}', JsonParaScript(TProtifolioModel.GetDepoimentosAprovadosJson(Perfil.UUid)), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{DEPOIMENTOS_SUBMIT_URL}}', 'https://api.guiatour.online/api/v1/depoimentos', [rfReplaceAll]);

  // Vídeo: JSON {"url_video":"..."} dentro de <script type="application/json">.
  VideoJson := TJSONObject.Create(['url_video', Perfil.UrlVideo]);
  try
    HTMLFinal := StringReplace(HTMLFinal, '{{VIDEO_JSON}}', JsonParaScript(VideoJson.AsJSON), [rfReplaceAll]);
  finally
    VideoJson.Free;
  end;

  // Limpeza final: remove só placeholders que sobraram do template ({{ + A-Z 0-9 _ + }}).
  // Texto digitado com "{{" (bio, depoimento...) não apaga mais pedaços da página.
  i := 1;
  while i < Length(HTMLFinal) do
  begin
    if (HTMLFinal[i] = '{') and (HTMLFinal[i + 1] = '{') then
    begin
      p := i + 2;
      while (p <= Length(HTMLFinal)) and (HTMLFinal[p] in ['A'..'Z', '0'..'9', '_']) do
        Inc(p);
      if (p > i + 2) and (p < Length(HTMLFinal)) and
         (HTMLFinal[p] = '}') and (HTMLFinal[p + 1] = '}') then
      begin
        Delete(HTMLFinal, i, p + 2 - i);
        Continue;
      end;
    end;
    Inc(i);
  end;

  Result := HTMLFinal;
end;

end.

unit uportifolioview;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  uportifoliomodel,
  //uguiatourdata,
  httpprotocol;

type

  { TGuiatourView }

  TGuiatourView = class
    public
      class function Render(Perfil: TComercioPerfil; const Slug: string): string;
  end;

implementation

{ TGuiatourView }

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
  UrlCanonica := 'https://guiatour.online/loja/' + Slug;

  UrlAbsolutaAvatar := Perfil.Avatar;
  if Pos('/', UrlAbsolutaAvatar) <> 1 then UrlAbsolutaAvatar := '/' + UrlAbsolutaAvatar;
  UrlAbsolutaAvatar := BaseUrl + UrlAbsolutaAvatar;

  UrlAbsolutaFotoBio := Perfil.FotoBio;
  if Pos('/', UrlAbsolutaFotoBio) <> 1 then UrlAbsolutaFotoBio := '/' + UrlAbsolutaFotoBio;
  UrlAbsolutaFotoBio := BaseUrl + UrlAbsolutaFotoBio;

  UrlAbsolutaCapa := Perfil.foto_capa;
  if Pos('/', UrlAbsolutaCapa) <> 1 then UrlAbsolutaCapa := '/' + UrlAbsolutaCapa;
  UrlAbsolutaCapa := BaseUrl + UrlAbsolutaCapa;

  // 3. Sanitização de variáveis
  WhatsLimpo := StringReplace(Perfil.WhatsApp, ' ', '', [rfReplaceAll]);
  WhatsLimpo := StringReplace(WhatsLimpo, '-', '', [rfReplaceAll]);
  WhatsLimpo := StringReplace(WhatsLimpo, '(', '', [rfReplaceAll]);
  WhatsLimpo := StringReplace(WhatsLimpo, ')', '', [rfReplaceAll]);

  EnderecoCompleto := Perfil.Logradouro + ', ' + Perfil.Numero;
  if Perfil.Complemento <> '' then
    EnderecoCompleto := EnderecoCompleto + ' - ' + Perfil.Complemento;
  EnderecoCompleto := EnderecoCompleto + ' - ' + Perfil.Bairro + ', ' + Perfil.Cidade + ' - ' + Perfil.UF + ', ' + Perfil.CEP;

  MapsUrl := 'https://maps.google.com/maps?q=' + StringReplace(EnderecoCompleto, ' ', '+', [rfReplaceAll]) + '&t=&z=15&ie=UTF8&iwloc=&output=embed';

  // 4. Carrossel — sem alt "Tatuagem por", genérico pro comércio
  CarrosselHtml := '';
  for i := 0 to High(Perfil.FotosGaleria) do
  begin
    UrlFotoAbsoluta := Perfil.FotosGaleria[i];
    if Pos('/', UrlFotoAbsoluta) <> 1 then UrlFotoAbsoluta := '/' + UrlFotoAbsoluta;
    UrlFotoAbsoluta := BaseUrl + UrlFotoAbsoluta;

    CarrosselHtml := CarrosselHtml +
      '<div class="carousel-item">' +
      '  <a href="' + UrlFotoAbsoluta + '" data-pswp-width="1200" data-pswp-height="1500" target="_blank">' +
      '    <img src="' + UrlFotoAbsoluta + '" alt="Foto de ' + Perfil.Titulo + '" loading="lazy">' +
      '  </a>' +
      '</div>';
  end;

  // 5. Motor de substituição de tags
  HTMLFinal := StringReplace(HTMLFinal, '{{PAGE_TITLE}}', Perfil.slug, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{META_DESCRIPTION}}', Copy(Perfil.Bio, 1, 150) + '...', [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{META_AUTHOR}}', Perfil.Titulo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{CANONICAL_URL}}', UrlCanonica, [rfReplaceAll]);

  HTMLFinal := StringReplace(HTMLFinal, '{{OG_DESCRIPTION}}', Copy(Perfil.Bio, 1, 150) + '...', [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{OG_IMAGE_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);

  // Schema.org JSON-LD — tipo varia por categoria, diferente do Inkers
  // (que era sempre TattooParlor fixo)
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_TYPE}}', SchemaTypePorCategoria(Perfil.CategoriaSlug), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_NOME}}', Perfil.Titulo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_TELEFONE}}', WhatsLimpo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_LOGRADOURO}}', Perfil.Logradouro + ', ' + Perfil.Numero, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_CIDADE}}', Perfil.Cidade, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_UF}}', Perfil.Uf, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_CEP}}', Perfil.CEP, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_LATITUDE}}', Perfil.Latitude, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_LONGITUDE}}', Perfil.Longitude, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_DIAS}}', Perfil.SchemaDias, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_ABRE}}', Perfil.SchemaAbre, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_FECHA}}', Perfil.SchemaFecha, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{SCHEMA_INSTAGRAM_URL}}', Perfil.Insta, [rfReplaceAll]);

  // Trackers
  HTMLFinal := StringReplace(HTMLFinal, '{{META_PIXEL_ID}}', Perfil.meta_pixel, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{GOOGLE_TAG_ID}}', Perfil.google_id, [rfReplaceAll]);

  // Estrutura visual — "COMERCIO_*"
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_ID}}', Perfil.UUid, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_SLUG}}', Perfil.slug, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_NOME}}', Perfil.slug, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_BIO}}', Perfil.Subtitulo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_BIO_LONGA}}', Perfil.Bio, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CIDADE}}', Perfil.Cidade + ' - ' + Perfil.Uf, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CAPA_URL}}', UrlAbsolutaCapa, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CATEGORIA_NOME}}', Perfil.CategoriaNome, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_CATEGORIA_SLUG}}', Perfil.CategoriaSlug, [rfReplaceAll]);

  HTMLFinal := StringReplace(HTMLFinal, '{{ALT_FOTO_PERFIL}}', 'Foto de perfil de ' + Perfil.Titulo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ALT_FOTO_BIO}}', 'Foto de ' + Perfil.Titulo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_FULL_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_URL}}', UrlAbsolutaAvatar, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_FULL_BIO_URL}}', UrlAbsolutaFotoBio, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{COMERCIO_FOTO_BIO_URL}}', UrlAbsolutaFotoBio, [rfReplaceAll]);

  // Contato e localização
  HTMLFinal := StringReplace(HTMLFinal, '{{WHATSAPP_NUMERO}}', WhatsLimpo, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ENDERECO_COMPLETO}}', EnderecoCompleto, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{MAPS_EMBED_URL}}', MapsUrl, [rfReplaceAll]);

  // Componentes dinâmicos
  HTMLFinal := StringReplace(HTMLFinal, '{{CARROSSEL_ITENS}}', CarrosselHtml, [rfReplaceAll]);

  HTMLFinal := StringReplace(HTMLFinal, '{{DEPOIMENTOS_JSON}}', TProtifolioModel.GetDepoimentosAprovadosJson(Perfil.UUid), [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{DEPOIMENTOS_SUBMIT_URL}}', 'https://api.guiatour.online/api/v1/depoimentos', [rfReplaceAll]);

  // Limpeza final de placeholders não substituídos
  while (Pos('{{', HTMLFinal) > 0) and (Pos('}}', HTMLFinal) > Pos('{{', HTMLFinal)) do
  begin
    p := Pos('{{', HTMLFinal);
    i := Pos('}}', HTMLFinal);
    Delete(HTMLFinal, p, i - p + 2);
  end;

  Result := HTMLFinal;
end;

end.

unit uportifoliomodel;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, udata, ugetdata, db, jsonparser, fpjson, DateUtils,
  base64;

type
  TComercioPerfil = record
    Encontrado  : Boolean;
    SiteID      : Integer;
    UUid        : string;  
    Titulo      : string;
    Subtitulo   : string;
    Avatar      : string;
    FotoBio     : string;
    Bio         : string;
    WhatsApp    : string;
    Endereco    : string;
    SchemaDias  : string;
    SchemaAbre  : string;
    SchemaFecha : string;
    Insta       : string;
    Telefone    : string;
    Logradouro  : string;
    Cidade      : string;
    Uf          : string;
    CEP         : string;
    Numero      : string;
    Bairro      : String;
    Complemento : string;
    Latitude    : string;
    Longitude   : string;
    google_id   : string;
    meta_pixel  : string;
    slug        : string;
    foto_capa   : string;
    CategoriaSlug:string;
    CategoriaNome:string;
    FotosGaleria: TArray<string>;
    CPosTattoo  : TArray<string>;
  end;

type

  { TProtifolioModel }

  TProtifolioModel = class

  public
    class function UpdateFotoCapa(const nome_arquivo, id_loja, base64_str: string): integer;
    class function GetBySlug(const Slug: string): TComercioPerfil;
    class procedure SavePortfolio(const IDLoja, Titulo, Subtitulo, Avatar,
      FotoBio, Bio: string);
    class function GetPortfolio(var id_loja: string): TJSONObject;
    class function GetGaleria(var id_portfolio: integer): TJSONObject;
    class function UpdateAvatar(var id_site: integer; const nome_arquivo, id_loja, base64_str: string): integer;
    class function UpdateFotoBio(var id_site: integer; const nome_arquivo, id_loja, base64_str: string): integer;
    class procedure RemoveItem(var id: integer);
    class procedure UploadFoto(var id_site: integer; var nome, base64Str,
      id_loja: string);
    class procedure PortifolioUpdateBasico(id, titulo, subtitulo, bio: string);
    class function GetDepoimentosAprovadosJson(const id_loja: string): string;
    class function GetDepoimentosPendentesJson(const id_loja: string): TJSONArray;
    class procedure AprovarDepoimento(id: integer);
    class function SaveDepoimento(const id_loja, nome,
  texto: string; nota: integer; const foto_base64, extensao_foto: string): integer;
    class function FotoValidaDepoimento(const foto_base64: string;
      out Extensao: string): Boolean;
    class function GetIdLojaPorSlug(const Slug: string): string;
  end;

implementation

function GetImageFilePathFromUrl(const Url: string): string;
begin
  Result := '';
  if Trim(Url) = '' then
    Exit;

  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
            'uploads' + PathDelim + ExtractFileName(Url);
end;

procedure DeleteImageFile(const Url: string);
var
  FilePath: string;
begin
  FilePath := GetImageFilePathFromUrl(Url);
  if (FilePath <> '') and FileExists(FilePath) then
    DeleteFile(FilePath);
end;



{ TProtifolioModel }
class function TProtifolioModel.UpdateFotoCapa(const nome_arquivo, id_loja, base64_str: string): integer;
var
  caminho_salvar, url_banco, foto_capa_antiga: string;
  dataset: TDataSet;
  DecodedStr: string;
  StringStream: TStringStream;
begin
  dataset := nil;
  StringStream := nil;
  try
    dataset := TGetData.getData(
      'SELECT FOTO_CAPA FROM SITE WHERE id_loja_ex = :id_loja;',
      [id_loja],
      True
    );

    if Assigned(dataset) and not dataset.IsEmpty then
      foto_capa_antiga := dataset.FieldByName('FOTO_CAPA').AsString;
    FreeAndNil(dataset);

    // Deletar imagem antiga se existir
    if foto_capa_antiga <> '' then
      DeleteImageFile(foto_capa_antiga);

    // Salvar nova imagem
    caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo);
    url_banco      := ExpandFileName('/imagens/' + id_loja + '_' + nome_arquivo);

    DecodedStr := DecodeStringBase64(base64_str);
    StringStream := TStringStream.Create(DecodedStr);
    StringStream.SaveToFile(caminho_salvar);

    // Atualizar banco
    dataset := nil;
    dataset := TGetData.getData(
      'UPDATE OR INSERT INTO SITE (id_loja_ex, FOTO_CAPA) '+
      'VALUES(:id_loja_ex, :foto_capa) MATCHING (id_loja_ex) RETURNING ID;',
      [
        id_loja,
        url_banco
      ],
      True
    );

    Result := dataset.Fields[0].AsInteger;

  finally
    if Assigned(dataset) then dataset.Free;
    if Assigned(StringStream) then StringStream.Free;
  end;
end;


class function TProtifolioModel.GetBySlug(const Slug: string): TComercioPerfil;
var
  dataset: TDataSet;
  FotosCount, CPosTattooCount: Integer;
  ConfigHorario: string;
  JData, JDay: TJSONObject;
  i: Integer;
  ArrayDias: string;
  NomesDias: array[1..7] of string;
  FS: TFormatSettings;
begin
  Result.Encontrado := False;
  SetLength(Result.FotosGaleria, 0);

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

     try

          dataset := TGetData.getData(
            'SELECT S.ID AS SITE_ID, S.TITULO, S.SUBTITULO, '+
            'S.AVATAR, S.FOTO_BIO, S.BIO, S.FOTO_CAPA, '+

            'L.TELEFONE AS WHATSAPP, L.ENDERECO, L.NUMERO, L.BAIRRO, '+
            'L.COMPLEMENTO, L.HORARIOS, L.CIDADE, L.UF, L.CEP, '+
            'L.VALIDADE, L.META_PIXEL_ID, L.GOOGLE_ANALYTICS_ID, L.INSTA, '+
            'L.SLUG, L.UUID FROM LOJA L '+

            'LEFT JOIN SITE S ON S.ID_LOJA_EX = L.UUID WHERE L.SLUG = :Slug;',
            [Slug],
            True
          );

          if Assigned(dataset) then
          begin
            try
              if not dataset.IsEmpty then
               begin
                 if DateOf(dataset.FieldByName('validade').AsDateTime) < DateOf(Now) then exit;

                 Result.Encontrado := True;
                 Result.SiteID     := dataset.FieldByName('SITE_ID'            ).AsInteger;
                 Result.Titulo     := dataset.FieldByName('TITULO'             ).AsString;
                 Result.Subtitulo  := dataset.FieldByName('SUBTITULO'          ).AsString;
                 Result.Avatar     := dataset.FieldByName('AVATAR'             ).AsString;
                 Result.FotoBio    := dataset.FieldByName('FOTO_BIO'           ).AsString;
                 Result.Bio        := dataset.FieldByName('BIO'                ).AsString;
                 Result.WhatsApp   := dataset.FieldByName('WHATSAPP'           ).AsString;
                 Result.Endereco   := dataset.FieldByName('ENDERECO'           ).AsString;
                 Result.Insta      := dataset.FieldByName('INSTA'              ).AsString;
                 Result.Telefone   := dataset.FieldByName('WHATSAPP'           ).AsString;
                 Result.Logradouro := dataset.FieldByName('ENDERECO'           ).AsString;
                 Result.Cidade     := dataset.FieldByName('CIDADE'             ).AsString;
                 Result.Uf         := dataset.FieldByName('UF'                 ).AsString;
                 Result.CEP        := dataset.FieldByName('CEP'                ).AsString;
                 Result.Numero     := dataset.FieldByName('NUMERO'             ).AsString;
                 Result.Bairro     := dataset.FieldByName('BAIRRO'             ).AsString;
                 Result.Complemento:= dataset.FieldByName('COMPLEMENTO'        ).AsString;
                 Result.google_id  := dataset.FieldByName('GOOGLE_ANALYTICS_ID').AsString;
                 Result.meta_pixel := dataset.FieldByName('META_PIXEL_ID'      ).AsString;
                 Result.slug       := dataset.FieldByName('SLUG'               ).AsString;
                 Result.foto_capa  := dataset.FieldByName('FOTO_CAPA'          ).AsString;
                 Result.UUid       := dataset.FieldByName('UUID'               ).AsString;

                 NomesDias[1] := 'Sunday';
                 NomesDias[2] := 'Monday';
                 NomesDias[3] := 'Tuesday';
                 NomesDias[4] := 'Wednesday';
                 NomesDias[5] := 'Thursday';
                 NomesDias[6] := 'Friday';
                 NomesDias[7] := 'Saturday';

                 Result.SchemaDias  := '"Monday", "Tuesday", "Wednesday", "Thursday", "Friday"';
                 Result.SchemaAbre  := '09:00';
                 Result.SchemaFecha := '18:00';

                 ConfigHorario := dataset.FieldByName('HORARIOS').AsString;

                 if trim(ConfigHorario) <> '' then
                  begin
                    try
                      JData := GetJSON(ConfigHorario) as TJSONObject;
                      try
                        ArrayDias := '';

                        for i := 1 to 7 do
                        begin
                          if JData.IndexOfName(IntToStr(i)) <> -1 then
                           begin
                             JDay := JData.Objects[IntToStr(i)];
                             if JDay.Booleans['aberto'] then
                              begin
                                if ArrayDias <> '' then ArrayDias := ArrayDias + ', ';
                                ArrayDias := ArrayDias + '"' + NomesDias[i] + '"';

                                Result.SchemaAbre := JDay.Strings['inicio'];
                                Result.SchemaFecha := JDay.Strings['fim'];
                              end;
                           end;
                        end;

                        if ArrayDias <> '' then Result.SchemaDias := ArrayDias;

                      finally
                        JData.Free;
                      end;
                    except
                    end;
                  end;
               end;
            finally
              dataset.Free;
            end;
          end;

         if Result.Encontrado and (Result.SiteID > 0) then
          begin
            dataset := TGetData.getData(
             'SELECT URL_FOTO FROM SITE_GALERIA WHERE ID_SITE = :SiteId '+
             'order by id desc;',
             [Result.SiteID],
             True
            );
            FotosCount := 0;

            if Assigned(dataset) then
             begin
              try
                dataset.First;
                while not dataset.eof do
                  begin
                    Inc(FotosCount);
                    SetLength(Result.FotosGaleria, FotosCount);
                    Result.FotosGaleria[FotosCount -1] := dataset.FieldByName('URL_FOTO').AsString;
                    dataset.Next;
                  end;
              finally
                 freeandnil(dataset);
              end;

            end;

          end;

     except on e:exception do
       raise Exception.Create('Erro ao buscar artista: ' + E.Message);
     end;
end;

class procedure TProtifolioModel.SavePortfolio(const IDLoja, Titulo, Subtitulo,
  Avatar, FotoBio, Bio: string);
begin
  try
      TGetData.getData(
        'UPDATE OR INSERT INTO SITE ' +
        '(ID_LOJA_EX, TITULO, SUBTITULO, AVATAR, FOTO_BIO, BIO) ' +
        'VALUES (:id_loja, :titulo, :subtitulo, :avatar, :foto_bio, :bio) ' +
        'MATCHING (ID_LOJA_EX);',
        [IDLoja, Titulo, Subtitulo, Avatar, FotoBio, Bio]
      );
    except
      on E: Exception do
        raise Exception.Create('Falha de banco de dados ao salvar portfólio: ' + E.Message);
    end;
end;

class function TProtifolioModel.GetPortfolio(var id_loja: string): TJSONObject;
var
  dataset: TDataSet;
  jsonitem, jsonItemCuidados: TJSONObject;
  jarray, arrayCuidados: TJSONArray;
  id_site: integer;
begin
  Result := nil;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT ID, TITULO, SUBTITULO, '+
      'AVATAR, FOTO_BIO, BIO, FOTO_CAPA '+
      'FROM SITE WHERE ID_LOJA_EX = :id_loja;',
      [id_loja],
      True
    );

    if not Assigned(dataset) or (dataset.IsEmpty) then exit;

    id_site := dataset.FieldByName('id').AsInteger;

    Result := TJSONObject.Create;

    Result.Add('titulo',    dataset.FieldByName('titulo'   ).AsString);
    Result.Add('subtitulo', dataset.FieldByName('subtitulo').AsString);
    Result.Add('avatar',    dataset.FieldByName('avatar'   ).AsString);
    Result.Add('foto_bio',  dataset.FieldByName('foto_bio' ).AsString);
    Result.Add('bio',       dataset.FieldByName('bio'      ).AsString);
    Result.Add('foto_capa', dataset.FieldByName('foto_capa').AsString);
    Result.add('id_site',   dataset.FieldByName('id'       ).AsInteger);

  finally
    if Assigned(dataset) then FreeAndNil(dataset);
  end;

  try
    dataset := TGetData.getData(
      'SELECT ID, URL_FOTO FROM SITE_GALERIA WHERE ID_SITE = :ID_SITE',
      [id_site],
      True
    );

    if assigned(dataset) and (not dataset.IsEmpty) then;
    begin
      jarray := TJSONArray.Create;
      dataset.First;

      while not dataset.eof do
      begin
         jsonitem := TJSONObject.Create;

         jsonitem.Add('id_foto',  dataset.FieldByName('id'      ).AsInteger);
         jsonitem.add('url_foto', dataset.FieldByName('url_foto').AsString );

         jarray.Add(jsonitem);
         dataset.Next;
      end;
         Result.Add('itens', jarray);
         if Assigned(dataset) then FreeAndNil(dataset);
    end;
  finally
    if Assigned(dataset) then dataset.Free;
  end;
end;

class function TProtifolioModel.UpdateAvatar(var id_site: integer; const nome_arquivo, id_loja, base64_str: string): integer;
var
  caminho_salvar, url_banco, avatar_antigo: string;
  dataset: TDataSet;
  DecodedStr: string;
  StringStream: TStringStream;
begin
  try
    // Buscar avatar antigo para deletar
    dataset := TGetData.getData('SELECT AVATAR FROM SITE WHERE id_loja_ex = :id_loja', [id_loja], True);
    if Assigned(dataset) and not dataset.IsEmpty then
      avatar_antigo := dataset.FieldByName('AVATAR').AsString;
    dataset.Free;

    // Salvar nova imagem
    caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo);
    url_banco      := ExpandFileName('/imagens/' + id_loja + '_' + nome_arquivo);

    DecodedStr := DecodeStringBase64(base64_str);
    StringStream := TStringStream.Create(DecodedStr);
    StringStream.SaveToFile(caminho_salvar);

    // Atualizar banco
    dataset := nil;
    dataset := TGetData.getData(
      'UPDATE or INSERT INTO SITE (id_loja_ex, AVATAR) VALUES(:id_loja, :AVATAR) MATCHING(id_loja_ex) RETURNING ID;',
      [id_loja, url_banco],
      True
    );

    Result := dataset.Fields[0].AsInteger;

    if avatar_antigo <> '' then
      DeleteImageFile(avatar_antigo);
  finally
    StringStream.Free;
    dataset.Free;
  end;
end;

class function TProtifolioModel.UpdateFotoBio(var id_site: integer; const nome_arquivo, id_loja, base64_str: string): integer;
var
  caminho_salvar, url_banco, foto_bio_antiga: string;
  dataset: TDataSet;
  DecodedStr: string;
  StringStream: TStringStream;
begin
  try
    // Buscar foto bio antiga para deletar
    dataset := TGetData.getData('SELECT FOTO_BIO FROM SITE WHERE id_loja_ex = :id_loja', [id_loja], True);
    if Assigned(dataset) and not dataset.IsEmpty then
      foto_bio_antiga := dataset.FieldByName('FOTO_BIO').AsString;
    dataset.Free;

    // Salvar nova imagem
    caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo);
    url_banco      := ExpandFileName('/imagens/' + id_loja + '_' + nome_arquivo);

    DecodedStr := DecodeStringBase64(base64_str);
    StringStream := TStringStream.Create(DecodedStr);
    StringStream.SaveToFile(caminho_salvar);

    // Atualizar banco
    dataset := nil;
    dataset := TGetData.getData(
      'UPDATE OR INSERT INTO SITE (id_loja_ex, FOTO_BIO) VALUES(:id_loja_ex, :foto_bio) MATCHING (id_loja_ex) RETURNING ID;',
      [id_loja, url_banco],
      True
    );

    // Deletar imagem antiga se existir
    if foto_bio_antiga <> '' then
      DeleteImageFile(foto_bio_antiga);

    Result := dataset.Fields[0].AsInteger;
  finally
    dataset.Free;
    StringStream.Free;
  end;
end;

class procedure TProtifolioModel.RemoveItem(var id: integer);
var
  dataset: TDataSet;
  url_foto: string;
begin

  url_foto := '';
  dataset := TGetData.getData(
    'select url_foto from site_galeria where id = :id',
    [id],
    True
  );
  if Assigned(dataset) then
  begin
    try
      if not dataset.IsEmpty then
        url_foto := dataset.FieldByName('url_foto').AsString;
    finally
      dataset.Free;
    end;
  end;

  if url_foto <> '' then
    DeleteImageFile(url_foto);

  TGetData.getData(
    'delete from site_galeria where id = :id',
    [id]
  );
end;

class procedure TProtifolioModel.UploadFoto(var id_site: integer; var nome,
  base64Str, id_loja: string);
var
  caminho_salvar, url_banco, url_relativa, DecodedStr: string;
  StringStream: TStringStream;
begin
  try
    caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome);
    url_banco      := ExpandFileName('/imagens/'  + id_loja + '_' + nome);
    url_relativa   := 'uploads/' + id_loja + '_' + nome;

    DecodedStr := DecodeStringBase64(base64Str);
    StringStream := TStringStream.Create(DecodedStr);

    StringStream.SaveToFile(caminho_salvar);

    TGetData.getData(
      'insert into site_galeria (id_site, url_foto) values(:id_site, :url_foto)',
      [id_site, url_banco]
    );
  finally
    StringStream.Free;
  end;
end;

class procedure TProtifolioModel.PortifolioUpdateBasico(id, titulo, subtitulo,
  bio: string);
begin
  try
    TGetData.getData(
      'update site set titulo = :titulo, subtitulo = :subtitulo, bio = :bio ' +
      'where id_loja_ex = :id_loja;',
      [titulo, subtitulo, bio, id]
    );
  except
    raise;
  end;
end;

class function TProtifolioModel.GetGaleria(var id_portfolio: integer): TJSONObject;
var
  dataset: TDataSet;
  jsonitem: TJSONObject;
  jarray: TJSONArray;
begin
  Result := TJSONObject.Create;

  try
    dataset := TGetData.getData(
      'SELECT ID, URL_FOTO FROM SITE_GALERIA WHERE ID_SITE = :ID_SITE',
      [id_portfolio],
      True
    );

    if not Assigned(dataset) then exit;

    if dataset.IsEmpty then exit;

    jarray := TJSONArray.Create;

    dataset.First;

    while not dataset.eof do
     begin
       jsonitem := TJSONObject.Create;

       jsonitem.Add('id_foto',  dataset.FieldByName('id'      ).AsInteger);
       jsonitem.add('url_foto', dataset.FieldByName('url_foto').AsString );

       jarray.Add(jsonitem);
       dataset.Next;
     end;

     Result.Add('itens', jarray);

  finally
    if Assigned(dataset) then dataset.Free;
  end;

end;

class function TProtifolioModel.GetIdLojaPorSlug(const Slug: string): string;
var
  dataset: TDataSet;
begin
  Result := '';
  dataset := TGetData.getData(
    'SELECT UUID FROM LOJA WHERE SLUG = :slug;',
    [Slug],
    True
  );
  try
    if Assigned(dataset) and not dataset.IsEmpty then
      Result := dataset.Fields[0].AsString;
  finally
    if Assigned(dataset) then FreeAndNil(dataset);
  end;
end;
 
class function TProtifolioModel.FotoValidaDepoimento(const foto_base64: string;
  out Extensao: string): Boolean;
var
  DecodedStr: string;
const
  TAMANHO_MAXIMO = 3 * 1024 * 1024; // 3 MB decodificado
begin
  Result := False;
  Extensao := '';
 
  DecodedStr := DecodeStringBase64(foto_base64);
 
  if Length(DecodedStr) > TAMANHO_MAXIMO then
    Exit; // recusa antes mesmo de olhar o conteúdo
 
  // JPEG: FF D8 FF
  if (Length(DecodedStr) >= 3) and
     (Ord(DecodedStr[1]) = $FF) and (Ord(DecodedStr[2]) = $D8) and
     (Ord(DecodedStr[3]) = $FF) then
  begin
    Extensao := '.jpg';
    Result := True;
    Exit;
  end;
 
  // PNG: 89 50 4E 47
  if (Length(DecodedStr) >= 4) and
     (Ord(DecodedStr[1]) = $89) and (Ord(DecodedStr[2]) = $50) and
     (Ord(DecodedStr[3]) = $4E) and (Ord(DecodedStr[4]) = $47) then
  begin
    Extensao := '.png';
    Result := True;
  end;
 
  // Qualquer outro formato (HEIC, GIF, WEBP, SVG etc.) é recusado — o
  // cliente já converte pra JPEG antes de enviar, isso só protege contra
  // alguém chamando a API direto, sem passar pelo formulário público.
end;
 
class function TProtifolioModel.SaveDepoimento(const id_loja, nome,
  texto: string; nota: integer; const foto_base64, extensao_foto: string): integer;
var
  dataset: TDataSet;
  caminho_salvar, url_banco, nome_arquivo, DecodedStr: string;
  StringStream: TStringStream;
begin
  Result := 0;
  dataset := nil;
  StringStream := nil;
  url_banco := '';
  try
    if foto_base64 <> '' then
    begin
      nome_arquivo   := 'dep_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + extensao_foto;
      caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo);
      url_banco      := ExpandFileName('/imagens/'  + id_loja + '_' + nome_arquivo);
 
      DecodedStr := DecodeStringBase64(foto_base64);
      StringStream := TStringStream.Create(DecodedStr);
      StringStream.SaveToFile(caminho_salvar);
    end;

    dataset := TGetData.getData(
      'INSERT INTO DEPOIMENTOS (ID_LOJA, NOME, NOTA, TEXTO, FOTO_URL, STATUS) ' +
      'VALUES (:id_loja, :nome, :nota, :texto, :foto_url, ''pendente'') RETURNING ID;',
      [id_loja, nome, nota, texto, url_banco],
      True
    );
 
    if Assigned(dataset) and not dataset.IsEmpty then
      Result := dataset.Fields[0].AsInteger;
  finally
    if Assigned(StringStream) then StringStream.Free;
    if Assigned(dataset) then dataset.Free;
  end;
end;
 
class function TProtifolioModel.GetDepoimentosAprovadosJson(const id_loja: string): string;
var
  dataset: TDataSet;
  jarray: TJSONArray;
  jsonitem: TJSONObject;
begin
  jarray := TJSONArray.Create;
  try
    dataset := TGetData.getData(
      'SELECT NOME, NOTA, TEXTO, FOTO_URL FROM DEPOIMENTOS ' +
      'WHERE ID_LOJA = :id_loja AND STATUS = ''aprovado'' ' +
      'ORDER BY CRIADO_EM DESC;',
      [id_loja],
      True
    );
 
    if Assigned(dataset) then
    begin
      try
        dataset.First;
        while not dataset.EOF do
        begin
          jsonitem := TJSONObject.Create;
          jsonitem.Add('nome',     dataset.FieldByName('nome'    ).AsString);
          jsonitem.Add('nota',     dataset.FieldByName('nota'    ).AsInteger);
          jsonitem.Add('texto',    dataset.FieldByName('texto'   ).AsString);
          jsonitem.Add('foto_url', dataset.FieldByName('foto_url').AsString);
          jarray.Add(jsonitem);
          dataset.Next;
        end;
      finally
        dataset.Free;
      end;
    end;
    Result := jarray.AsJSON;
  finally
    jarray.Free;
  end;
end;

class function TProtifolioModel.GetDepoimentosPendentesJson(const id_loja: string): TJSONArray;
var
  dataset: TDataSet;
  jarray: TJSONArray;
  jsonitem: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    dataset := TGetData.getData(
      'SELECT ID, NOME, NOTA, TEXTO, FOTO_URL, CRIADO_EM FROM DEPOIMENTOS ' +
      'WHERE ID_LOJA = :id_loja AND STATUS = ''pendente'' ' +
      'ORDER BY CRIADO_EM DESC;',
      [id_loja],
      True
    );

    if Assigned(dataset) then
    begin
      dataset.First;
      while not dataset.EOF do
      begin
        jsonitem := TJSONObject.Create;
        jsonitem.Add('id',       dataset.FieldByName('id'      ).AsInteger);
        jsonitem.Add('nome',     dataset.FieldByName('nome'    ).AsString);
        jsonitem.Add('nota',     dataset.FieldByName('nota'    ).AsInteger);
        jsonitem.Add('texto',    dataset.FieldByName('texto'   ).AsString);
        jsonitem.Add('foto_url', dataset.FieldByName('foto_url').AsString);
        jsonitem.Add('data',     DateTimeToStr(dataset.FieldByName('criado_em').AsDateTime));
        Result.Add(jsonitem);
        dataset.Next;
      end;
    end;
  finally
    dataset.Free;
  end;
end;

class procedure TProtifolioModel.AprovarDepoimento(id: integer);
begin
  try
    TGetData.getData(
      'UPDATE DEPOIMENTOS SET STATUS = ''aprovado'' WHERE ID = :id',
      [id]
    );
  except
      raise;
  end;
end;

end.


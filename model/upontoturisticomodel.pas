unit upontoturisticomodel;

interface

uses
  Classes, SysUtils, fpjson, ugetdata, db, base64, Math, LazUTF8, StrUtils;

const
  RAIO_BASE_KM            = 5.0;  // raio padrão de visibilidade do comércio
  RAIO_EXTRA_POR_NIVEL_KM = 5.0;  // cada nível de PLANO_DESTAQUE soma esse tanto ao raio
  LIMITE_COMERCIOS_PROXIMOS = 12;
  MAX_IMAGEM_BYTES = 5 * 1024 * 1024;

type
  EImagemInvalida = class(Exception);

  TPontoTuristicoData = record
    idVendedor,
    nome,
    slug,
    resumo,
    historia,
    latitude,
    longitude,
    cep,
    endereco,
    numero,
    bairro,
    cidade,
    estado,
    nome_arquivo_capa,
    capa,
    galeria: string;
    id_categoria: integer;
  end;

type

  { TPontoTuristicoModel }

  TPontoTuristicoModel = class
  public
    class function DonoDoPonto(idVendedor, uuidPonto: string): Boolean;
    class function ListarPontos(idVendedor: string): TJSONArray;
    class function CriarPonto(dados: TPontoTuristicoData): string;
    class function GetPontoPorUuid(uuidPonto: string): TJSONObject;
    class function AtualizarPonto(uuidPonto: string; dados: TPontoTuristicoData): Boolean;
    class function DefinirAtivo(uuid: string; ativo: Boolean): Boolean;
    class function RemoverFotoGaleria(uuidPonto: string; idFoto: integer): Boolean;
    class function GetBySlug(slug: string): TJSONObject;
    class function GetComerciosProximos(slug: string): TJSONArray;
    class function GetPontosProximos(slug: string; limite: integer = 6): TJSONArray;
    class function GetPontosPorGPS(lat, lng: Double; raioKm: Double = 30; limite: integer = 10): TJSONArray;
    class function ListarCategorias: TJSONArray;
    class function TryParseCoord(const S: string; Min, Max: Double; out V: Double): Boolean;
    class function Slugify(const AValue: string): string;
    class function GerarSlugUnico(const Base: string; const UuidIgnorar: string = ''): string;
    class function GerarNomeArquivoSeguro(const NomeOriginal, UuidPonto: string; out NomeFinal: string): Boolean;
  private
    class function MontarGaleriaJson(idPonto: integer): TJSONArray;
    class procedure SalvarItensGaleria(const uuidString, galeriaJson: string; idPonto: integer);
  end;

implementation

{ ---------- helpers ---------- }

class function TPontoTuristicoModel.MontarGaleriaJson(idPonto: integer): TJSONArray;
var
  dataset: TDataSet;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT id, url_foto FROM ponto_turistico_galeria ' +
      'WHERE id_ponto = :idPonto ORDER BY ordem;',
      [idPonto],
      True
    );
    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
      item.Add('id',  dataset.FieldByName('id').AsInteger);
      item.Add('url', dataset.FieldByName('url_foto').AsString);
      Result.Add(item);
      dataset.Next;
    end;
  finally
    dataset.Free;
  end;
end;

// Decodifica e salva cada item de galeria em disco + insere a linha,
// mantendo a ordem recebida (soma à ordem que já existir, pra suportar
// "adicionar mais fotos" em cima de um ponto já existente).
class procedure TPontoTuristicoModel.SalvarItensGaleria(const uuidString, galeriaJson: string; idPonto: integer);
var
  arrayGaleria: TJSONArray;
  itemGaleria: TJSONObject;
  jsonData: TJSONData;
  dataset: TDataSet;
  i, ordemBase: integer;
  caminho_salvar, url_banco, DecodedStr, nome_arquivo, itemFoto, nome_seguro: string;
  StringStream: TStringStream;
begin
  if Trim(galeriaJson) = '' then Exit;

  jsonData := GetJSON(galeriaJson);
  try
    if jsonData.JSONType <> jtArray then Exit;

    arrayGaleria := TJSONArray(jsonData);
    if arrayGaleria.Count = 0 then Exit;

    dataset := nil;
    ordemBase := 0;
    try
      dataset := TGetData.getData(
        'SELECT COALESCE(MAX(ordem), -1) AS max_ordem FROM ponto_turistico_galeria ' +
        'WHERE id_ponto = :idPonto;',
        [idPonto],
        True
      );
      if Assigned(dataset) and not dataset.IsEmpty then
        ordemBase := dataset.FieldByName('max_ordem').AsInteger + 1;
    finally
      dataset.Free;
    end;

    ForceDirectories(ExpandFileName('./uploads'));
    StringStream := nil;
    try
      for i := 0 to arrayGaleria.Count - 1 do
      begin
        itemGaleria := arrayGaleria.Objects[i];
        nome_arquivo := itemGaleria.Get('nome_arquivo', '');
        itemFoto     := itemGaleria.Get('itemFoto', '');

        if (nome_arquivo = '') or (itemFoto = '') then Continue;

        if not GerarNomeArquivoSeguro(nome_arquivo, uuidString, nome_seguro) then
          raise EImagemInvalida.Create('Extensão de imagem não permitida.');

        DecodedStr := DecodeStringBase64(itemFoto);
        if Length(DecodedStr) > MAX_IMAGEM_BYTES then
          raise EImagemInvalida.Create('Imagem muito grande.');

        caminho_salvar := ExpandFileName('./uploads/' + nome_seguro);
        url_banco      := '/imagens/' + nome_seguro;

        StringStream := TStringStream.Create(DecodedStr);
        StringStream.SaveToFile(caminho_salvar);
        FreeAndNil(StringStream);

        TGetData.getData(
          'insert into ponto_turistico_galeria(id_ponto, url_foto, ordem) ' +
          'values(:id_ponto, :url_foto, :ordem);',
          [idPonto, url_banco, ordemBase + i]
        );
      end;
    finally
      if Assigned(StringStream) then StringStream.Free;
    end;
  finally
    jsonData.Free;
  end;
end;

{ ---------- vendedor ---------- }

class function TPontoTuristicoModel.DonoDoPonto(idVendedor, uuidPonto: string): Boolean;
var
  dataset: TDataSet;
begin
  dataset := nil;
  try
    try
      Result := False;
      if (idVendedor = '') or (uuidPonto = '') then Exit;

      dataset := TGetData.getData(
        'SELECT 1 FROM ponto_turistico p JOIN vendedor v ON v.id = p.id_vendedor ' +
        'WHERE p.uuid = :uuidPonto AND v.uuid = :idVendedor',
        [uuidPonto, idVendedor],
        True
      );
      Result := not dataset.IsEmpty;
    except
      raise;
    end;
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.ListarPontos(idVendedor: string): TJSONArray;
var
  dataset: TDataSet;
  item: TJSONObject;
begin
  dataset := nil;
  try
    try
      Result := TJSONArray.Create;

      dataset := TGetData.getData(
        'SELECT p.uuid, p.nome, p.slug, p.ativo, c.nome AS categoria ' +
        'FROM ponto_turistico p ' +
        'JOIN vendedor v ON v.id = p.id_vendedor ' +
        'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
        'WHERE v.uuid = :idVendedor ORDER BY p.nome',
        [idVendedor],
        True
      );
      while not dataset.EOF do
      begin
        item := TJSONObject.Create;
        item.Add('uuid', dataset.FieldByName('uuid').AsString);
        item.Add('nome', dataset.FieldByName('nome').AsString);
        item.Add('slug', dataset.FieldByName('slug').AsString);
        item.Add('categoria', dataset.FieldByName('categoria').AsString);
        item.Add('ativo', dataset.FieldByName('ativo').AsBoolean);
        Result.Add(item);
        dataset.Next;
      end;
    except
      raise;
    end;
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.CriarPonto(dados: TPontoTuristicoData): string;
var
  dataSet: TDataSet;
  uuid: TGuid;
  uuidString, url_banco_capa, DecodedStrCapa, caminho_salvar_capa, nome_seguro: string;
  idPonto: integer;
  StringStream: TStringStream;
begin
  dataSet := nil;
  StringStream := nil;
  url_banco_capa := '';
  try
    try
      CreateGUID(uuid);
      uuidString := StringReplace(StringReplace(GUIDToString(uuid),
                      '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);

      // a capa usa o uuid recém-gerado no nome do arquivo — não depende
      // do id numérico, então dá pra salvar o arquivo antes do insert
      // (mesmo esquema usado pro avatar/capa do comércio).
      if (dados.nome_arquivo_capa <> '') and (dados.capa <> '') then
      begin
        if not GerarNomeArquivoSeguro(dados.nome_arquivo_capa, uuidString, nome_seguro) then
          raise EImagemInvalida.Create('Extensão de imagem da capa não permitida.');

        DecodedStrCapa := DecodeStringBase64(dados.capa);
        if Length(DecodedStrCapa) > MAX_IMAGEM_BYTES then
          raise EImagemInvalida.Create('Imagem da capa muito grande.');

        caminho_salvar_capa := ExpandFileName('./uploads/' + nome_seguro);
        url_banco_capa      := '/imagens/' + nome_seguro;

        ForceDirectories(ExpandFileName('./uploads'));
        StringStream := TStringStream.Create(DecodedStrCapa);
        StringStream.SaveToFile(caminho_salvar_capa);
        FreeAndNil(StringStream);
      end;

      dados.slug := GerarSlugUnico(IfThen(dados.slug <> '', dados.slug, dados.nome));

      dataSet := TGetData.getData(
        'insert into ponto_turistico(uuid, id_vendedor, id_categoria, nome, slug, ' +
        'resumo, historia, latitude, longitude, endereco, numero, bairro, cidade, ' +
        'uf, cep, capa) ' +
        'values(:uuid, (select id from vendedor where uuid = :idVendedor), :idCategoria, ' +
        ':nome, :slug, :resumo, :historia, :latitude, :longitude, :endereco, :numero, ' +
        ':bairro, :cidade, :uf, :cep, :capa) ' +
        'returning id;',
        [
          uuidString,
          dados.idVendedor,
          dados.id_categoria,
          dados.nome,
          dados.slug,
          dados.resumo,
          dados.historia,
          StrToFloat(StringReplace(dados.latitude,  ',', '.', [])),
          StrToFloat(StringReplace(dados.longitude, ',', '.', [])),
          dados.endereco,
          dados.numero,
          dados.bairro,
          dados.cidade,
          dados.estado,
          dados.cep,
          url_banco_capa
        ],
        True
      );

      idPonto := dataSet.Fields[0].AsInteger;

      SalvarItensGaleria(uuidString, dados.galeria, idPonto);

      Result := uuidString;
    except
      raise;
    end;
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.GetPontoPorUuid(uuidPonto: string): TJSONObject;
var
  dataset: TDataSet;
  idPonto: integer;
begin
  Result := nil;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT p.id, p.uuid, p.nome, p.slug, p.resumo, p.historia, p.latitude, ' +
      'p.longitude, p.endereco, p.numero, p.bairro, p.cidade, p.uf, p.cep, ' +
      'p.capa, p.ativo, p.id_categoria, c.nome AS categoria_nome, c.slug AS categoria_slug ' +
      'FROM ponto_turistico p ' +
      'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      'WHERE p.uuid = :uuidPonto;',
      [uuidPonto],
      True
    );

    if (not Assigned(dataset)) or dataset.IsEmpty then Exit;

    idPonto := dataset.FieldByName('id').AsInteger;

    Result := TJSONObject.Create;
    Result.Add('uuid',            dataset.FieldByName('uuid'           ).AsString);
    Result.Add('nome',            dataset.FieldByName('nome'           ).AsString);
    Result.Add('slug',            dataset.FieldByName('slug'           ).AsString);
    Result.Add('resumo',          dataset.FieldByName('resumo'         ).AsString);
    Result.Add('historia',        dataset.FieldByName('historia'       ).AsString);
    Result.Add('latitude',        dataset.FieldByName('latitude'       ).AsFloat);
    Result.Add('longitude',       dataset.FieldByName('longitude'      ).AsFloat);
    Result.Add('endereco',        dataset.FieldByName('endereco'       ).AsString);
    Result.Add('numero',          dataset.FieldByName('numero'         ).AsString);
    Result.Add('bairro',          dataset.FieldByName('bairro'         ).AsString);
    Result.Add('cidade',          dataset.FieldByName('cidade'         ).AsString);
    Result.Add('uf',              dataset.FieldByName('uf'             ).AsString);
    Result.Add('cep',             dataset.FieldByName('cep'            ).AsString);
    Result.Add('capa',            dataset.FieldByName('capa'           ).AsString);
    Result.Add('ativo',           dataset.FieldByName('ativo'          ).AsBoolean);
    Result.Add('id_categoria',    dataset.FieldByName('id_categoria'   ).AsInteger);
    Result.Add('categoria_nome',  dataset.FieldByName('categoria_nome' ).AsString);
    Result.Add('categoria_slug',  dataset.FieldByName('categoria_slug' ).AsString);
    Result.Add('galeria',         MontarGaleriaJson(idPonto));
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.AtualizarPonto(uuidPonto: string; dados: TPontoTuristicoData): Boolean;
var
  dataSet: TDataSet;
  idPonto: integer;
  uuidString, url_banco_capa, DecodedStrCapa, caminho_salvar_capa, nome_seguro: string;
  StringStream: TStringStream;
begin
  Result := False;
  dataset := nil;
  StringStream := nil;
  try
    dataset := TGetData.getData(
      'SELECT id, uuid FROM ponto_turistico WHERE uuid = :uuidPonto;',
      [uuidPonto],
      True
    );
    if (not Assigned(dataset)) or dataset.IsEmpty then Exit;

    idPonto    := dataset.FieldByName('id'  ).AsInteger;
    uuidString := dataset.FieldByName('uuid').AsString;

    TGetData.getData(
      'update ponto_turistico set nome = :nome, resumo = :resumo, ' +
      'historia = :historia, latitude = :latitude, longitude = :longitude, ' +
      'endereco = :endereco, numero = :numero, bairro = :bairro, cidade = :cidade, ' +
      'uf = :uf, cep = :cep, id_categoria = :id_categoria ' +
      'where id = :id;',
      [
        dados.nome,
        dados.resumo,
        dados.historia,
        StrToFloat(StringReplace(dados.latitude,  ',', '.', [])),
        StrToFloat(StringReplace(dados.longitude, ',', '.', [])),
        dados.endereco,
        dados.numero,
        dados.bairro,
        dados.cidade,
        dados.estado,
        dados.cep,
        dados.id_categoria,
        idPonto
      ]
    );

    // capa nova é opcional — só troca se vier arquivo no request
    if (dados.nome_arquivo_capa <> '') and (dados.capa <> '') then
    begin
      if not GerarNomeArquivoSeguro(dados.nome_arquivo_capa, uuidString, nome_seguro) then
        raise EImagemInvalida.Create('Extensão de imagem da capa não permitida.');

      DecodedStrCapa := DecodeStringBase64(dados.capa);
      if Length(DecodedStrCapa) > MAX_IMAGEM_BYTES then
        raise EImagemInvalida.Create('Imagem da capa muito grande.');

      caminho_salvar_capa := ExpandFileName('./uploads/' + nome_seguro);
      url_banco_capa      := '/imagens/' + nome_seguro;

      ForceDirectories(ExpandFileName('./uploads'));
      StringStream := TStringStream.Create(DecodedStrCapa);
      StringStream.SaveToFile(caminho_salvar_capa);
      FreeAndNil(StringStream);

      TGetData.getData(
        'update ponto_turistico set capa = :capa where id = :id;',
        [url_banco_capa, idPonto]
      );
    end;

    // fotos novas de galeria são adicionadas às existentes (não substitui)
    SalvarItensGaleria(uuidString, dados.galeria, idPonto);

    Result := True;
  finally
    if Assigned(StringStream) then StringStream.Free;
    dataset.Free;
  end;
end;

{ ---------- público ---------- }

class function TPontoTuristicoModel.DefinirAtivo(uuid: string; ativo: Boolean): Boolean;
begin
  Result := False;
  try
    TGetData.getData(
      'UPDATE ponto_turistico SET ativo = :ativo WHERE uuid = :uuid',
      [ativo, uuid]
    );
    Result := True;
  except
    raise;
  end;
end;

class function TPontoTuristicoModel.RemoverFotoGaleria(uuidPonto: string; idFoto: integer): Boolean;
var
  dataset: TDataSet;
  url_foto, caminho_arquivo: string;
begin
  Result := False;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT url_foto FROM ponto_turistico_galeria ' +
      'WHERE id = :idFoto AND id_ponto = (SELECT id FROM ponto_turistico WHERE uuid = :uuid);',
      [idFoto, uuidPonto],
      True
    );

    if (not Assigned(dataset)) or dataset.IsEmpty then Exit;

    url_foto := dataset.FieldByName('url_foto').AsString;

    // Apaga do banco
    TGetData.getData(
      'DELETE FROM ponto_turistico_galeria WHERE id = :idFoto;',
      [idFoto]
    );

    // Apaga do disco (se for uma imagem local)
    if Pos('/imagens/', url_foto) = 1 then
    begin
      caminho_arquivo := ExpandFileName('./uploads/' + StringReplace(url_foto, '/imagens/', '', []));
      if FileExists(caminho_arquivo) then
        DeleteFile(caminho_arquivo);
    end;

    Result := True;
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.GetBySlug(slug: string): TJSONObject;
var
  dataset: TDataSet;
  idPonto: integer;
begin
  Result := nil;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT p.id, p.uuid, p.nome, p.slug, p.resumo, p.historia, p.latitude, ' +
      'p.longitude, p.endereco, p.numero, p.bairro, p.cidade, p.uf, p.cep, ' +
      'p.capa, c.nome AS categoria_nome, c.slug AS categoria_slug ' +
      'FROM ponto_turistico p ' +
      'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      'WHERE p.slug = :slug AND p.ativo = TRUE;',
      [slug],
      True
    );

    if (not Assigned(dataset)) or dataset.IsEmpty then Exit;

    idPonto := dataset.FieldByName('id').AsInteger;

    Result := TJSONObject.Create;
    Result.Add('uuid',           dataset.FieldByName('uuid'          ).AsString);
    Result.Add('nome',           dataset.FieldByName('nome'          ).AsString);
    Result.Add('slug',           dataset.FieldByName('slug'          ).AsString);
    Result.Add('resumo',         dataset.FieldByName('resumo'        ).AsString);
    Result.Add('historia',       dataset.FieldByName('historia'      ).AsString);
    Result.Add('latitude',       dataset.FieldByName('latitude'      ).AsFloat);
    Result.Add('longitude',      dataset.FieldByName('longitude'     ).AsFloat);
    Result.Add('endereco',       dataset.FieldByName('endereco'      ).AsString);
    Result.Add('bairro',         dataset.FieldByName('bairro'        ).AsString);
    Result.Add('cidade',         dataset.FieldByName('cidade'        ).AsString);
    Result.Add('uf',             dataset.FieldByName('uf'            ).AsString);
    Result.Add('capa',           dataset.FieldByName('capa'          ).AsString);
    Result.Add('categoria_nome', dataset.FieldByName('categoria_nome').AsString);
    Result.Add('categoria_slug', dataset.FieldByName('categoria_slug').AsString);
    Result.Add('galeria',        MontarGaleriaJson(idPonto));
  finally
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.GetComerciosProximos(slug: string): TJSONArray;
var
  dsPonto, dataset: TDataSet;
  lat, lng: Double;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;

  dsPonto := nil;
  dataset := nil;
  try
    dsPonto := TGetData.getData(
      'SELECT latitude, longitude FROM ponto_turistico ' +
      'WHERE slug = :slug AND ativo = TRUE;',
      [slug],
      True
    );

    if (not Assigned(dsPonto)) or dsPonto.IsEmpty then Exit;

    lat := dsPonto.FieldByName('latitude' ).AsFloat;
    lng := dsPonto.FieldByName('longitude').AsFloat;

    // WITH calcula a distância uma vez; o raio efetivo de cada comércio
    // cresce com o PLANO_DESTAQUE dele (0 = plano free = só o raio base).
    // Atenção: os placeholders abaixo são posicionais na ORDEM em que
    // aparecem no texto (o getData faz bind por índice, não por nome),
    // então :lat/:lng repetidos exigem o valor repetido no array também.
    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT l.uuid, l.nome, l.slug, ' +
      '         COALESCE(l.plano_destaque, 0) AS plano_destaque, ' +
      '         c.nome AS categoria_nome, s.avatar, ' +
      '         (COS(RADIANS(:lat)) * COS(RADIANS(l.latitude)) * ' +
      '          COS(RADIANS(l.longitude) - RADIANS(:lng)) + ' +
      '          SIN(RADIANS(:lat)) * SIN(RADIANS(l.latitude))) AS cos_d ' +
      '  FROM loja l ' +
      '  JOIN categoria c ON c.id = l.id_categoria ' +
      '  LEFT JOIN site s ON s.id_loja_ex = l.uuid ' +
      '  WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL ' +
      '    AND l.validade >= CURRENT_DATE' +
      '), DIST AS (' +
      '  SELECT uuid, nome, slug, plano_destaque, categoria_nome, avatar, ' +
      '         6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                          WHEN cos_d < -1.0 THEN -1.0 ' +
      '                          ELSE cos_d END) AS distancia_km ' +
      '  FROM BASE' +
      ') ' +
      'SELECT * FROM DIST ' +
      'WHERE distancia_km <= (:raio_base + plano_destaque * :raio_extra) ' +
      'ORDER BY plano_destaque DESC, distancia_km ASC ' +
      'ROWS :limite;',
      [
        lat, lng, lat,
        RAIO_BASE_KM, RAIO_EXTRA_POR_NIVEL_KM,
        LIMITE_COMERCIOS_PROXIMOS
      ],
      True
    );

    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
      item.Add('uuid',          dataset.FieldByName('uuid'         ).AsString);
      item.Add('nome',          dataset.FieldByName('nome'         ).AsString);
      item.Add('slug',          dataset.FieldByName('slug'         ).AsString);
      item.Add('categoria',     dataset.FieldByName('categoria_nome').AsString);
      item.Add('avatar',        dataset.FieldByName('avatar'       ).AsString);
      item.Add('distancia_km',  RoundTo(dataset.FieldByName('distancia_km').AsFloat, -1));
      item.Add('destacado',     dataset.FieldByName('plano_destaque').AsInteger > 0);
      Result.Add(item);
      dataset.Next;
    end;
  finally
    dsPonto.Free;
    dataset.Free;
  end;
end;

class function TPontoTuristicoModel.GetPontosProximos(slug: string;
  limite: integer): TJSONArray;
var
  dsPonto, dataset: TDataSet;
  lat, lng: Double;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;
  dsPonto := nil;
  dataset := nil;
  try
    dsPonto := TGetData.getData(
      'SELECT id, latitude, longitude FROM ponto_turistico WHERE slug = :slug AND ativo = TRUE;',
      [slug], True
    );

    if (not Assigned(dsPonto)) or dsPonto.IsEmpty then Exit;

    lat := StrToFloatDef(dsPonto.FieldByName('latitude').AsString, 0);
    lng := StrToFloatDef(dsPonto.FieldByName('longitude').AsString, 0);

    // Busca outros pontos em um raio de até 50km
    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '          COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '          SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) AS cos_d ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.slug <> :slug_origem AND p.ativo = TRUE ' +
      '    AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      '), DIST AS (' +
      '  SELECT *, 6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                             WHEN cos_d < -1.0 THEN -1.0 ' +
      '                             ELSE cos_d END) AS distancia_km ' +
      '  FROM BASE' +
      ') ' +
      'SELECT * FROM DIST WHERE distancia_km <= 50 ORDER BY distancia_km ASC ROWS :limite;',
      [lat, lng, lat, slug, limite],
      True
    );

    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
      item.Add('uuid', dataset.FieldByName('uuid').AsString);
      item.Add('nome', dataset.FieldByName('nome').AsString);
      item.Add('slug', dataset.FieldByName('slug').AsString);
      item.Add('resumo', dataset.FieldByName('resumo').AsString);
      item.Add('capa', dataset.FieldByName('capa').AsString);
      item.Add('categoria', dataset.FieldByName('categoria').AsString);
      item.Add('distancia_km', RoundTo(dataset.FieldByName('distancia_km').AsFloat, -1));
      Result.Add(item);
      dataset.Next;
    end;
  finally
    if Assigned(dsPonto) then dsPonto.Free;
    if Assigned(dataset) then dataset.Free;
  end;

end;

class function TPontoTuristicoModel.GetPontosPorGPS(lat, lng: Double; raioKm: Double; limite: integer): TJSONArray;
var
  dataset: TDataSet;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '          COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '          SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) AS cos_d ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.ativo = TRUE AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      '), DIST AS (' +
      '  SELECT *, 6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                             WHEN cos_d < -1.0 THEN -1.0 ' +
      '                             ELSE cos_d END) AS distancia_km ' +
      '  FROM BASE' +
      ') ' +
      'SELECT * FROM DIST WHERE distancia_km <= :raio ORDER BY distancia_km ASC ROWS :limite;',
      [lat, lng, lat, raioKm, limite],
      True
    );

    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
      item.Add('uuid', dataset.FieldByName('uuid').AsString);
      item.Add('nome', dataset.FieldByName('nome').AsString);
      item.Add('slug', dataset.FieldByName('slug').AsString);
      item.Add('resumo', dataset.FieldByName('resumo').AsString);
      item.Add('capa', dataset.FieldByName('capa').AsString);
      item.Add('categoria', dataset.FieldByName('categoria').AsString);
      item.Add('distancia_km', RoundTo(dataset.FieldByName('distancia_km').AsFloat, -1));
      Result.Add(item);
      dataset.Next;
    end;
  finally
    if Assigned(dataset) then dataset.Free;
  end;
end;

class function TPontoTuristicoModel.ListarCategorias: TJSONArray;
var
  dataSet: TDataSet;
  jsonItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  dataSet := nil;
  try
    dataSet := TGetData.getData(
      'SELECT id, nome, slug FROM categoria_ponto_turistico ORDER BY nome;',
      [],
      True
    );

    while not dataSet.EOF do
    begin
      jsonItem := TJSONObject.Create;
      jsonItem.Add('id_categoria', dataSet.FieldByName('id').AsInteger);
      jsonItem.Add('nome',         dataSet.FieldByName('nome').AsString);
      jsonItem.Add('slug',         dataSet.FieldByName('slug').AsString);
      Result.Add(jsonItem);
      dataSet.Next;
    end;
  finally
    dataSet.Free;
  end;
end;

class function TPontoTuristicoModel.Slugify(const AValue: string): string;
const
  DE   = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  PARA = 'aaaaaeeeeiiiiooooouuuucn';   // mesmo nº de caracteres que DE (24)
var
  s, ch: string;
  i, p: Integer;
begin
  s := UTF8LowerCase(Trim(AValue));
  Result := '';
  for i := 1 to UTF8Length(s) do
  begin
    ch := UTF8Copy(s, i, 1);
    p := UTF8Pos(ch, DE);
    if p > 0 then ch := PARA[p];
    if (Length(ch) = 1) and (ch[1] in ['a'..'z', '0'..'9']) then
      Result := Result + ch
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  end;
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
  if Result = '' then Result := 'ponto';
end;

class function TPontoTuristicoModel.GerarNomeArquivoSeguro(
  const NomeOriginal, UuidPonto: string; out NomeFinal: string): Boolean;
var
  ext: string;
  g: TGuid;
begin
  ext := LowerCase(ExtractFileExt(ExtractFileName(NomeOriginal)));
  Result := (ext = '.jpg') or (ext = '.jpeg') or (ext = '.png') or (ext = '.webp');
  if not Result then Exit;
  CreateGUID(g);
  NomeFinal := UuidPonto + '_' +
    StringReplace(StringReplace(GUIDToString(g), '{', '', [rfReplaceAll]),
                  '}', '', [rfReplaceAll]) + ext;
end;

class function TPontoTuristicoModel.GerarSlugUnico(const Base, UuidIgnorar: string): string;
var
  ds: TDataSet;
  n: Integer;
  candidato: string;
begin
  n := 1;
  candidato := Slugify(Base);
  repeat
    ds := TGetData.getData(
      'SELECT 1 FROM ponto_turistico WHERE slug = :slug AND uuid <> :uuid',
      [candidato, UuidIgnorar],
      True
    );
    try
      if ds.IsEmpty then Break;
    finally
      ds.Free;
    end;
    Inc(n);
    candidato := Slugify(Base) + '-' + IntToStr(n);
  until False;
  Result := candidato;
end;

class function TPontoTuristicoModel.TryParseCoord(const S: string;
  Min, Max: Double; out V: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(S), ',', '.', []), V, DefaultFormatSettings)
            and (V >= Min) and (V <= Max);
end;

end.

unit upontoturisticomodel;

interface

uses
  Classes, SysUtils, fpjson, ugetdata, db, base64, Math;

const
  RAIO_BASE_KM            = 5.0;  // raio padrão de visibilidade do comércio
  RAIO_EXTRA_POR_NIVEL_KM = 5.0;  // cada nível de PLANO_DESTAQUE soma esse tanto ao raio
  LIMITE_COMERCIOS_PROXIMOS = 12;

type
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
    class function GetBySlug(slug: string): TJSONObject;
    class function GetComerciosProximos(slug: string): TJSONArray;
    class function GetPontosProximos(slug: string; limite: integer = 6): TJSONArray;
    class function GetPontosPorGPS(lat, lng: Double; raioKm: Double = 30; limite: integer = 10): TJSONArray;
    class function ListarCategorias: TJSONArray;
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
      'SELECT url_foto FROM ponto_turistico_galeria ' +
      'WHERE id_ponto = :idPonto ORDER BY ordem;',
      [idPonto],
      True
    );
    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
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
  caminho_salvar, url_banco, DecodedStr: string;
  StringStream: TStringStream;
begin
  if Trim(galeriaJson) = '' then Exit;

  jsonData := GetJSON(galeriaJson);
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

  StringStream := nil;
  try
    for i := 0 to arrayGaleria.Count - 1 do
    begin
      itemGaleria := arrayGaleria.Objects[i];

      caminho_salvar := ExpandFileName('./uploads/' + uuidString + '_' + itemGaleria.Strings['nome_arquivo']);
      url_banco      := '/imagens/' + uuidString + '_' + itemGaleria.Strings['nome_arquivo'];

      DecodedStr := DecodeStringBase64(itemGaleria.Strings['itemFoto']);
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
  uuidString, url_banco_capa, DecodedStrCapa, caminho_salvar_capa: string;
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
        caminho_salvar_capa := ExpandFileName('./uploads/' + uuidString + '_' + dados.nome_arquivo_capa);
        url_banco_capa      := '/imagens/' + uuidString + '_' + dados.nome_arquivo_capa;

        DecodedStrCapa := DecodeStringBase64(dados.capa);
        StringStream := TStringStream.Create(DecodedStrCapa);
        StringStream.SaveToFile(caminho_salvar_capa);
        FreeAndNil(StringStream);
      end;

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
  uuidString, url_banco_capa, DecodedStrCapa, caminho_salvar_capa: string;
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
      'update ponto_turistico set nome = :nome, slug = :slug, resumo = :resumo, ' +
      'historia = :historia, latitude = :latitude, longitude = :longitude, ' +
      'endereco = :endereco, numero = :numero, bairro = :bairro, cidade = :cidade, ' +
      'uf = :uf, cep = :cep, id_categoria = :id_categoria ' +
      'where id = :id;',
      [
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
        dados.id_categoria,
        idPonto
      ]
    );

    // capa nova é opcional — só troca se vier arquivo no request
    if (dados.nome_arquivo_capa <> '') and (dados.capa <> '') then
    begin
      caminho_salvar_capa := ExpandFileName('./uploads/' + uuidString + '_' + dados.nome_arquivo_capa);
      url_banco_capa      := '/imagens/' + uuidString + '_' + dados.nome_arquivo_capa;

      DecodedStrCapa := DecodeStringBase64(dados.capa);
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
      'WITH DIST AS (' +
      '  SELECT l.uuid, l.nome, l.slug, l.plano_destaque, ' +
      '         c.nome AS categoria_nome, s.avatar, ' +
      '         (6371 * ACOS(' +
      '            COS(RADIANS(:lat)) * COS(RADIANS(l.latitude)) * ' +
      '            COS(RADIANS(l.longitude) - RADIANS(:lng)) + ' +
      '            SIN(RADIANS(:lat)) * SIN(RADIANS(l.latitude))' +
      '         )) AS distancia_km ' +
      '  FROM loja l ' +
      '  JOIN categoria c ON c.id = l.id_categoria ' +
      '  LEFT JOIN site s ON s.id_loja_ex = l.uuid ' +
      '  WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL ' +
      '    AND l.validade >= CURRENT_DATE' +
      ') ' +
      'SELECT * FROM DIST ' +
      'WHERE distancia_km <= (:raio_base + plano_destaque * :raio_extra) ' +
      'ORDER BY plano_destaque DESC, distancia_km ASC ' +
      'ROWS :limite;',
      [
        lat, lng, lat,               // :lat, :lng, :lat (2ª ocorrência)
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
      'WITH DIST AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (6371 * ACOS(' +
      '            CASE ' +
      '              WHEN (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) > 1.0 THEN 1.0 ' +
      '              WHEN (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) < -1.0 THEN -1.0 ' +
      '              ELSE (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) ' +
      '            END' +
      '         )) AS distancia_km ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.slug <> :slug_origem AND p.ativo = TRUE ' +
      '    AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      ') ' +
      'SELECT * FROM DIST WHERE distancia_km <= 50 ORDER BY distancia_km ASC ROWS :limite;',
      [lat, lng, lat, lat, lng, lat, lat, lng, lat, slug, limite],
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
      'WITH DIST AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (6371 * ACOS(' +
      '            CASE ' +
      '              WHEN (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) > 1.0 THEN 1.0 ' +
      '              WHEN (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) < -1.0 THEN -1.0 ' +
      '              ELSE (COS(RADIANS(:lat)) * COS(RADIANS(p.latitude)) * ' +
      '                    COS(RADIANS(p.longitude) - RADIANS(:lng)) + ' +
      '                    SIN(RADIANS(:lat)) * SIN(RADIANS(p.latitude))) ' +
      '            END' +
      '         )) AS distancia_km ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.ativo = TRUE AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      ') ' +
      'SELECT * FROM DIST WHERE distancia_km <= :raio ORDER BY distancia_km ASC ROWS :limite;',
      [lat, lng, lat, lat, lng, lat, lat, lng, lat, raioKm, limite],
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
  arrayItens: TJSONArray;
begin
  dataSet := nil;
  arrayItens := nil;
  try
    try
      Result := TJSONArray.Create;

      dataSet := TGetData.getData(
        'select id, nome from categoria_ponto_turistico;',
        [],
        True
      );

      if not dataSet.IsEmpty then
      begin
        with dataSet do
        begin
          first;
          while not eof do
          begin
            jsonItem := TJSONObject.Create;

            jsonItem.Add('id_categoria', FieldByName('id').AsInteger);
            jsonItem.Add('nome', FieldByName('nome').AsInteger);

            arrayItens.Add(jsonItem);
            next;
          end;
        end;
      end;
    except
      begin
        raise;
      end;
    end;
  finally
    FreeAndNil(dataSet);
  end;
end;

end.

unit upontoturisticomodel;

interface

uses
  Classes, SysUtils, fpjson, ugetdata, db, base64, Math, LazUTF8, StrUtils;

const
  RAIO_BASE_KM            = 5.0;  // raio padrão de visibilidade do comércio
  RAIO_EXTRA_POR_NIVEL_KM = 5.0;  // cada nível de PLANO_DESTAQUE soma esse tanto ao raio
  LIMITE_COMERCIOS_PROXIMOS = 12;
  MAX_IMAGEM_BYTES  = 5 * 1024 * 1024;   // tamanho máximo de cada imagem já decodificada
  MAX_FOTOS_GALERIA = 20;                // máximo de fotos por requisição
  MAX_SLUG_BASE     = 90;                // coluna SLUG = 100; folga para o sufixo "-N"
  MAX_PLANO_DESTAQUE = 3;   // maior nível de PLANO_DESTAQUE em uso; define a caixa do pré-filtro

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

  // Imagem já validada e decodificada, pronta para gravar em disco.
  TImagemPreparada = record
    nomeSeguro: string;   // <uuid do ponto>_<guid>.<ext>
    dados: string;        // bytes decodificados
  end;
  TImagensPreparadas = array of TImagemPreparada;

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
    class procedure RemoveItem(const id: integer);
  private
    class function MontarGaleriaJson(idPonto: integer): TJSONArray;
    class function ConteudoPareceImagem(const dados: string): Boolean;
    class function PrepararImagem(const nomeOriginal, base64Str, uuidPonto, rotulo: string): TImagemPreparada;
    class function PrepararGaleria(const galeriaJson, uuidPonto: string): TImagensPreparadas;
    class procedure SalvarArquivoUpload(const nomeSeguro, dados: string);
    class function CaminhoUploadSeguro(const urlFoto: string; out caminho: string): Boolean;
    class procedure SalvarItensGaleria(const itens: TImagensPreparadas; idPonto: integer);
  end;

implementation

uses uguiatourutils;


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

// Confere a "assinatura" (magic bytes) do arquivo: JPEG, PNG ou WEBP.
// Impede que um arquivo qualquer seja enviado apenas trocando a extensão.
class function TPontoTuristicoModel.ConteudoPareceImagem(const dados: string): Boolean;
begin
  Result := False;
  if Length(dados) < 12 then Exit;

  // JPEG: FF D8 FF
  if (dados[1] = #$FF) and (dados[2] = #$D8) and (dados[3] = #$FF) then
  begin
    Result := True;
    Exit;
  end;

  // PNG: 89 'PNG' 0D 0A 1A 0A
  if Copy(dados, 1, 8) = (#$89 + 'PNG' + #$0D#$0A#$1A#$0A) then
  begin
    Result := True;
    Exit;
  end;

  // WEBP: 'RIFF' ???? 'WEBP'
  if (Copy(dados, 1, 4) = 'RIFF') and (Copy(dados, 9, 4) = 'WEBP') then
    Result := True;
end;

// Valida (extensão, tamanho, base64 e conteúdo) e decodifica UMA imagem.
// Não grava nada em disco — assim dá pra validar tudo antes de tocar no banco.
class function TPontoTuristicoModel.PrepararImagem(
  const nomeOriginal, base64Str, uuidPonto, rotulo: string): TImagemPreparada;
var
  limiteBase64: Integer;
begin
  Result.nomeSeguro := '';
  Result.dados := '';

  if not GerarNomeArquivoSeguro(nomeOriginal, uuidPonto, Result.nomeSeguro) then
    raise EImagemInvalida.Create('Extensão de imagem ' + rotulo + ' não permitida.');

  // rejeita antes de decodificar strings gigantes (base64 ocupa ~4/3 do original)
  limiteBase64 := ((MAX_IMAGEM_BYTES + 2) div 3) * 4 + 8;
  if Length(base64Str) > limiteBase64 then
    raise EImagemInvalida.Create('Imagem ' + rotulo + ' muito grande.');

  try
    Result.dados := DecodeStringBase64(base64Str);
  except
    raise EImagemInvalida.Create('Imagem ' + rotulo + ' com base64 inválido.');
  end;

  if Length(Result.dados) > MAX_IMAGEM_BYTES then
    raise EImagemInvalida.Create('Imagem ' + rotulo + ' muito grande.');

  if not ConteudoPareceImagem(Result.dados) then
    raise EImagemInvalida.Create('Arquivo ' + rotulo + ' não é uma imagem JPEG, PNG ou WEBP válida.');
end;

// Valida e decodifica todas as fotos da galeria de uma vez.
// Se qualquer foto for inválida, levanta EImagemInvalida sem ter gravado nada.
class function TPontoTuristicoModel.PrepararGaleria(
  const galeriaJson, uuidPonto: string): TImagensPreparadas;
var
  jsonData: TJSONData;
  arrayGaleria: TJSONArray;
  itemGaleria: TJSONObject;
  i, k: integer;
  nome_arquivo, itemFoto: string;
begin
  Result := nil;
  if Trim(galeriaJson) = '' then Exit;

  try
    jsonData := GetJSON(galeriaJson);
  except
    raise EImagemInvalida.Create('Galeria em formato inválido.');
  end;

  try
    if jsonData.JSONType <> jtArray then
      raise EImagemInvalida.Create('Galeria em formato inválido.');

    arrayGaleria := TJSONArray(jsonData);
    if arrayGaleria.Count > MAX_FOTOS_GALERIA then
      raise EImagemInvalida.Create('Fotos demais em uma única requisição.');

    SetLength(Result, arrayGaleria.Count);
    k := 0;
    for i := 0 to arrayGaleria.Count - 1 do
    begin
      if arrayGaleria.Items[i].JSONType <> jtObject then Continue;

      itemGaleria  := arrayGaleria.Objects[i];
      nome_arquivo := itemGaleria.Get('nome_arquivo', '');
      itemFoto     := itemGaleria.Get('itemFoto', '');

      if (nome_arquivo = '') or (itemFoto = '') then Continue;

      Result[k] := PrepararImagem(nome_arquivo, itemFoto, uuidPonto, 'da galeria');
      Inc(k);
    end;
    SetLength(Result, k);
  finally
    jsonData.Free;
  end;
end;

class procedure TPontoTuristicoModel.SalvarArquivoUpload(const nomeSeguro, dados: string);
var
  fs: TFileStream;
begin
  ForceDirectories(ExpandFileName('./uploads'));
  fs := TFileStream.Create(ExpandFileName('./uploads/' + nomeSeguro), fmCreate);
  try
    if Length(dados) > 0 then
      fs.WriteBuffer(dados[1], Length(dados));
  finally
    fs.Free;
  end;
end;

// Converte uma URL '/imagens/arquivo.ext' no caminho físico dentro de ./uploads,
// garantindo que o resultado NÃO sai dessa pasta.
class function TPontoTuristicoModel.CaminhoUploadSeguro(const urlFoto: string;
  out caminho: string): Boolean;
var
  pasta, nome: string;
begin
  Result := False;
  caminho := '';

  if Pos('/imagens/', urlFoto) <> 1 then Exit;

  nome := ExtractFileName(Copy(urlFoto, Length('/imagens/') + 1, MaxInt));
  if (nome = '') or (nome = '.') or (nome = '..') then Exit;

  pasta   := IncludeTrailingPathDelimiter(ExpandFileName('./uploads'));
  caminho := ExpandFileName(pasta + nome);

  Result := Pos(pasta, caminho) = 1;
end;

// Grava em disco e insere a linha de cada foto JÁ VALIDADA, mantendo a ordem
// recebida (soma à ordem que já existir, pra suportar "adicionar mais fotos"
// em cima de um ponto já existente).
class procedure TPontoTuristicoModel.SalvarItensGaleria(const itens: TImagensPreparadas;
  idPonto: integer);
var
  dataset: TDataSet;
  i, ordemBase: integer;
begin
  if Length(itens) = 0 then Exit;

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

  for i := 0 to High(itens) do
  begin
    SalvarArquivoUpload(itens[i].nomeSeguro, itens[i].dados);

    TGetData.getData(
      'insert into ponto_turistico_galeria(id_ponto, url_foto, ordem) ' +
      'values(:id_ponto, :url_foto, :ordem);',
      [idPonto, '/imagens/' + itens[i].nomeSeguro, ordemBase + i]
    );
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
  uuidString, url_banco_capa, caminho_capa: string;
  idPonto: integer;
  latV, lngV: Double;
  temCapa, capaSalva: Boolean;
  capaPreparada: TImagemPreparada;
  galeriaPreparada: TImagensPreparadas;
begin
  dataSet := nil;
  url_banco_capa := '';
  caminho_capa := '';
  idPonto := 0;
  capaSalva := False;
  try
    if not (TryParseCoord(dados.latitude,  -90,  90,  latV) and
            TryParseCoord(dados.longitude, -180, 180, lngV)) then
      raise Exception.Create('Coordenadas inválidas.');

    CreateGUID(uuid);
    uuidString := StringReplace(StringReplace(GUIDToString(uuid),
                    '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);

    // 1) VALIDA TUDO ANTES de gravar qualquer coisa (banco ou disco).
    //    Se alguma imagem for inválida, EImagemInvalida sobe e nada foi criado.
    temCapa := (dados.nome_arquivo_capa <> '') and (dados.capa <> '');
    if temCapa then
      capaPreparada := PrepararImagem(dados.nome_arquivo_capa, dados.capa, uuidString, 'da capa');

    galeriaPreparada := PrepararGaleria(dados.galeria, uuidString);

    // 2) slug único gerado no servidor
    dados.slug := GerarSlugUnico(IfThen(dados.slug <> '', dados.slug, dados.nome));

    // 3) a capa usa o uuid recém-gerado no nome do arquivo — não depende
    //    do id numérico, então dá pra salvar o arquivo antes do insert
    if temCapa then
    begin
      SalvarArquivoUpload(capaPreparada.nomeSeguro, capaPreparada.dados);
      capaSalva      := True;
      url_banco_capa := '/imagens/' + capaPreparada.nomeSeguro;
      caminho_capa   := ExpandFileName('./uploads/' + capaPreparada.nomeSeguro);
    end;

    try
      // ATIVO entra explícito como TRUE (ponto já aparece nas rotas públicas).
      // Se preferir moderação, troque o TRUE do SQL por FALSE.
      dataSet := TGetData.getData(
        'insert into ponto_turistico(uuid, id_vendedor, id_categoria, nome, slug, ' +
        'resumo, historia, latitude, longitude, endereco, numero, bairro, cidade, ' +
        'uf, cep, capa, ativo) ' +
        'values(:uuid, (select id from vendedor where uuid = :idVendedor), :idCategoria, ' +
        ':nome, :slug, :resumo, :historia, :latitude, :longitude, :endereco, :numero, ' +
        ':bairro, :cidade, :uf, :cep, :capa, TRUE) ' +
        'returning id;',
        [
          uuidString,
          dados.idVendedor,
          dados.id_categoria,
          dados.nome,
          dados.slug,
          dados.resumo,
          dados.historia,
          latV,
          lngV,
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

      SalvarItensGaleria(galeriaPreparada, idPonto);
    except
      // falhou depois de começar a gravar: desfaz o que der pra não deixar
      // um ponto pela metade (o front recebe erro e pode tentar de novo)
      if idPonto > 0 then
      begin
        try
          TGetData.getData('DELETE FROM ponto_turistico_galeria WHERE id_ponto = :id;', [idPonto]);
          TGetData.getData('DELETE FROM ponto_turistico WHERE id = :id;', [idPonto]);
        except
          // melhor esforço
        end;
      end;
      if capaSalva and (caminho_capa <> '') and FileExists(caminho_capa) then
        DeleteFile(caminho_capa);
      raise;
    end;

    Result := uuidString;
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
  uuidString, url_banco_capa: string;
  latV, lngV: Double;
  temCapa: Boolean;
  capaPreparada: TImagemPreparada;
  galeriaPreparada: TImagensPreparadas;
begin
  Result := False;
  dataset := nil;
  try
    dataset := TGetData.getData(
      'SELECT id, uuid FROM ponto_turistico WHERE uuid = :uuidPonto;',
      [uuidPonto],
      True
    );
    if (not Assigned(dataset)) or dataset.IsEmpty then Exit;

    idPonto    := dataset.FieldByName('id'  ).AsInteger;
    uuidString := dataset.FieldByName('uuid').AsString;

    if not (TryParseCoord(dados.latitude,  -90,  90,  latV) and
            TryParseCoord(dados.longitude, -180, 180, lngV)) then
      raise Exception.Create('Coordenadas inválidas.');

    // VALIDA TUDO (capa e galeria) ANTES do UPDATE: se algo for inválido,
    // EImagemInvalida sobe e o ponto não é alterado pela metade.
    temCapa := (dados.nome_arquivo_capa <> '') and (dados.capa <> '');
    if temCapa then
      capaPreparada := PrepararImagem(dados.nome_arquivo_capa, dados.capa, uuidString, 'da capa');

    galeriaPreparada := PrepararGaleria(dados.galeria, uuidString);

    // o slug NÃO é alterado na edição (mantém links já compartilhados)
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
        latV,
        lngV,
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
    if temCapa then
    begin
      SalvarArquivoUpload(capaPreparada.nomeSeguro, capaPreparada.dados);
      url_banco_capa := '/imagens/' + capaPreparada.nomeSeguro;

      TGetData.getData(
        'update ponto_turistico set capa = :capa where id = :id;',
        [url_banco_capa, idPonto]
      );
    end;

    // fotos novas de galeria são adicionadas às existentes (não substitui)
    SalvarItensGaleria(galeriaPreparada, idPonto);

    Result := True;
  finally
    dataset.Free;
  end;
end;

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

    // Apaga do banco (repete a checagem de dono no próprio DELETE)
    TGetData.getData(
      'DELETE FROM ponto_turistico_galeria ' +
      'WHERE id = :idFoto AND id_ponto = (SELECT id FROM ponto_turistico WHERE uuid = :uuid);',
      [idFoto, uuidPonto]
    );

    // Apaga do disco só se o caminho resolvido ficar dentro de ./uploads
    if CaminhoUploadSeguro(url_foto, caminho_arquivo) then
    begin
      if FileExists(caminho_arquivo) then
        DeleteFile(caminho_arquivo);
    end;

    Result := True;
  finally
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
  lat, lng, raioMax: Double;
  latMin, latMax, lngMin, lngMax: Double;
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
    if dsPonto.FieldByName('latitude').IsNull or
       dsPonto.FieldByName('longitude').IsNull then Exit;

    lat := dsPonto.FieldByName('latitude' ).AsFloat;
    lng := dsPonto.FieldByName('longitude').AsFloat;

    raioMax := RAIO_BASE_KM + MAX_PLANO_DESTAQUE * RAIO_EXTRA_POR_NIVEL_KM;
    CalcularCaixa(lat, lng, raioMax, latMin, latMax, lngMin, lngMax);

    //gkey:'AIzaSyA5M4yVTKwcI-vHz8qbE0yLiP6hfLCy8MM',mapId:'a49c24d7ae14e69f3d88399e'

    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT l.uuid, l.nome, l.slug, ' +
      '         COALESCE(l.plano_destaque, 0) AS plano_destaque, ' +
      '         c.nome AS categoria_nome, s.avatar, ' +
      '         l.latitude AS lat_c, l.longitude AS lng_c, ' +
      '         (COS(CAST(:lat1 AS DOUBLE PRECISION) * 0.017453292519943295) * COS(l.latitude * 0.017453292519943295) * ' +
      '          COS(l.longitude * 0.017453292519943295 - CAST(:lng AS DOUBLE PRECISION) * 0.017453292519943295) + ' +
      '          SIN(CAST(:lat2 AS DOUBLE PRECISION) * 0.017453292519943295) * SIN(l.latitude * 0.017453292519943295)) AS cos_d ' +
      '  FROM loja l ' +
      '  JOIN categoria c ON c.id = l.id_categoria ' +
      '  LEFT JOIN site s ON s.id_loja_ex = l.uuid ' +
      '  WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL ' +
      '    AND l.validade >= CURRENT_DATE ' +
      '    AND l.latitude  BETWEEN :lat_min AND :lat_max ' +
      '    AND l.longitude BETWEEN :lng_min AND :lng_max' +
      '), DIST AS (' +
      '  SELECT uuid, nome, slug, plano_destaque, categoria_nome, avatar, ' +
      '         lat_c, lng_c, ' +
      '         6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                          WHEN cos_d < -1.0 THEN -1.0 ' +
      '                          ELSE cos_d END) AS distancia_km ' +
      '  FROM BASE' +
      ') ' +
      'SELECT * FROM DIST ' +
      'WHERE distancia_km <= (CAST(:raio_base AS DOUBLE PRECISION) + plano_destaque * CAST(:raio_extra AS DOUBLE PRECISION)) ' +
      'ORDER BY plano_destaque DESC, distancia_km ASC ' +
      'ROWS :limite;',
      [
        lat, lng, lat,
        latMin, latMax, lngMin, lngMax,
        RAIO_BASE_KM, RAIO_EXTRA_POR_NIVEL_KM,
        LIMITE_COMERCIOS_PROXIMOS
      ],
      True
    );

    while not dataset.EOF do
    begin
      item := TJSONObject.Create;
      item.Add('uuid',         dataset.FieldByName('uuid'          ).AsString);
      item.Add('nome',         dataset.FieldByName('nome'          ).AsString);
      item.Add('slug',         dataset.FieldByName('slug'          ).AsString);
      item.Add('categoria',    dataset.FieldByName('categoria_nome').AsString);
      item.Add('avatar',       dataset.FieldByName('avatar'        ).AsString);
      item.Add('latitude',     dataset.FieldByName('lat_c'         ).AsFloat);
      item.Add('longitude',    dataset.FieldByName('lng_c'         ).AsFloat);
      item.Add('distancia_km', RoundTo(dataset.FieldByName('distancia_km').AsFloat, -1));
      item.Add('destacado',    dataset.FieldByName('plano_destaque').AsInteger > 0);
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

    // AsFloat (e não AsString + StrToFloatDef): não depende do separador decimal do sistema
    lat := dsPonto.FieldByName('latitude').AsFloat;
    lng := dsPonto.FieldByName('longitude').AsFloat;

    // Busca outros pontos em um raio de até 50km.
    // No Firebird o "*" precisa vir qualificado (BASE.*) quando há outras colunas no SELECT.
    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (COS(CAST(:lat1 AS DOUBLE PRECISION) * 0.017453292519943295) * COS(p.latitude * 0.017453292519943295) * ' +
      '          COS(p.longitude * 0.017453292519943295 - CAST(:lng AS DOUBLE PRECISION) * 0.017453292519943295) + ' +
      '          SIN(CAST(:lat2 AS DOUBLE PRECISION) * 0.017453292519943295) * SIN(p.latitude * 0.017453292519943295)) AS cos_d ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.slug <> :slug_origem AND p.ativo = TRUE ' +
      '    AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      '), DIST AS (' +
      '  SELECT BASE.*, 6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                                  WHEN cos_d < -1.0 THEN -1.0 ' +
      '                                  ELSE cos_d END) AS distancia_km ' +
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
    // No Firebird o "*" precisa vir qualificado (BASE.*) quando há outras colunas no SELECT.
    dataset := TGetData.getData(
      'WITH BASE AS (' +
      '  SELECT p.uuid, p.nome, p.slug, p.resumo, p.capa, c.nome AS categoria, ' +
      '         (COS(CAST(:lat1 AS DOUBLE PRECISION) * 0.017453292519943295) * COS(p.latitude * 0.017453292519943295) * ' +
      '          COS(p.longitude * 0.017453292519943295 - CAST(:lng AS DOUBLE PRECISION) * 0.017453292519943295) + ' +
      '          SIN(CAST(:lat2 AS DOUBLE PRECISION) * 0.017453292519943295) * SIN(p.latitude * 0.017453292519943295)) AS cos_d ' +
      '  FROM ponto_turistico p ' +
      '  JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
      '  WHERE p.ativo = TRUE AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL' +
      '), DIST AS (' +
      '  SELECT BASE.*, 6371 * ACOS(CASE WHEN cos_d > 1.0 THEN 1.0 ' +
      '                                  WHEN cos_d < -1.0 THEN -1.0 ' +
      '                                  ELSE cos_d END) AS distancia_km ' +
      '  FROM BASE' +
      ') ' +
      'SELECT * FROM DIST WHERE distancia_km <= :raio ORDER BY distancia_km ASC ROWS :limite;',
      [
        lat,
        lng,
        lat,
        raioKm,
        limite
      ],
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
  NomeFinal := '';
  ext := LowerCase(ExtractFileExt(ExtractFileName(NomeOriginal)));
  Result := (ext = '.jpg') or (ext = '.jpeg') or (ext = '.png') or (ext = '.webp');
  if not Result then Exit;
  CreateGUID(g);
  NomeFinal := UuidPonto + '_' +
    StringReplace(StringReplace(GUIDToString(g), '{', '', [rfReplaceAll]),
                  '}', '', [rfReplaceAll]) + ext;
end;

class procedure TPontoTuristicoModel.RemoveItem(const id: integer);
var
  dataset: TDataSet;
  url_foto: string;
begin
  try
    url_foto := '';
    dataset := TGetData.getData(
      'select url_foto from PONTO_TURISTICO_GALERIA where id = :id',
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
      'delete from PONTO_TURISTICO_GALERIA where id = :id',
      [id]
    );
  except
    raise;
  end;
end;

class function TPontoTuristicoModel.GerarSlugUnico(const Base: string;
  const UuidIgnorar: string): string;
var
  ds: TDataSet;
  n: Integer;
  slugBase, candidato: string;
begin
  // limita o tamanho da base para caber na coluna mesmo com o sufixo "-N"
  slugBase := Slugify(Base);
  if Length(slugBase) > MAX_SLUG_BASE then
  begin
    slugBase := Copy(slugBase, 1, MAX_SLUG_BASE);
    while (slugBase <> '') and (slugBase[Length(slugBase)] = '-') do
      Delete(slugBase, Length(slugBase), 1);
  end;

  n := 1;
  candidato := slugBase;
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
    candidato := slugBase + '-' + IntToStr(n);
  until False;
  Result := candidato;
end;

// Converte "-23.05" ou "-23,05" em Double, aceitando só valores dentro de [Min, Max].
// Independe do separador decimal configurado no sistema operacional.
class function TPontoTuristicoModel.TryParseCoord(const S: string;
  Min, Max: Double; out V: Double): Boolean;
var
  T: string;
  fs: TFormatSettings;
  i: Integer;
begin
  Result := False;
  V := 0;

  T := Trim(S);
  if T = '' then Exit;

  // só dígitos, sinal e separador decimal — barra "nan", "inf" e notação
  // científica ("1e5"), que fariam a comparação com Min/Max levantar exceção
  for i := 1 to Length(T) do
    if not (T[i] in ['0'..'9', '.', ',', '-', '+']) then Exit;

  // rejeita "1.234,56", "1,2,3" etc.: no máximo um separador decimal
  if (Pos(',', T) > 0) and (Pos('.', T) > 0) then Exit;
  if Length(T) - Length(StringReplace(T, ',', '', [rfReplaceAll])) > 1 then Exit;

  T := StringReplace(T, ',', '.', []);

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';

  Result := TryStrToFloat(T, V, fs) and (V >= Min) and (V <= Max);
  if not Result then V := 0;
end;

end.

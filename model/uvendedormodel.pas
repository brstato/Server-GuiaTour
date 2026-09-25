unit uvendedormodel;

interface

uses
  Classes, SysUtils, fpjson, ugetdata, db, base64;

Type
  TVendorList = record
    idVendedor,
    nome,
    telefone,
    email,
    slug,
    insta,
    cep,
    endereco,
    complemento,
    bairro,
    cidade,
    estado,
    numero,
    g_analytcs,
    meta_pixel_id,
    conta_google_ads,
    horario,
    titulo,
    subtitulo,
    bio,
    foto_bio,
    nome_arquivo_foto_bio,
    avatar,
    nome_arquivo_foto_avatar,
    foto_capa,
    nome_arquivo_foto_capa,
    trabalhos: string;
    id_categoria: integer
  end;


type
  TVendedorModel = class
  public
    class function DonoDaLoja(idVendedor, uuidLoja: string): Boolean;
    class function ListarComercios(idVendedor: string): TJSONArray;
    class function CriarComercio(vendor: TVendorList): string;
    class procedure RegistrarLog(idVendedor, uuidLoja, acao: string);
  end;

implementation

class function TVendedorModel.DonoDaLoja(idVendedor, uuidLoja: string): Boolean;
var
  dataset: TDataSet;
begin
    dataset := nil;
    try
      try
        Result := False;
        if (idVendedor = '') or (uuidLoja = '') then Exit;

        dataset := TGetData.getData(
            'SELECT 1 FROM loja l JOIN vendedor v ON v.id = l.id_vendedor ' +
            'WHERE l.uuid = :uuidLoja AND v.uuid = :idVendedor',
            [uuidLoja, idVendedor],
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

class function TVendedorModel.ListarComercios(idVendedor: string): TJSONArray;
var
  dataset: TDataSet;
  item: TJSONObject;
begin
  dataset := nil;
  try
    try
      Result := TJSONArray.Create;

      dataset := TGetData.getData(
        'SELECT l.uuid, l.nome, l.slug, l.validade FROM loja l ' +
        'JOIN vendedor v ON v.id = l.id_vendedor ' +
        'WHERE v.uuid = :idVendedor ORDER BY l.nome',
        [idVendedor],
        True
      );
      while not dataset.EOF do
      begin
        item := TJSONObject.Create;
        item.Add('uuid', dataset.FieldByName('uuid').AsString);
        item.Add('nome', dataset.FieldByName('nome').AsString);
        item.Add('slug', dataset.FieldByName('slug').AsString);
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

class function TVendedorModel.CriarComercio(vendor: TVendorList): string;
var
  dataSet: TDataSet;
  uuid: TGuid;
  uuidString, idLoja, urlFoto, nome_arquivo, DecodedStr,
    avatar_antigo, url_banco_avatar,
    DecodedStrAvatar, caminho_salvar_avatar, caminho_salvar_fotobio,
    url_banco_fotobio, caminho_salvar_fotocapa, url_banco_fotocapa,
    DecodedStrFotoBio, DecodedStrFotocapa, caminho_salvar, url_banco: string;
  idSite, i, item: integer;
  arrayTrabalhos: TJSONArray;
  itemTrabalho: TJSONObject;
  jsonData: TJSONData;
  StringStream: TStringStream;
begin
  arrayTrabalhos := nil;
  itemTrabalho := nil;
  dataSet := nil;
  try
    try
      CreateGUID(uuid);
      uuidString := StringReplace(StringReplace(GUIDToString(uuid),
                      '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);

      dataSet := TGetData.getData(
          'insert into loja(nome, telefone, email, slug, uuid, id_categoria, ' +
          'validade, id_vendedor, endereco, bairro, cep, cidade, complemento, '+
          'numero, uf, insta, meta_pixel_id, google_ads_id, google_analytics_id, '+
          'horarios) ' +
          'values(:nome, :telefone, :email, :slug, :uuid, :idCategoria, ' +
          ':validade, (select id from vendedor where uuid = :idVendedor), '+
          ':endereco, :bairro, :cep, :cidade, :complemento, '+
          ':numero, :uf, :insta, :meta_pixel_id, :google_ads_id, '+
          ':google_analytics_id, :horarios) '+
          'returning uuid;',
          [
              vendor.nome,
              vendor.telefone,
              vendor.email,
              vendor.slug,
              uuidString,
              vendor.id_categoria,
              StrToDate(FormatDateTime('dd/mm/yyyy', IncMonth(Now, 1))),
              vendor.idVendedor,
              vendor.endereco,
              vendor.bairro,
              vendor.cep,
              vendor.cidade,
              vendor.complemento,
              vendor.numero,
              vendor.estado,
              vendor.insta,
              vendor.meta_pixel_id,
              vendor.conta_google_ads,
              vendor.g_analytcs,
              vendor.horario
          ],
          true
      );

      idLoja := dataSet.Fields[0].AsString;

      caminho_salvar_avatar := ExpandFileName('./uploads/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar);
      url_banco_avatar      := ExpandFileName('/imagens/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar);

      DecodedStrAvatar := DecodeStringBase64(vendor.avatar);
      StringStream := TStringStream.Create(DecodedStrAvatar);
      StringStream.SaveToFile(caminho_salvar_avatar);
      FreeAndNil(StringStream);

      caminho_salvar_fotobio := ExpandFileName('./uploads/' + uuidString + '_' + vendor.nome_arquivo_foto_bio);
      url_banco_fotobio      := ExpandFileName('/imagens/' + uuidString + '_' + vendor.nome_arquivo_foto_bio);

      DecodedStrFotoBio := DecodeStringBase64(vendor.foto_bio);
      StringStream := TStringStream.Create(DecodedStrFotoBio);
      StringStream.SaveToFile(caminho_salvar_fotobio);
      FreeAndNil(StringStream);

      caminho_salvar_fotocapa := ExpandFileName('./uploads/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar);
      url_banco_fotocapa      := ExpandFileName('/imagens/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar);

      DecodedStrFotocapa := DecodeStringBase64(vendor.foto_capa);
      StringStream := TStringStream.Create(DecodedStrFotocapa);
      StringStream.SaveToFile(caminho_salvar_fotocapa);
      FreeAndNil(StringStream);

      dataset := TGetData.getData(
          'insert into site(titulo, subtitulo, avatar, foto_bio, bio, foto_capa, id_loja_ex) ' +
          'values(:titulo, :subtitulo, :avatar, :foto_bio, :bio, :foto_capa, :id_loja_ex) ' +
          'returning id;',
          [
              vendor.titulo,
              vendor.subtitulo,
              caminho_salvar_avatar,
              caminho_salvar_fotobio,
              vendor.bio,
              caminho_salvar_fotocapa,
              idLoja
          ],
          True
      );

      idSite := dataSet.Fields[0].AsInteger;

      jsonData := GetJSON(vendor.trabalhos);

      if jsonData.JSONType = jtArray then
      begin
        arrayTrabalhos := TJSONArray(jsonData);

        for i := 0 to arrayTrabalhos.Count -1 do
        begin
           itemTrabalho := arrayTrabalhos.Objects[i];

           caminho_salvar := ExpandFileName('./uploads/' + uuidString + '_' + itemTrabalho.Strings['nome_arquivo']);
           url_banco      := ExpandFileName('/imagens/' + uuidString + '_' + itemTrabalho.Strings['nome_arquivo']);

           DecodedStr := DecodeStringBase64(itemTrabalho.Strings['itemTrabalho']);
           StringStream := TStringStream.Create(DecodedStr);
           StringStream.SaveToFile(caminho_salvar);
           FreeAndNil(StringStream);

           TGetData.getData(
             'insert into site_galeria(id_site, url_foto) values(:id_site, :url_foto);',
             [idSite, url_banco]
           );
        end;
      end;

      RegistrarLog(vendor.idVendedor, idLoja, 'criou_loja');

      Result := idLoja;
    except
      raise;
    end;
  finally
      StringStream.Free;
      dataset.Free;
  end;
end;

class procedure TVendedorModel.RegistrarLog(idVendedor, uuidLoja, acao: string);
begin
    try
        TGetData.getData(
            'insert into log_acao_vendedor(id_vendedor, id_loja, acao) ' +
            'values((select id from vendedor where uuid = :idVendedor), :uuidLoja, :acao);',
            [
                idVendedor, 
                uuidLoja, 
                acao
            ]
        );      
    except
        raise;
    end;
end;

end.

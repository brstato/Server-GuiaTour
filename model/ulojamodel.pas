unit ulojamodel;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, udata, ugetdata, sql_queries, uNetService,
  ZDataset, fpjson, BCrypt, DateUtils, db;

type
  TLojaReturn = Record
    id,
    nome,
    telefone,
    email,
    zap_instance,
    horario_str,
    slug,
    logradouro,
    cidade,
    uf,
    cep,
    numero,
    complemento,
    bairro,
    meta_pixel,
    g_tag,
    insta_str,
    meta_long_token,
    MetaAdsId,
    StatusCampanha,
    google_ads_nome,
    google_ads_id: string;
    latitude,
    longitude: double;
    id_categoria: integer;
  end;

type
  TEnderecoData = record
    Street: string;
    Neighborhood: string;
    City: string;
    State: string;
    Latitude: string;
    Longitude: string;
    Valid: Boolean;
    ErrorMsg: string;
  end;

type

  { TLojaModel }

  TLojaModel = class
  private

    public
       function createloja(const ANome, ATelefone, AEmail, horario, slug: UTF8String
         ): integer; overload;
       class function createloja(const ANome, AEmail: string):string; overload;
       procedure updateAccount(const LojaDados: TLojaReturn);
       function getDataAccount(const id: string): TJSONObject;
       class function GetInfoStudio(const slug: string): TJSONObject;
       class function get_slug(slug, id:string): Boolean;
       class function get_endereco(var json: TJSONObject): TJSONObject;
       class procedure UpdateMetaLongToken(id, token:string);
       class procedure UpdateMetaAdsId(id, MetaAdsId: string);
       class procedure UpdateMetaPixelId(id, MetaPixelId: string);
       class procedure UpdateGoogleAnalyticsId(id, GoogleAnalyticsId: string);
       class procedure UpdateStatusCampanhaMeta(id: string; StatusCampanhaMeta: Boolean);
       class procedure UpdateAccounBasico(id, nome, apelido: string;
         id_categoria:integer);
       class procedure UpdateAccounContato(id, telefone, email, instagram: string);
       class procedure UpdateEndereco(id, cep, endereco, numero, bairro, cidade,
         estado, complemento: string);
       class function GetEnderecoCep(ACEP: string): TJSONObject;
       class procedure UpdateConfiguracoesAvancadas(id_loja, g_analytcs,
        meta_pixel_id, conta_google_ads, horario: string);
       class function GerarSlug(const Texto: string): string;
       class function GetCategorias: TJSONArray;

  end;

implementation

{ TLojaModel }


class function TLojaModel.GerarSlug(const Texto: string): string;
const
  ComAcento = 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ';
  SemAcento = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
var
  i, p: Integer;
begin
  Result := Trim(Texto);
  Result := StringReplace(Result, ' ', '-', [rfReplaceAll]);
  Result := LowerCase(Result);

  for i := 1 to Length(Result) do
  begin
    p := Pos(Result[i], ComAcento);
    if p > 0 then
      Result[i] := SemAcento[p];
  end;

  if Length(Result) > 20 then
    Result := Copy(Result, 1, 20);
end;

class function TLojaModel.GetCategorias: TJSONArray;
var
  jsonItem:TJSONObject;
  dataSet: TDataSet;
begin
  dataSet := nil;
  Result := nil;
  try
    try
      dataSet := TGetData.getData(
        'SELECT id, nome FROM categoria WHERE ativa = TRUE ORDER BY ordem, nome;',
        [],
        True
      );
      Result := TJSONArray.Create;
      dataSet.First;
      while not dataSet.EOF do
      begin
        jsonItem := TJSONObject.Create;
        jsonItem.Add('categoria_id',   dataSet.FieldByName('id'  ).AsInteger);
        jsonItem.Add('categoria_nome', dataSet.FieldByName('nome').AsString);
        Result.Add(jsonItem);
        dataSet.Next;
      end;
    except
      raise;
    end;
  finally
    FreeAndNil(dataSet);
  end;
end;


function bcript(const AText: string): string;
begin
   Result:=TBCrypt.GenerateHash(AText);
end;

function TLojaModel.createloja(const ANome, ATelefone, AEmail, horario, slug: UTF8String): integer;
var
   Query: TZQuery;
   id: integer;
   uuid: TGuid;
   uuidString, message: string;
   getdata: TGetData;
   dataset: TDataSet;
begin
   getdata := TGetData.Create;
     try
       CreateGUID(uuid);

       uuidString:=stringreplace(GUIDToString(uuid), '{','',[rfReplaceAll]);
       uuidString:=stringreplace(uuidString, '}','',[rfReplaceAll]);

       id := -1;
       Query := TZQuery.Create(nil);
       try
          with Query do
          begin
            Connection := DataModule1.ZConnection1;
            sql.Clear;
            sql.Add(sql_queries.criar_loja_simples);
            ParamByName('nome'          ).AsString    :=ANome;
            ParamByName('email'         ).AsString    :=AEmail;
            ParamByName('telefone'      ).AsString    :=ATelefone;
            //ParamByName('senha'         ).AsString    :=bcript(ASenha);
            ParamByName('validade'      ).AsDate      :=strtodate(FormatDateTime('dd/mm/yyyy', IncMonth(Now, 1)));
            ParamByName('uuid'          ).AsString    :=uuidString;
            ParamByName('CONFIG_HORARIO').AsUTF8String:=horario;
            ParamByName('slug'          ).AsString    :=slug;
            Open;

            id := FieldByName('id').AsInteger;
          end;
       finally
          Query.Free;
         Result := id;
       end;
     except raise;
     end;
end;

class function TLojaModel.createloja(const ANome, AEmail: string): string;
var
   getdata: TGetData;
   dataset: TDataSet;
   uuidString, id, slug: string;
   uuid: TGuid;
begin
   id := '';
   try
     try
       CreateGUID(uuid);

       uuidString:=stringreplace(GUIDToString(uuid), '{','',[rfReplaceAll]);
       uuidString:=stringreplace(uuidString, '}','',[rfReplaceAll]);

       slug := GerarSlug(ANome +' '+ uuidString);

       getdata := TGetData.Create;

       dataset := getdata.getData(
         'insert into loja(nome, email, validade, slug, '+
         'uuid) values(:nome, :email, :validade, :slug, :uuid) returning uuid;',
         [
           ANome,
           AEmail,
           strtodate(FormatDateTime('dd/mm/yyyy', IncMonth(Now, 1))),
           slug,
           uuidString
         ],
         True
       );

       id := dataset.FieldByName('uuid').AsString;
       Result := id;
     finally
       getdata.Free;
       dataset.Free;
     end;
   except
     raise;
   end;
end;

procedure TLojaModel.updateAccount(const LojaDados: TLojaReturn);
var
   senha: string;
   StringError: TStringList;
begin
   try
       TGetData.getData(
         'update loja set nome = :nome, email = :email, telefone '+
         '= :telefone, CONFIG_HORARIO = :CONFIG_HORARIO, slug = :slug, '+
         'logradouro = :ALogradouro, uf = :AUf, cidade = :ACidade, cep = :ACEP, '+
         'bairro = :ABairro, complemento = :AComplemento, numero = :ANumero, '+
         'meta_pixel_id = :meta_pixel, google_analytics_id = :g_analytics, '+
         'insta = :insta, latitude = :latitude, longitude = :longitude, '+
         'google_ads_id = :g_ads_id, google_ads_nome = :g_ads_nome '+
         'where uuid = :id;',
         [
           LojaDados.nome,
           LojaDados.email,
           LojaDados.telefone,
           LojaDados.horario_str,
           LojaDados.slug,
           LojaDados.logradouro,
           LojaDados.uf,
           LojaDados.cidade,
           LojaDados.cep,
           LojaDados.bairro,
           LojaDados.complemento,
           LojaDados.numero,
           LojaDados.meta_pixel,
           LojaDados.g_tag,
           LojaDados.insta_str,
           LojaDados.latitude,
           LojaDados.longitude,
           LojaDados.google_ads_id,
           LojaDados.google_ads_nome,
           LojaDados.id
         ]
       );
   except on e:exception do
          raise;
   end;
end;

function TLojaModel.getDataAccount(const id: string): TJSONObject;
var
   query: TDataSet;
   gtData: TGetData;
   json, jsonHorario: TJSONObject;
   LojaDados: TLojaReturn;
begin
   gtData := TGetData.Create;
   json := TJSONObject.Create;
   try
     query:=gtData.getData(
       'select nome, email, telefone, horarios, '+
       'slug, endereco, cidade, uf, cep, numero, complemento, bairro, '+
       'meta_pixel_id, google_analytics_id, insta, meta_long_token, '+
       'meta_ads_id, meta_campanha_ativa, '+
       'google_ads_id, google_ads_nome, id_categoria '+
       'from loja where uuid = :id;',
       [id],
       true
     );
     if Assigned(query) then
     begin
       if not query.IsEmpty then
       begin
         with query do
           begin
             LojaDados.nome           := FieldByName('nome'               ).AsString;
             LojaDados.telefone       := FieldByName('telefone'           ).AsString;
             LojaDados.email          := FieldByName('email'              ).AsString;
             LojaDados.slug           := FieldByName('slug'               ).AsString;
             LojaDados.logradouro     := FieldByName('endereco'           ).AsString;
             LojaDados.cidade         := FieldByName('cidade'             ).AsString;
             LojaDados.uf             := FieldByName('uf'                 ).AsString;
             LojaDados.numero         := FieldByName('numero'             ).AsString;
             LojaDados.complemento    := FieldByName('complemento'        ).AsString;
             LojaDados.bairro         := FieldByName('bairro'             ).AsString;
             LojaDados.cep            := FieldByName('cep'                ).AsString;
             LojaDados.meta_pixel     := FieldByName('meta_pixel_id'      ).AsString;
             LojaDados.g_tag          := FieldByName('google_analytics_id').AsString;
             LojaDados.insta_str      := FieldByName('insta'              ).AsString;
             LojaDados.meta_long_token:= FieldByName('meta_long_token'    ).AsString;
             LojaDados.MetaAdsId      := FieldByName('meta_ads_id'        ).AsString;
             LojaDados.StatusCampanha := FieldByName('meta_campanha_ativa').AsString;
             LojaDados.google_ads_nome:= FieldByName('google_ads_nome'    ).AsString;
             LojaDados.google_ads_id  := FieldByName('google_ads_id'      ).AsString;
             LojaDados.id_categoria   := FieldByName('id_categoria'       ).AsInteger;
             LojaDados.horario_str    := FieldByName('horarios'           ).AsUTF8String;

             if LojaDados.horario_str <> '' then
             begin
               try
                 jsonHorario := TJSONObject(GetJSON(LojaDados.horario_str));
                 json.Add('horario', jsonHorario);
               except
                 json.Add('horario', TJSONObject.Create);
               end;
             end
             else
               json.Add('horario', TJSONObject.Create);

             json.Add('nome',                             LojaDados.nome);
             json.Add('telefone',                     LojaDados.telefone);
             json.Add('email',                           LojaDados.email);
             json.add('slug',                             LojaDados.slug);
             json.add('endereco',                   LojaDados.logradouro);
             json.add('cep',                               LojaDados.cep);
             json.add('bairro',                         LojaDados.bairro);
             json.add('cidade',                         LojaDados.cidade);
             json.add('estado',                             LojaDados.uf);
             json.add('numero',                         LojaDados.numero);
             json.Add('g_tag',                           LojaDados.g_tag);
             json.Add('meta_pixel',                 LojaDados.meta_pixel);
             json.Add('insta',                       LojaDados.insta_str);
             json.Add('complemento',               LojaDados.complemento);
             json.Add('meta_long_token',       LojaDados.meta_long_token);
             json.add('meta_ads_id',                 LojaDados.MetaAdsId);
             json.add('status_campanha',        LojaDados.StatusCampanha);
             json.add('conta_google_ads_nome', LojaDados.google_ads_nome);
             json.add('conta_google_ads_id',     LojaDados.google_ads_id);
             json.add('id_categoria',             LojaDados.id_categoria);
           end;
       end;
     end;
   finally
     Result:=json;
     query.Free;
     gtData.Free;
   end;
end;

class function TLojaModel.GetInfoStudio(const slug: string): TJSONObject;
var
   jsonres: TJSONObject;
   dataset: TDataSet;
   validade: TDateTime;
   nome, telefone: string;
begin
   result := nil;
   dataset := nil;
   try
     try
       dataset := TGetData.getData(
         'SELECT l2.NOME, l2.TELEFONE, l2.META_PIXEL_ID, l2.GOOGLE_ANALYTICS_ID, l2.INSTA, '+
         's.TITULO, s.SUBTITULO FROM LOJA l2 LEFT JOIN site s '+
         'ON (s.ID_LOJA_EX = l2.uuid) WHERE l2.SLUG = :slug;',
         [slug],
         True
       );

       if Assigned(dataset) then
       begin
         if not dataset.IsEmpty then
         begin
           Result := TJSONObject.Create;

           Result.add('nome',       dataset.FieldByName('NOME'               ).AsString);
           Result.add('telefone',   dataset.FieldByName('TELEFONE'           ).AsString);
           Result.add('titulo',     dataset.FieldByName('TITULO'             ).AsString);
           Result.add('subtitulo',  dataset.FieldByName('SUBTITULO'          ).AsString);
           Result.add('meta_pixel', dataset.FieldByName('META_PIXEL_ID'      ).AsString);
           Result.add('google_id',  dataset.FieldByName('GOOGLE_ANALYTICS_ID').AsString);
           Result.add('insta',      dataset.FieldByName('INSTA'              ).AsString);
         end;
       end;
     except
       Result.Free;
       Result := nil;
       raise;
     end;
   finally
     dataset.Free;
   end;
end;

class function TLojaModel.get_slug(slug, id: string): Boolean;
var
  dataset: TDataSet;
  jsonres: TJSONObject;
  id_loja:string;
  slug_bool: boolean;
begin
  dataset := nil;
  Result := True;
  try
    dataset := TGetData.getData(
      'select slug, uuid from loja where slug = :slug;',
      [slug],
      True
    );

    if (dataset.RecordCount > 0) and (dataset.FieldByName('uuid').AsString <> id) then
      Result := True
    else
      Result := False

  finally
    dataset.Free;
  end;
end;

class function TLojaModel.get_endereco(var json: TJSONObject): TJSONObject;
const prompt: string = 'Você é um extrator e formatador de dados de endereços '+
'brasileiros. ' + sLineBreak +
'O usuário fornecerá um única string de texto contendo um endereço '+
'de forma bagunçada. ' + sLineBreak +
'Sua tarefa é analisar o texto, corrigir erros ortográficos '+
'óbvios e extrair os componentes do endereço. '+ sLineBreak +
'Você deve verificar rigorosamente '+
'se um CEP (Código Postal de 8 dígitos) foi informado no meio do texto. '+ sLineBreak +
'Responda EXCLUSIVAMENTE com um objeto JSON válido, sem formatação Markdown, sem explicações '+
'e usando exatamente as seguintes chaves: ' + sLineBreak +
'logradouro (string, ou vazio se não encontrar) '+ sLineBreak +
'numero (string, use S/N se não houver) '+ sLineBreak +
'bairro (string, ou vazio) '+ sLineBreak +
'cidade (string, ou vazio) '+ sLineBreak +
'uf (string com 2 letras, ou vazio) '+ sLineBreak +
'cep (string formatada como XXXXX-XXX, ou deixe vazio se o usuário não tiver '+ sLineBreak +
'digitado nenhum número que pareça um CEP) '+ sLineBreak +
'cep_informado (boolean, true se encontrou o CEP no texto, false se não encontrou)';
begin
  try
     result := TJSONObject(GetJSON(TNetService.getGemini(json, prompt)));
  except
  on e:exception do
     raise;
  end;
end;

class procedure TLojaModel.UpdateMetaLongToken(id, token: string);
begin
  try
    TGetData.getData(
      'update loja set meta_long_token = :token where uuid = :id',
      [token, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateMetaAdsId(id, MetaAdsId: string);
begin
  try
    TGetData.getData(
      'update loja set META_ADS_ID = :AdsId where uuid = :id;',
      [MetaAdsId, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateMetaPixelId(id, MetaPixelId: string);
begin
  try
    TGetData.getData(
      'update loja set META_PIXEL_ID = :PixelId where uuid = :id;',
      [MetaPixelId, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateGoogleAnalyticsId(id, GoogleAnalyticsId: string
  );
begin
  try
    TGetData.getData(
      'update loja set GOOGLE_ANALYTICS_ID = :GoogleAnalyticsId where uuid = :id;',
      [GoogleAnalyticsId, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateStatusCampanhaMeta(id: string;
  StatusCampanhaMeta: Boolean);
begin
  try
    TGetData.getData(
      'update loja set META_CAMPANHA_ATIVA = :StatusCampanhaMeta where uuid = :id;',
      [StatusCampanhaMeta, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateAccounBasico(id, nome, apelido: string;
  id_categoria:integer);
begin
  try
    apelido := GerarSlug(apelido);

    TGetData.getData(
      'update loja set nome = :nome, slug = :apelido, id_categoria = :id_categoria '+
      'where uuid = :id;',
      [
        nome,
        apelido,
        id_categoria,
        id
      ]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateAccounContato(id, telefone, email,
  instagram: string);
begin
  try
    TGetData.getData(
      'update loja set telefone = :telefone, email = :email, insta = :instagram '+
      'where uuid = :id;',
      [telefone, email, instagram, id]
    );
  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateEndereco(id, cep, endereco, numero, bairro,
  cidade, estado, complemento: string);
begin
  try
    TGetData.getData(
      'update loja set cep = :cep, endereco = :endereco, '+
      'numero = :numero, bairro = :bairro, cidade = :cidade, '+
      'uf = :estado, complemento = :complemento '+
      'where uuid = :id;',
      [
        cep,
        endereco,
        numero,
        bairro,
        cidade,
        estado,
        complemento,
        id
      ]
    );
  except
    raise;
  end;
end;

class function TLojaModel.GetEnderecoCep(ACEP: string): TJSONObject;
var
  StatusCode: integer;
  LContent: string;
  LJson: TJSONObject;
begin
  Result := nil;
  try
    LContent := TNetService.get(
      'https://brasilapi.com.br/api/cep/v2/' + ACEP,
      StatusCode
    );

    if StatusCode = 200 then
      result := TJSONObject(GetJSON(LContent));

  except
    raise;
  end;
end;

class procedure TLojaModel.UpdateConfiguracoesAvancadas(id_loja, g_analytcs,
  meta_pixel_id, conta_google_ads, horario: string);
begin
  try
    TGetData.getData(
      'update loja set GOOGLE_ANALYTICS_ID = :g_analytcs, '+
      'META_PIXEL_ID = :meta_pixel_id, GOOGLE_ADS_ID = :conta_google_ads, '+
      'horarios = :horario where uuid = :id_loja;',
      [
        g_analytcs,
        meta_pixel_id,
        conta_google_ads,
        horario,
        id_loja
      ]
    );
  except
    raise;
  end;
end;


end.


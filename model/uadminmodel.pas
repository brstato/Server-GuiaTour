unit uadminmodel;

{$mode delphi}{$H+}

{
  Camada de dados da administração geral (somente vendedores administradores).

  "Vendedor administrador" = linha em VENDEDOR com ATIVO = TRUE e ADM = TRUE. Vendedor
  terceirizado fica com ADM = FALSE (padrão): loga e usa o painel normal, mas não vê a
  administração. A condição é conferida no banco a cada requisição, então tirar o ADM ou
  desativar o vendedor corta o acesso na hora, sem esperar o JWT expirar.

  Regras de mensalidade (LOJA.VALIDADE já inclui os dias de tolerância do Asaas):
    - VENCIDA   : VALIDADE < hoje (mesma regra do login e das páginas públicas)
    - POR VENCER: VALIDADE entre hoje e hoje + N dias  E  a loja NÃO tem pagamento
                  recorrente, ou seja, a assinatura mais recente (ASAAS_ASSINATURA de
                  maior ID) não existe ou não está com STATUS = 'ATIVA'
    - Loja com VALIDADE nula não entra nas listas de mensalidade (aparece como
      "sem_validade" na lista geral de lojas).

  Padrão do projeto: TGetData com SQL que começa em SELECT, nenhum CTE. NUMERIC lido com
  CAST(... AS DOUBLE PRECISION) e diferenças de data com CAST(... AS INTEGER).
}

interface

uses
  Classes, SysUtils, db, fpjson, ugetdata, uasaas;

type
  TAdminModel = class
  public
    class function VendedorAtivo(const AIdVendedor: string): Boolean;
    class function VendedorAdmin(const AIdVendedor: string): Boolean;
    class function SiteDaLoja(AIdSite: Integer; const AUuidLoja: string): Boolean;
    class function LojaDaFoto(AIdFoto: Integer): string;
    class function ListarLojas(const AIdVendedor: string): TJSONArray;
    class function ListarPontos: TJSONArray;
    class function ListarMensalidades(const AIdVendedor: string;
      ADiasAviso: Integer): TJSONObject;
  end;

implementation

const
  // Colunas e junções compartilhadas entre a lista de lojas e a de mensalidades.
  // A assinatura "atual" da loja é a de maior ID (mesma regra de TAsaasModel.UltimaAssinatura).
  SQL_LOJA_COLUNAS =
    'SELECT l.uuid, l.nome, l.slug, l.telefone, l.email, l.cidade, l.uf, l.validade, ' +
    'CAST(DATEDIFF(DAY FROM CURRENT_DATE TO l.validade) AS INTEGER) AS dias, ' +
    'c.nome AS categoria, v.nome AS vendedor, v.uuid AS vendedor_uuid, ' +
    'COALESCE(a.status, ''SEM_ASSINATURA'') AS assinatura_status, ' +
    'a.billing_type AS forma_pagamento, ' +
    'CAST(a.valor AS DOUBLE PRECISION) AS valor ';

  SQL_LOJA_ORIGEM =
    'FROM loja l ' +
    'LEFT JOIN categoria c ON c.id = l.id_categoria ' +
    'LEFT JOIN vendedor v ON v.id = l.id_vendedor ' +
    'LEFT JOIN asaas_assinatura a ON a.id = ' +
    '  (SELECT MAX(x.id) FROM asaas_assinatura x WHERE x.loja_id = l.id) ';

function DataOuNulo(AField: TField): TJSONData;
begin
  if AField.IsNull then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(DateToIso(AField.AsDateTime));
end;

// Monta o item JSON de uma loja a partir da linha atual do dataset.
// O UUID do vendedor NÃO vai para o cliente: só serve para marcar "meu" (loja do
// próprio vendedor logado), usado na tela para destacar "(você)".
function LojaParaJson(ADs: TDataSet; const AIdVendedor: string): TJSONObject;
var
  situacao: string;
begin
  if ADs.FieldByName('validade').IsNull then
    situacao := 'sem_validade'
  else if ADs.FieldByName('dias').AsInteger < 0 then
    situacao := 'vencida'
  else
    situacao := 'no_ar';

  Result := TJSONObject.Create;
  Result.Add('uuid', ADs.FieldByName('uuid').AsString);
  Result.Add('nome', ADs.FieldByName('nome').AsString);
  Result.Add('slug', ADs.FieldByName('slug').AsString);
  Result.Add('telefone', ADs.FieldByName('telefone').AsString);
  Result.Add('email', ADs.FieldByName('email').AsString);
  Result.Add('cidade', ADs.FieldByName('cidade').AsString);
  Result.Add('uf', ADs.FieldByName('uf').AsString);
  Result.Add('categoria', ADs.FieldByName('categoria').AsString);
  Result.Add('vendedor', ADs.FieldByName('vendedor').AsString);
  Result.Add('meu', (AIdVendedor <> '') and
    (ADs.FieldByName('vendedor_uuid').AsString = AIdVendedor));
  Result.Add('validade', DataOuNulo(ADs.FieldByName('validade')));
  if ADs.FieldByName('dias').IsNull then
    Result.Add('dias', TJSONNull.Create)
  else
    Result.Add('dias', ADs.FieldByName('dias').AsInteger);
  Result.Add('situacao', situacao);
  Result.Add('assinatura_status', ADs.FieldByName('assinatura_status').AsString);
  Result.Add('forma_pagamento', ADs.FieldByName('forma_pagamento').AsString);
  if ADs.FieldByName('valor').IsNull then
    Result.Add('valor', TJSONNull.Create)
  else
    Result.Add('valor', ADs.FieldByName('valor').AsFloat);
end;

// Vendedor existe e está ATIVO (VENDEDOR.ATIVO = TRUE). Usado pela cobrança, que também
// atende vendedor comum (dono da loja) e por isso não exige ADM.
class function TAdminModel.VendedorAtivo(const AIdVendedor: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if Trim(AIdVendedor) = '' then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM vendedor WHERE uuid = :uuid AND ativo = TRUE',
    [AIdVendedor], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.VendedorAdmin(const AIdVendedor: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if Trim(AIdVendedor) = '' then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM vendedor WHERE uuid = :uuid AND ativo = TRUE AND adm = TRUE',
    [AIdVendedor], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

// O SITE de id AIdSite pertence à loja AUuidLoja? (impede anexar foto no site de outra loja)
class function TAdminModel.SiteDaLoja(AIdSite: Integer; const AUuidLoja: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if (AIdSite <= 0) or (Trim(AUuidLoja) = '') then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM site WHERE id = :id AND id_loja_ex = :uuid',
    [AIdSite, AUuidLoja], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

// UUID da loja dona da foto da galeria (SITE_GALERIA.ID); '' se a foto não existe.
class function TAdminModel.LojaDaFoto(AIdFoto: Integer): string;
var
  ds: TDataSet;
begin
  Result := '';
  if AIdFoto <= 0 then Exit;

  ds := TGetData.getData(
    'SELECT s.id_loja_ex FROM site_galeria g JOIN site s ON s.id = g.id_site WHERE g.id = :id',
    [AIdFoto], True);
  try
    if not ds.IsEmpty then
      Result := ds.Fields[0].AsString;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.ListarLojas(const AIdVendedor: string): TJSONArray;
var
  ds: TDataSet;
begin
  Result := TJSONArray.Create;
  ds := nil;
  try
    try
      ds := TGetData.getData(
        SQL_LOJA_COLUNAS + SQL_LOJA_ORIGEM + 'ORDER BY l.nome',
        [], True);
      while not ds.Eof do
      begin
        Result.Add(LojaParaJson(ds, AIdVendedor));
        ds.Next;
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.ListarPontos: TJSONArray;
var
  ds: TDataSet;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;
  ds := nil;
  try
    try
      ds := TGetData.getData(
        'SELECT p.uuid, p.nome, p.slug, p.ativo, p.cidade, p.uf, ' +
        'c.nome AS categoria, v.nome AS vendedor ' +
        'FROM ponto_turistico p ' +
        'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
        'JOIN vendedor v ON v.id = p.id_vendedor ' +
        'ORDER BY p.nome',
        [], True);
      while not ds.Eof do
      begin
        item := TJSONObject.Create;
        item.Add('uuid', ds.FieldByName('uuid').AsString);
        item.Add('nome', ds.FieldByName('nome').AsString);
        item.Add('slug', ds.FieldByName('slug').AsString);
        item.Add('ativo', ds.FieldByName('ativo').AsBoolean);
        item.Add('cidade', ds.FieldByName('cidade').AsString);
        item.Add('uf', ds.FieldByName('uf').AsString);
        item.Add('categoria', ds.FieldByName('categoria').AsString);
        item.Add('vendedor', ds.FieldByName('vendedor').AsString);
        Result.Add(item);
        ds.Next;
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    ds.Free;
  end;
end;

// Devolve { "dias_aviso": N, "vencidas": [...], "por_vencer": [...] }.
// Ordenação: vencidas = as mais atrasadas primeiro; por_vencer = as mais próximas primeiro.
class function TAdminModel.ListarMensalidades(const AIdVendedor: string;
  ADiasAviso: Integer): TJSONObject;
var
  ds: TDataSet;
  vencidas, porVencer: TJSONArray;
begin
  // Faixa saneada (1..60) e injetada como inteiro: DATEADD não aceita bem parâmetro
  // de quantidade no Firebird, e um Integer não carrega nada além de dígitos.
  if ADiasAviso < 1 then ADiasAviso := 1;
  if ADiasAviso > 60 then ADiasAviso := 60;

  Result := TJSONObject.Create;
  vencidas := TJSONArray.Create;
  porVencer := TJSONArray.Create;
  Result.Add('dias_aviso', ADiasAviso);
  Result.Add('vencidas', vencidas);
  Result.Add('por_vencer', porVencer);

  ds := nil;
  try
    try
      ds := TGetData.getData(
        SQL_LOJA_COLUNAS + SQL_LOJA_ORIGEM +
        'WHERE l.validade IS NOT NULL AND (' +
        '  l.validade < CURRENT_DATE ' +
        '  OR (l.validade <= DATEADD(' + IntToStr(ADiasAviso) + ' DAY TO CURRENT_DATE) ' +
        '      AND COALESCE(a.status, '''') <> ''ATIVA'')) ' +
        'ORDER BY l.validade, l.nome',
        [], True);
      while not ds.Eof do
      begin
        if ds.FieldByName('dias').AsInteger < 0 then
          vencidas.Add(LojaParaJson(ds, AIdVendedor))
        else
          porVencer.Add(LojaParaJson(ds, AIdVendedor));
        ds.Next;
      end;
    except
      FreeAndNil(Result); // dono de vencidas e porVencer
      raise;
    end;
  finally
    ds.Free;
  end;
end;

end.

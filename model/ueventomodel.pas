unit ueventomodel;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, db, fpjson, ugetdata;

type

  { TEventoModel }

  TEventoModel = class
  public
    // Grava 1 clique. Se a loja não existir ou estiver vencida, não grava nada
    // (sem erro). pontoSlug pode ser ''. Exceções de banco sobem para o chamador.
    class procedure Registrar(const lojaSlug, pontoSlug, tipo: string);

    // Métricas do painel da loja nos últimos "dias" dias (contando hoje).
    // Devolve nil se a loja não existir. Quem chama libera o objeto.
    class function Metricas(const uuidLoja: string; dias: Integer): TJSONObject;

    // Métricas somadas de várias lojas, no mesmo formato de Metricas, mais "total_lojas" e
    // "lojas" (as 10 com mais interações). uuidVendedor = '' soma a rede inteira
    // (administrador); com um UUID, soma só as lojas desse vendedor.
    // Devolve nil se o vendedor não existir. Quem chama libera o objeto.
    class function MetricasRede(const uuidVendedor: string; dias: Integer): TJSONObject;
  end;

implementation

const
  // tipos mostrados no painel (os mesmos aceitos em POST api/v1/evento)
  TIPOS_METRICA: array[0..5] of string = ('visita', 'whats', 'rota', 'ver', 'card', 'pin');

{ TEventoModel }

class procedure TEventoModel.Registrar(const lojaSlug, pontoSlug, tipo: string);
begin
  // Parâmetros posicionais, na ordem do texto: :ponto, :tipo, :loja
  TGetData.getData(
    'INSERT INTO evento_clique (id_loja, id_ponto, tipo) ' +
    'SELECT l.id, ' +
    '       (SELECT FIRST 1 p.id FROM ponto_turistico p WHERE p.slug = :ponto), ' +
    '       CAST(:tipo AS VARCHAR(10)) ' +
    'FROM loja l ' +
    'WHERE l.slug = :loja AND l.validade >= CURRENT_DATE;',
    [pontoSlug, tipo, lojaSlug]
  );
end;

class function TEventoModel.Metricas(const uuidLoja: string; dias: Integer): TJSONObject;
var
  ds: TDataSet;
  idLoja, i: Integer;
  inicio, inicioAnterior: TDateTime;
  atual, anterior, item: TJSONObject;
  porDia, pontos: TJSONArray;
  tipo: string;
begin
  Result := nil;
  if (dias < 1) or (dias > 366) then
    dias := 30;

  // período = os últimos "dias" dias, contando hoje; o anterior tem o mesmo tamanho
  inicio := IncDay(Date, -(dias - 1));
  inicioAnterior := IncDay(inicio, -dias);

  // id interno da loja (o índice de evento_clique é por id_loja + criado_em)
  idLoja := 0;
  ds := TGetData.getData('SELECT id FROM loja WHERE uuid = :uuid', [uuidLoja], True);
  try
    if Assigned(ds) and not ds.IsEmpty then
      idLoja := ds.Fields[0].AsInteger;
  finally
    ds.Free;
  end;
  if idLoja = 0 then
    Exit;

  Result := TJSONObject.Create;
  try
    Result.Add('dias', dias);
    atual := TJSONObject.Create;
    Result.Add('atual', atual);
    anterior := TJSONObject.Create;
    Result.Add('anterior', anterior);
    porDia := TJSONArray.Create;
    Result.Add('por_dia', porDia);
    pontos := TJSONArray.Create;
    Result.Add('pontos', pontos);

    for i := Low(TIPOS_METRICA) to High(TIPOS_METRICA) do
    begin
      atual.Add(TIPOS_METRICA[i], 0);
      anterior.Add(TIPOS_METRICA[i], 0);
    end;

    // 1) total por tipo: período atual e anterior numa consulta só
    //    (parâmetros na ordem do texto: :ini1, :ini2, :id, :ini_ant)
    ds := TGetData.getData(
      'SELECT tipo, ' +
      '  CAST(SUM(CASE WHEN criado_em >= :ini1 THEN 1 ELSE 0 END) AS INTEGER) AS atual, ' +
      '  CAST(SUM(CASE WHEN criado_em <  :ini2 THEN 1 ELSE 0 END) AS INTEGER) AS anterior ' +
      'FROM evento_clique ' +
      'WHERE id_loja = :id AND criado_em >= :ini_ant ' +
      'GROUP BY tipo',
      [inicio, inicio, idLoja, inicioAnterior], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          tipo := ds.FieldByName('tipo').AsString;
          if atual.IndexOfName(tipo) >= 0 then
          begin
            atual.Integers[tipo] := ds.FieldByName('atual').AsInteger;
            anterior.Integers[tipo] := ds.FieldByName('anterior').AsInteger;
          end;
          ds.Next;
        end;
    finally
      ds.Free;
    end;

    // 2) total por dia no período atual (só dias com movimento; o painel completa os zeros)
    ds := TGetData.getData(
      'SELECT CAST(criado_em AS DATE) AS dia, CAST(COUNT(*) AS INTEGER) AS total ' +
      'FROM evento_clique ' +
      'WHERE id_loja = :id AND criado_em >= :ini ' +
      'GROUP BY CAST(criado_em AS DATE) ' +
      'ORDER BY 1',
      [idLoja, inicio], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          item := TJSONObject.Create;
          item.Add('dia', FormatDateTime('yyyy-mm-dd', ds.FieldByName('dia').AsDateTime));
          item.Add('total', ds.FieldByName('total').AsInteger);
          porDia.Add(item);
          ds.Next;
        end;
    finally
      ds.Free;
    end;

    // 3) pontos turísticos que mais trouxeram cliques para a loja
    ds := TGetData.getData(
      'SELECT FIRST 5 p.nome, p.slug, CAST(COUNT(*) AS INTEGER) AS total ' +
      'FROM evento_clique e ' +
      'JOIN ponto_turistico p ON p.id = e.id_ponto ' +
      'WHERE e.id_loja = :id AND e.criado_em >= :ini ' +
      'GROUP BY p.nome, p.slug ' +
      'ORDER BY 3 DESC',
      [idLoja, inicio], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          item := TJSONObject.Create;
          item.Add('nome', ds.FieldByName('nome').AsString);
          item.Add('slug', ds.FieldByName('slug').AsString);
          item.Add('total', ds.FieldByName('total').AsInteger);
          pontos.Add(item);
          ds.Next;
        end;
    finally
      ds.Free;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

class function TEventoModel.MetricasRede(const uuidVendedor: string; dias: Integer): TJSONObject;
var
  ds: TDataSet;
  idVendedor, i: Integer;
  inicio, inicioAnterior: TDateTime;
  escopo, tipo: string;
  atual, anterior, item: TJSONObject;
  porDia, pontos, lojas: TJSONArray;
begin
  Result := nil;
  if (dias < 1) or (dias > 366) then
    dias := 30;

  inicio := IncDay(Date, -(dias - 1));
  inicioAnterior := IncDay(inicio, -dias);

  // Escopo: só um número inteiro lido do banco entra no texto do SQL.
  escopo := '';
  if uuidVendedor <> '' then
  begin
    idVendedor := 0;
    ds := TGetData.getData('SELECT id FROM vendedor WHERE uuid = :uuid', [uuidVendedor], True);
    try
      if Assigned(ds) and not ds.IsEmpty then
        idVendedor := ds.Fields[0].AsInteger;
    finally
      ds.Free;
    end;
    if idVendedor = 0 then
      Exit;
    escopo := ' AND l.id_vendedor = ' + IntToStr(idVendedor);
  end;

  Result := TJSONObject.Create;
  try
    Result.Add('dias', dias);
    atual := TJSONObject.Create;
    Result.Add('atual', atual);
    anterior := TJSONObject.Create;
    Result.Add('anterior', anterior);
    porDia := TJSONArray.Create;
    Result.Add('por_dia', porDia);
    pontos := TJSONArray.Create;
    Result.Add('pontos', pontos);
    lojas := TJSONArray.Create;
    Result.Add('lojas', lojas);
    Result.Add('total_lojas', 0);

    for i := Low(TIPOS_METRICA) to High(TIPOS_METRICA) do
    begin
      atual.Add(TIPOS_METRICA[i], 0);
      anterior.Add(TIPOS_METRICA[i], 0);
    end;

    // 0) quantas lojas entram na soma
    ds := TGetData.getData('SELECT CAST(COUNT(*) AS INTEGER) FROM loja l WHERE 1 = 1' + escopo, [], True);
    try
      if Assigned(ds) and not ds.IsEmpty then
        Result.Integers['total_lojas'] := ds.Fields[0].AsInteger;
    finally
      ds.Free;
    end;

    // 1) total por tipo: período atual e anterior (parâmetros na ordem do texto)
    ds := TGetData.getData(
      'SELECT e.tipo, ' +
      '  CAST(SUM(CASE WHEN e.criado_em >= :ini1 THEN 1 ELSE 0 END) AS INTEGER) AS atual, ' +
      '  CAST(SUM(CASE WHEN e.criado_em <  :ini2 THEN 1 ELSE 0 END) AS INTEGER) AS anterior ' +
      'FROM evento_clique e JOIN loja l ON l.id = e.id_loja ' +
      'WHERE e.criado_em >= :ini_ant' + escopo + ' ' +
      'GROUP BY e.tipo',
      [inicio, inicio, inicioAnterior], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          tipo := ds.FieldByName('tipo').AsString;
          if atual.IndexOfName(tipo) >= 0 then
          begin
            atual.Integers[tipo] := ds.FieldByName('atual').AsInteger;
            anterior.Integers[tipo] := ds.FieldByName('anterior').AsInteger;
          end;
          ds.Next;
        end;
    finally
      ds.Free;
    end;

    // 2) total por dia no período atual (só dias com movimento; o painel completa os zeros)
    ds := TGetData.getData(
      'SELECT CAST(e.criado_em AS DATE) AS dia, CAST(COUNT(*) AS INTEGER) AS total ' +
      'FROM evento_clique e JOIN loja l ON l.id = e.id_loja ' +
      'WHERE e.criado_em >= :ini' + escopo + ' ' +
      'GROUP BY CAST(e.criado_em AS DATE) ' +
      'ORDER BY 1',
      [inicio], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          item := TJSONObject.Create;
          item.Add('dia', FormatDateTime('yyyy-mm-dd', ds.FieldByName('dia').AsDateTime));
          item.Add('total', ds.FieldByName('total').AsInteger);
          porDia.Add(item);
          ds.Next;
        end;
    finally
      ds.Free;
    end;

    // 3) pontos turísticos que mais trouxeram cliques para essas lojas
    ds := TGetData.getData(
      'SELECT FIRST 5 p.nome, p.slug, CAST(COUNT(*) AS INTEGER) AS total ' +
      'FROM evento_clique e ' +
      'JOIN loja l ON l.id = e.id_loja ' +
      'JOIN ponto_turistico p ON p.id = e.id_ponto ' +
      'WHERE e.criado_em >= :ini' + escopo + ' ' +
      'GROUP BY p.nome, p.slug ' +
      'ORDER BY 3 DESC',
      [inicio], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          item := TJSONObject.Create;
          item.Add('nome', ds.FieldByName('nome').AsString);
          item.Add('slug', ds.FieldByName('slug').AsString);
          item.Add('total', ds.FieldByName('total').AsInteger);
          pontos.Add(item);
          ds.Next;
        end;
    finally
      ds.Free;
    end;

    // 4) as 10 lojas com mais interações no período
    ds := TGetData.getData(
      'SELECT FIRST 10 l.uuid, l.nome, l.slug, ' +
      '  CAST(COUNT(*) AS INTEGER) AS total, ' +
      '  CAST(SUM(CASE WHEN e.tipo = ''visita'' THEN 1 ELSE 0 END) AS INTEGER) AS visitas, ' +
      '  CAST(SUM(CASE WHEN e.tipo = ''whats'' THEN 1 ELSE 0 END) AS INTEGER) AS whats, ' +
      '  CAST(SUM(CASE WHEN e.tipo = ''rota'' THEN 1 ELSE 0 END) AS INTEGER) AS rotas ' +
      'FROM evento_clique e JOIN loja l ON l.id = e.id_loja ' +
      'WHERE e.criado_em >= :ini' + escopo + ' ' +
      'GROUP BY l.uuid, l.nome, l.slug ' +
      'ORDER BY 4 DESC, l.nome',
      [inicio], True);
    try
      if Assigned(ds) then
        while not ds.EOF do
        begin
          item := TJSONObject.Create;
          item.Add('uuid', ds.FieldByName('uuid').AsString);
          item.Add('nome', ds.FieldByName('nome').AsString);
          item.Add('slug', ds.FieldByName('slug').AsString);
          item.Add('total', ds.FieldByName('total').AsInteger);
          item.Add('visitas', ds.FieldByName('visitas').AsInteger);
          item.Add('whats', ds.FieldByName('whats').AsInteger);
          item.Add('rotas', ds.FieldByName('rotas').AsInteger);
          lojas.Add(item);
          ds.Next;
        end;
    finally
      ds.Free;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

end.

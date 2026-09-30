unit ubuscamodel;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, fpjson, db, ugetdata, uguiatourutils;

const
  // Comparação sem acento e sem diferenciar maiúsculas (Firebird 3+, charset UTF8).
  // Se a query der erro de collation, troque por '' (fica só case-insensitive).
  COLLATE_BUSCA = ' COLLATE UNICODE_CI_AI';

type

  { TBuscaModel }

  TBuscaModel = class
  public
    // Retorna {"pontos":[...], "cidades":[...]}. O chamador é dono do objeto.
    // Termo com menos de 2 caracteres devolve as duas listas vazias.
    class function Buscar(const Termo: string; Limite: Integer = 8): TJSONObject;
  end;

implementation

{ TBuscaModel }

class function TBuscaModel.Buscar(const Termo: string; Limite: Integer): TJSONObject;
var
  dsPontos, dsCidades: TDataSet;
  arrPontos, arrCidades: TJSONArray;
  item: TJSONObject;
begin
  Result := TJSONObject.Create;
  arrPontos := TJSONArray.Create;
  Result.Add('pontos', arrPontos);      // Result passa a ser dono do array
  arrCidades := TJSONArray.Create;
  Result.Add('cidades', arrCidades);

  if Utf8Len(Termo) < 2 then Exit;

  dsPontos := nil;
  dsCidades := nil;
  try
    try
      // Parâmetros posicionais: :q1, :q2, :limite
      dsPontos := TGetData.getData(
        'SELECT p.nome, p.slug, p.cidade, p.uf, p.capa, c.nome AS categoria ' +
        'FROM ponto_turistico p ' +
        'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
        'WHERE p.ativo = TRUE AND (' +
        '  p.nome' + COLLATE_BUSCA + ' CONTAINING :q1 OR ' +
        '  p.cidade' + COLLATE_BUSCA + ' CONTAINING :q2) ' +
        'ORDER BY p.nome ' +
        'ROWS :limite;',
        [Termo, Termo, Limite],
        True
      );

      while not dsPontos.EOF do
      begin
        item := TJSONObject.Create;
        item.Add('nome',      dsPontos.FieldByName('nome'     ).AsString);
        item.Add('slug',      dsPontos.FieldByName('slug'     ).AsString);
        item.Add('cidade',    dsPontos.FieldByName('cidade'   ).AsString);
        item.Add('uf',        dsPontos.FieldByName('uf'       ).AsString);
        item.Add('capa',      dsPontos.FieldByName('capa'     ).AsString);
        item.Add('categoria', dsPontos.FieldByName('categoria').AsString);
        arrPontos.Add(item);
        dsPontos.Next;
      end;

      // Parâmetro posicional: :q
      dsCidades := TGetData.getData(
        'SELECT p.cidade, p.uf, COUNT(*) AS qtd, ' +
        '       AVG(p.latitude) AS lat, AVG(p.longitude) AS lng ' +
        'FROM ponto_turistico p ' +
        'WHERE p.ativo = TRUE AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL ' +
        '  AND p.cidade' + COLLATE_BUSCA + ' CONTAINING :q ' +
        'GROUP BY p.cidade, p.uf ' +
        'ORDER BY 3 DESC ' +
        'ROWS 5;',
        [Termo],
        True
      );

      while not dsCidades.EOF do
      begin
        item := TJSONObject.Create;
        item.Add('cidade',    dsCidades.FieldByName('cidade').AsString);
        item.Add('uf',        dsCidades.FieldByName('uf'    ).AsString);
        item.Add('qtd',       dsCidades.FieldByName('qtd'   ).AsInteger);
        item.Add('latitude',  dsCidades.FieldByName('lat'   ).AsFloat);
        item.Add('longitude', dsCidades.FieldByName('lng'   ).AsFloat);
        arrCidades.Add(item);
        dsCidades.Next;
      end;
    except
      FreeAndNil(Result);               // libera Result e os dois arrays
      raise;
    end;
  finally
    dsPontos.Free;
    dsCidades.Free;
  end;
end;

end.

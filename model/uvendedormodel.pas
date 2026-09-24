unit uvendedormodel;

interface

uses
  Classes, SysUtils, fpjson, ugetdata, db;

type
  TVendedorModel = class
  public
    class function DonoDaLoja(idVendedor, uuidLoja: string): Boolean;
    class function ListarComercios(idVendedor: string): TJSONArray;
    class function CriarComercio(idVendedor, nome, telefone, email,
            slug: string; idCategoria: integer): string;
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

class function TVendedorModel.CriarComercio(idVendedor, nome, telefone,
        email, slug: string; idCategoria: integer): string;
var
  dataset: TDataSet;
  uuid: TGuid;
  uuidString: string;
begin
    try
      try
        CreateGUID(uuid);
        uuidString := StringReplace(StringReplace(GUIDToString(uuid),
                        '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);

        dataset := TGetData.getData(
            'insert into loja(nome, telefone, email, slug, uuid, id_categoria, ' +
            'validade, id_vendedor) ' +
            'values(:nome, :telefone, :email, :slug, :uuid, :idCategoria, ' +
            ':validade, (select id from vendedor where uuid = :idVendedor)) ' +
            'returning uuid;',
            [
                nome, 
                telefone, 
                email, 
                slug, 
                uuidString, 
                idCategoria,
                StrToDate(FormatDateTime('dd/mm/yyyy', IncMonth(Now, 1))), idVendedor
            ],
            True
        );

        Result := dataset.FieldByName('uuid').AsString;
        RegistrarLog(idVendedor, Result, 'criou_loja');        
      except
        raise;
      end;
    finally
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

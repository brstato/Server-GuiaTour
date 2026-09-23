unit ugetdata;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  ZDataset,
  udata,
  db,
  ZConnection,
  MemDs;

type

  { TGetData }

  TGetData = class(TObject)
    public
      class function getData(const ASqlText: string; AParams: Array of Variant;
        AReturn_data:boolean = False): TMemDataset;
  end;


implementation

{ TGetData }

class function tgetdata.getdata(const asqltext: string;
  aparams: array of variant; areturn_data: boolean = False): TMemDataset;
var
   query: TZQuery;
   i: integer;
   error: string;
   DM: TDataModule1;
   isSelect: Boolean;
begin
  isSelect := Pos('SELECT', UpperCase(Trim(ASqlText))) = 1;
  Result := nil;
  DM := TDataModule1.Create(nil);
  query := TZQuery.Create(nil);

  try
    try
      query.Connection:= DM.ZConnection1;

      query.sql.Clear;
      query.sql.Text := ASqlText;
      query.Prepare;

      for i := Low(AParams) to High(AParams) do
      begin
        query.Params[i].Value:=AParams[i];
      end;

      if AReturn_data then
      begin
        Result := TMemDataset.Create(nil);

        query.Open;
        Result.FieldDefs.Assign(query.FieldDefs);
        Result.CreateTable;
        Result.Open;
        query.First;
        i := 0;
        while not query.eof do
        begin
          Result.Append;
          For i := 0 to query.FieldCount -1 do
            Result.Fields[i].Value := query.Fields[i].Value;
            Result.Post;
          query.next;
        end;
        Result.First;
        if not isSelect then
        begin
          query.Close;
          TZConnection(query.Connection).Commit;
        end;
      end
      else
      begin
        query.ExecSQL;
        TZConnection(query.Connection).Commit;
      end;

    finally
      if query.Active then
          query.Close;
      if DM.ZConnection1.Connected and DM.ZConnection1.InTransaction then
          DM.ZConnection1.Commit;

      DM.Free;
      query.free;
    end;
  except on e:Exception do
  begin
    error := e.Message;
    if Assigned(Result) then Result.Free;
    Result := nil;
    raise;
  end;
end;
end;

end.


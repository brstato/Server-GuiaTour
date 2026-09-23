unit uNotificacaoThread;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ugetdata, uNetService, db;

type
  TNotificacaoThread = class(TThread)
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

implementation

constructor TNotificacaoThread.Create;
begin
  inherited Create(False); // Inicia a thread imediatamente
  FreeOnTerminate := True; // Libera a memória automaticamente ao finalizar
end;

procedure TNotificacaoThread.Execute;
var
  ds: TDataSet;
  id_despesa, i: Integer;
  id_loja, descricao: string;
  hora_ini, hora_fim:TTime;
begin
  hora_ini := StrToTime('09:00:00');
  hora_fim := StrToTime('23:00:00');
  while not Terminated do
  begin
    try
      // 1. Busca as despesas de hoje não notificadas[cite: 3]
      ds := TGetData.getData(
        'SELECT id, id_loja_ex, descricao, data_vencimento FROM despesas '+
        'WHERE data_vencimento <= CURRENT_DATE '+
        'AND status <> ''PAGO'' '+
        'and (data_notificacao is null or '+
        'cast(data_notificacao as date) < current_date);',
        [],
        True
      );

      if Assigned(ds) and (ds.RecordCount > 0) and
      (Time >= hora_ini) and (time <= hora_fim) then
      begin
        ds.First;
        while not ds.eof do
        begin
          try
            id_loja   := ds.FieldByName('id_loja_ex').AsString;
            descricao := ds.FieldByName('descricao' ).AsString;
            id_despesa:= ds.FieldByName('id'        ).AsInteger;

            TNetService.EnviarPushOneSignal(
              id_loja,
              'Vencimento Hoje',
              'Lembrete: Você tem uma despesa vencendo hoje: ' + descricao,
              ''
            );

            TGetData.getData(
              'UPDATE despesas SET data_notificacao = CURRENT_TIMESTAMP '+
              'WHERE id = :id_despesa;',
              [id_despesa]
            );

            //Sleep(1000);

          finally
            ds.Free; // Libera o dataset da memória[cite: 3]
          end;
        end;
      end;

    except
      on E: Exception do
      begin
        // Grave E.Message em um log de texto aqui, se necessário.
        WriteLn('Erro em TNotificacaoDespesaThread: '+ e.Message);
      end;
    end;

    // 4. Pausa de 1 hora (3600 segundos) entre as verificações.
    // O loop permite que o servidor Horse seja fechado imediatamente sem travar.
    for i := 1 to 3600 do
    begin
      if Terminated then Break;
      Sleep(1000);
    end;
  end;
end;

end.

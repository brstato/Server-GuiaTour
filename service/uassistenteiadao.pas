unit uAssistenteIaDAO;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, uAssistenteIaModel, ugetdata, db;

type
  { TMensagemDAO: Responsável pela persistência do histórico no Firebird 5 }
  TMensagemDAO = class
  public
    { Insere uma nova mensagem (user ou assistant) no banco }
    class procedure Inserir(AMsg: TAssistantMessage);

    { Busca as últimas N mensagens para servir de contexto para a IA }
    class function ObterContexto(const AInstance, AWhatsAppId: string; ALimite: Integer = 10): TDataSet;
    class function BotEstaAtivo(const AInstanciaId, AWhatsAppId: string): Boolean;
    class procedure DesativarBotParaContato(const AInstanciaId, AWhatsAppId: string);
    class procedure AtivarBotParaContato(const AInstanciaId, AWhatsAppId: string);
  end;

implementation

{ TMensagemDAO }

class function TMensagemDAO.BotEstaAtivo(const AInstanciaId, AWhatsAppId: string): Boolean;
var
  dataset: TDataSet;
begin
  // Por padrão, se o cliente é novo e não tem registro, o bot atende (True)
  Result := True; 
  try
    dataset := TGetData.getData(
      'SELECT BOT_ATIVO FROM CONTATOS_STATUS ' +
      'WHERE INSTANCE_ID = :Instancia AND WHATSAPP_ID = :Telefone;',
      [AInstanciaId, AWhatsAppId],
      True // True para retornar o dataset
    );
    
    if Assigned(dataset) and not dataset.IsEmpty then
      Result := (dataset.FieldByName('BOT_ATIVO').AsInteger = 1)
    else
      Result := True; // Se não encontrar, assumir que bot está ativo
  except
    Result := True; // Em caso de erro, assumir que bot está ativo
  end;
end;

class procedure TMensagemDAO.DesativarBotParaContato(const AInstanciaId,
  AWhatsAppId: string);
begin
  TGetData.getData(
    'UPDATE OR INSERT INTO CONTATOS_STATUS (INSTANCE_ID, WHATSAPP_ID, BOT_ATIVO) ' +
    'VALUES (:Instancia, :Telefone, 0) MATCHING (INSTANCE_ID, WHATSAPP_ID);',
    [AInstanciaId, AWhatsAppId]
  );
end;

class procedure TMensagemDAO.AtivarBotParaContato(const AInstanciaId,
  AWhatsAppId: string);
begin
  TGetData.getData(
    'UPDATE OR INSERT INTO CONTATOS_STATUS (INSTANCE_ID, WHATSAPP_ID, BOT_ATIVO) ' +
    'VALUES (:Instancia, :Telefone, 1) MATCHING (INSTANCE_ID, WHATSAPP_ID);',
    [AInstanciaId, AWhatsAppId]
  );
end;

class procedure TMensagemDAO.Inserir(AMsg: TAssistantMessage);
begin
  {
    Utiliza o TGetData que você já possui.
    O Firebird 5 cuidará do ID (Identity) e do TIMESTAMP (Default)
  }
  TGetData.getData(
    'INSERT INTO MESAGES (INSTANCE_ID, WHATSAPP_ID, "ROLE", CONTENT, '+
    'EXEMPLO_MENSAGEM) VALUES (:inst, '+
    ':jid, :role, :content, :vexemplo);',
    [
      AMsg.InstanciaId,
      AMsg.WhatsAppId,
      AMsg.Role,
      AMsg.Content,
      AMsg.ExemploMensagem
    ],
    False // False para ExecSQL puro
  );
end;

class function TMensagemDAO.ObterContexto(const AInstance, AWhatsAppId: string; ALimite: Integer): TDataSet;
begin
  {
    Busca as mensagens mais recentes primeiro para montar o histórico.
    É vital filtrar por INSTANCIA_ID para manter o multi-tenant do Inkers seguro.
  }
  Result := TGetData.getData(
    'SELECT FIRST :limite "ROLE", CONTENT ' +
    'FROM MESAGES ' +
    'WHERE INSTANCE_ID = :inst AND WHATSAPP_ID = :jid ' +
    'ORDER BY ID DESC', // Assume-se que ID maior é mais recente
    [
      ALimite,
      AInstance,
      AWhatsAppId
    ],
    True // True para retornar o dataset
  );
end;

end.

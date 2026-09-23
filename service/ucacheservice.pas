unit ucacheservice;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections,
  syncobjs;

type
  TConfigLoja = record
    id             : integer;
    tempo_sessao   : integer;
    NomeAssistente : string;
    UUID           : string;
    ExemploMensagem: string;
    AssistenteAtivo: boolean;
    ValorMinimo    : double;
    ValorSessao    : double;
    ValorHora      : double;
  end;

  { TCacheService }

  TCacheService = class
    private
      class var FCache: TDictionary<string, TConfigLoja>;
      class var Flock: TCriticalSection;
      class constructor create;
      class destructor destroy;
    public
      class procedure AtualizarCache;
      class function GetConfig(AInstance: string; out AConfig: TCOnfigLoja): boolean;
      class procedure Remover(const AInstanceUUID: string);
      class procedure AtualizarInstancia(const AInstanceUUID: string);
  end;

implementation

uses
  fpjson, udata, ugetdata, db;

{ TCacheService }

class constructor TCacheService.create;
begin
  FCache := TDictionary<string, TConfigLoja>.Create;
  FLock := TCriticalSection.Create;
end;

class destructor TCacheService.destroy;
begin
  FCache.Free;
  FLock.Free;
end;

class procedure TCacheService.AtualizarCache;
var
  dataset: TDataSet;
  config: TConfigLoja;
  zapInstance: string;
begin
  Flock.Enter;
  try
    FCache.Clear;

    dataset := TGetData.getData(
      'SELECT ID, UUID, ZAP_INSTANCE, NOME_ASSISTENTE, ASSISTENTE_IA, VALOR_MINIMO, '+
      'VALOR_HORA, VALOR_SESSAO, EXEMPLO_MENSAGEM, DURACAO_SESSAO FROM LOJA WHERE ZAP_INSTANCE IS NOT NULL',
      [],
      True
    );

    // Protege o dataset para garantir que será liberado
    try
      if Assigned(dataset) then
      begin
        dataset.First;
        while not dataset.Eof do
        begin
          config.id              := dataset.FieldByName('id'              ).AsInteger;
          config.UUID            := dataset.FieldByName('UUID'            ).AsString;
          config.NomeAssistente  := dataset.FieldByName('NOME_ASSISTENTE' ).AsString;
          config.AssistenteAtivo := dataset.FieldByName('ASSISTENTE_IA'   ).AsBoolean;
          config.ValorMinimo     := dataset.FieldByName('VALOR_MINIMO'    ).AsFloat;
          config.ValorHora       := dataset.FieldByName('VALOR_HORA'      ).AsFloat;
          config.ValorSessao     := dataset.FieldByName('VALOR_SESSAO'    ).AsFloat;
          config.ExemploMensagem := dataset.FieldByName('EXEMPLO_MENSAGEM').AsString;
          config.tempo_sessao    := dataset.FieldByName('DURACAO_SESSAO'  ).AsInteger;

          zapInstance := dataset.FieldByName('ZAP_INSTANCE').AsString;

          if Trim(zapInstance) <> '' then
             FCache.AddOrSetValue(zapInstance, config);

          dataset.Next;
        end;
      end;
    finally
      if Assigned(dataset) then
        dataset.Free;
    end;

  finally
    Flock.Leave;
  end;
end;

class function TCacheService.GetConfig(AInstance: string; out
  AConfig: TCOnfigLoja): boolean;
begin
  Flock.Enter;
  try
    Result := FCache.TryGetValue(AInstance, AConfig);
  finally
    Flock.Leave;
  end;
end;

class procedure TCacheService.Remover(const AInstanceUUID: string);
begin
  Flock.Enter;
  try
    if FCache.ContainsKey(AInstanceUUID) then
      FCache.Remove(AInstanceUUID);
  finally
    Flock.Leave;
  end;
end;

class procedure TCacheService.AtualizarInstancia(const AInstanceUUID: string);
var
  dataset: TDataSet;
  config: TConfigLoja;
begin
  // Busca apenas a loja que sofreu alteração no painel
  dataset := TGetData.getData(
    'SELECT ID, UUID, ZAP_INSTANCE, NOME_ASSISTENTE, ASSISTENTE_IA, VALOR_MINIMO, '+
    'VALOR_HORA, VALOR_SESSAO, EXEMPLO_MENSAGEM, DURACAO_SESSAO FROM LOJA WHERE ZAP_INSTANCE = :inst',
    [AInstanceUUID],
    True
  );

  try
    if Assigned(dataset) and (not dataset.IsEmpty) then
    begin
      config.id              := dataset.FieldByName('id'              ).AsInteger;
      config.UUID            := dataset.FieldByName('UUID'            ).AsString;
      config.NomeAssistente  := dataset.FieldByName('NOME_ASSISTENTE' ).AsString;
      config.AssistenteAtivo := dataset.FieldByName('ASSISTENTE_IA'   ).AsBoolean;
      config.ValorMinimo     := dataset.FieldByName('VALOR_MINIMO'    ).AsFloat;
      config.ValorHora       := dataset.FieldByName('VALOR_HORA'      ).AsFloat;
      config.ValorSessao     := dataset.FieldByName('VALOR_SESSAO'    ).AsFloat;
      config.ExemploMensagem := dataset.FieldByName('EXEMPLO_MENSAGEM').AsString;
      config.tempo_sessao    := dataset.FieldByName('DURACAO_SESSAO'  ).AsInteger;

      // Bloqueia o dicionário rapidinho apenas para atualizar essa chave específica
      Flock.Enter;
      try
        FCache.AddOrSetValue(AInstanceUUID, config);
      finally
        Flock.Leave;
      end;
    end
    else
    begin
      // Se não achou no banco, remove do cache por segurança
      Remover(AInstanceUUID);
    end;
  finally
    if Assigned(dataset) then
      dataset.Free;
  end;
end;

end.

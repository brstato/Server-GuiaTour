unit uratelimit;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Generics.Collections;

type

  { TDedupe }

  // Deduplicação em memória: impede o mesmo evento repetido dentro de uma janela.
  TDedupe = class
  public
    // True = pode registrar; False = repetido dentro da janela (em ms).
    class function Permitir(const Chave: string; JanelaMs: QWord): Boolean;
  end;

implementation

const
  LIMPAR_ACIMA_DE = 5000;    // começa a remover as chaves vencidas
  MAXIMO_CHAVES   = 20000;   // acima disso, chave nova é recusada

var
  Lock: TCriticalSection;
  Vistos: TDictionary<string, QWord>;   // chave -> momento em que a chave vence
  ProximaLimpeza: QWord = 0;

procedure RemoverVencidas(agora: QWord);
var
  chaves: TArray<string>;
  k: string;
begin
  chaves := Vistos.Keys.ToArray;
  for k in chaves do
    if Vistos[k] <= agora then
      Vistos.Remove(k);
end;

class function TDedupe.Permitir(const Chave: string; JanelaMs: QWord): Boolean;
var
  agora, vence: QWord;
begin
  Result := True;
  agora := GetTickCount64;
  Lock.Enter;
  try
    if Vistos.TryGetValue(Chave, vence) and (agora < vence) then
    begin
      Result := False;
      Exit;
    end;

    // Antes: Vistos.Clear apagava tudo e liberava quem estava bloqueado.
    // Agora: tira só as vencidas, no máximo uma vez por segundo.
    if (Vistos.Count > LIMPAR_ACIMA_DE) and (agora >= ProximaLimpeza) then
    begin
      RemoverVencidas(agora);
      ProximaLimpeza := agora + 1000;
    end;

    // Enxurrada de chaves novas: recusa até as antigas vencerem
    if (Vistos.Count >= MAXIMO_CHAVES) and not Vistos.ContainsKey(Chave) then
    begin
      Result := False;
      Exit;
    end;

    Vistos.AddOrSetValue(Chave, agora + JanelaMs);
  finally
    Lock.Leave;
  end;
end;

initialization
  Lock   := TCriticalSection.Create;
  Vistos := TDictionary<string, QWord>.Create;

finalization
  Vistos.Free;
  Lock.Free;

end.

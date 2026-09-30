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

var
  Lock: TCriticalSection;
  Vistos: TDictionary<string, QWord>;

class function TDedupe.Permitir(const Chave: string; JanelaMs: QWord): Boolean;
var
  agora, ultimo: QWord;
begin
  Result := True;
  agora := GetTickCount64;
  Lock.Enter;
  try
    if Vistos.TryGetValue(Chave, ultimo) and (agora - ultimo < JanelaMs) then
    begin
      Result := False;
      Exit;
    end;
    if Vistos.Count > 5000 then Vistos.Clear;
    Vistos.AddOrSetValue(Chave, agora);
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

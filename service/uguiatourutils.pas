unit uguiatourutils;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math;

// Slug: só a-z, A-Z, 0-9 e hífen, até 100 caracteres (tamanho das colunas SLUG).
function SlugValido(const S: string): Boolean;

// Conta caracteres UTF-8 (não bytes).
function Utf8Len(const S: string): Integer;

// Corta em no máximo MaxChars caracteres UTF-8, sem partir um caractere no meio.
function Utf8Corta(const S: string; MaxChars: Integer): string;

// Termo de busca: remove caracteres de controle, Trim e limita a 60 caracteres.
function LimparTermo(const S: string): string;

// True se o User-Agent for vazio ou de robô/prévia de link.
function EhBot(const UserAgent: string): Boolean;

// Caixa (bounding box) em torno de um ponto, para pré-filtrar por lat/lng.
procedure CalcularCaixa(Lat, Lng, RaioKm: Double;
  out LatMin, LatMax, LngMin, LngMax: Double);

// Escapa texto para HTML (texto e atributos).
function HtmlEsc(const S: string): string;

// JSON para dentro de <script type="application/json|ld+json">: troca "<" por \u003c.
function JsonParaScript(const Json: string): string;

implementation

function SlugValido(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (S = '') or (Length(S) > 100) then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-']) then Exit;
  Result := True;
end;

function Utf8Len(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if (Ord(S[i]) and $C0) <> $80 then Inc(Result);
end;

function Utf8Corta(const S: string; MaxChars: Integer): string;
var
  i, n: Integer;
begin
  n := 0;
  for i := 1 to Length(S) do
  begin
    if (Ord(S[i]) and $C0) <> $80 then
    begin
      Inc(n);
      if n > MaxChars then
      begin
        Result := Copy(S, 1, i - 1);
        Exit;
      end;
    end;
  end;
  Result := S;
end;

function LimparTermo(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] >= #32 then Result := Result + S[i]
    else Result := Result + ' ';
  Result := Utf8Corta(Trim(Result), 60);
end;

function EhBot(const UserAgent: string): Boolean;
var
  ua: string;
begin
  ua := LowerCase(UserAgent);
  Result := (ua = '') or (Pos('bot', ua) > 0) or (Pos('spider', ua) > 0) or
            (Pos('crawl', ua) > 0) or (Pos('headless', ua) > 0) or
            (Pos('preview', ua) > 0);
end;

procedure CalcularCaixa(Lat, Lng, RaioKm: Double;
  out LatMin, LatMax, LngMin, LngMax: Double);
const
  KM_POR_GRAU = 111.32;
var
  dLat, dLng, cosLat: Double;
begin
  dLat   := RaioKm / KM_POR_GRAU;
  cosLat := Cos(DegToRad(Lat));
  if cosLat < 0.01 then cosLat := 0.01;
  dLng   := RaioKm / (KM_POR_GRAU * cosLat);

  LatMin := Lat - dLat;  LatMax := Lat + dLat;
  LngMin := Lng - dLng;  LngMax := Lng + dLng;
end;

function HtmlEsc(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '&',  '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result, '<',  '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '>',  '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '"',  '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;',  [rfReplaceAll]);
end;

function JsonParaScript(const Json: string): string;
begin
  Result := StringReplace(Json, '<', '\u003c', [rfReplaceAll]);
end;

end.

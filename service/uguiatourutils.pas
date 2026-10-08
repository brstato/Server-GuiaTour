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

// Escapa texto para HTML (texto e atributos). Também escapa { e } (motor {{VAR}}).
function HtmlEsc(const S: string): string;

// Escapa texto para dentro de uma string JavaScript/JSON ('...' ou "...") num <script>.
function JsEsc(const S: string): string;

// Só os dígitos de S (telefone para href do WhatsApp e JSON-LD).
function SoDigitos(const S: string): string;

// ID do Meta Pixel: só dígitos (5 a 20). Formato inválido -> ''.
function MetaPixelSeguro(const S: string): string;

// ID do Google (G-, GT-, AW-, UA- + letras/dígitos/hífen). Formato inválido -> ''.
function GoogleTagSeguro(const S: string): string;

// JSON para dentro de <script type="application/json|ld+json">: troca "<" por \u003c.
function JsonParaScript(const Json: string): string;

// URL de vídeo: vazio = válido (limpa o campo). Senão, só https:// com host
// do YouTube, até 1000 caracteres (tamanho da coluna URL_VIDEO), sem
// espaços, aspas, < > \ ` { } nem caracteres fora do ASCII.
function UrlVideoValida(const S: string): Boolean;

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
  // chaves também: o motor de template usa {{VAR}} e apaga o que estiver entre {{ e }}
  Result := StringReplace(Result, '{',  '&#123;', [rfReplaceAll]);
  Result := StringReplace(Result, '}',  '&#125;', [rfReplaceAll]);
end;

function JsEsc(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  // #92 = barra invertida (escrita assim de propósito: não troque por outra forma)
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      #92:  Result := Result + #92#92;
      '"':  Result := Result + #92'"';
      '''': Result := Result + #92'u0027';
      '<':  Result := Result + #92'u003c';
      '>':  Result := Result + #92'u003e';
      '&':  Result := Result + #92'u0026';
      '{':  Result := Result + #92'u007b';
      '}':  Result := Result + #92'u007d';
      #10:  Result := Result + #92'n';
      #13:  Result := Result + #92'r';
      #9:   Result := Result + #92't';
    else
      if Ord(c) >= 32 then Result := Result + c;
    end;
  end;
end;

function SoDigitos(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['0'..'9'] then Result := Result + S[i];
end;

function MetaPixelSeguro(const S: string): string;
var
  i: Integer;
  t: string;
begin
  Result := '';
  t := Trim(S);
  if (Length(t) < 5) or (Length(t) > 20) then Exit;
  for i := 1 to Length(t) do
    if not (t[i] in ['0'..'9']) then Exit;
  Result := t;
end;

function GoogleTagSeguro(const S: string): string;
var
  i: Integer;
  t: string;
begin
  Result := '';
  t := UpperCase(Trim(S));
  if (Length(t) < 4) or (Length(t) > 30) then Exit;
  if not ((Copy(t, 1, 2) = 'G-') or (Copy(t, 1, 3) = 'GT-') or
          (Copy(t, 1, 3) = 'AW-') or (Copy(t, 1, 3) = 'UA-')) then Exit;
  for i := 1 to Length(t) do
    if not (t[i] in ['A'..'Z', '0'..'9', '-']) then Exit;
  Result := t;
end;

function JsonParaScript(const Json: string): string;
begin
  Result := StringReplace(Json, '<', '\u003c', [rfReplaceAll]);
end;

function UrlVideoValida(const S: string): Boolean;
const
  HOSTS_VIDEO: array[0..3] of string = (
    'youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'
  );
var
  i, fim: Integer;
  resto, host: string;
begin
  Result := False;
  if S = '' then Exit(True);
  if Length(S) > 1000 then Exit;

  // { e } também ficam de fora: o motor de template usa {{VAR}}
  for i := 1 to Length(S) do
    if (Ord(S[i]) <= 32) or (Ord(S[i]) > 126) or
       (S[i] in ['"', '''', '<', '>', '\', '`', '{', '}']) then Exit;

  if LowerCase(Copy(S, 1, 8)) <> 'https://' then Exit;

  resto := Copy(S, 9, MaxInt);
  fim := Length(resto) + 1;
  for i := 1 to Length(resto) do
    if resto[i] in ['/', '?', '#'] then
    begin
      fim := i;
      Break;
    end;

  host := LowerCase(Copy(resto, 1, fim - 1));
  // sem usuário@host e sem porta
  if (host = '') or (Pos('@', host) > 0) or (Pos(':', host) > 0) then Exit;

  for i := Low(HOSTS_VIDEO) to High(HOSTS_VIDEO) do
    if host = HOSTS_VIDEO[i] then Exit(True);
end;

end.

unit uarquivoseguro;

{$mode delphi}{$H+}

{
  Gravação segura de imagens enviadas pelo cliente.

  Problema que resolve: o nome do arquivo vinha do cliente e era concatenado direto no
  caminho (./uploads/ + id + _ + nome). Um nome como /../../resources/config.ini escapava
  da pasta uploads e sobrescrevia arquivos do servidor.

  Regras desta unit:
    - o nome que o cliente mandou é IGNORADO (nunca entra no caminho nem no banco);
    - o nome final é PREFIXO + _ + GUID + extensão, gerado aqui;
    - a extensão sai dos BYTES da imagem (JPEG, PNG ou WEBP), não do nome. Por isso uma
      foto de iPhone chamada IMG_1.HEIC, já convertida para JPEG pelo front, continua
      funcionando;
    - tamanho máximo de 8 MB decodificado, e o base64 é medido ANTES de decodificar;
    - o caminho final é conferido: tem que ficar dentro de ./uploads.

  Uso: Preparar devolve o caminho, a URL para o banco e os bytes decodificados. Quem
  chama grava os bytes em ACaminho e guarda AUrlBanco.
}

interface

uses
  Classes, SysUtils, base64;

type
  TArquivoSeguro = class
  public
    class function Preparar(const APrefixo, ABase64: string;
      out ACaminho, AUrlBanco, ADecodificado: string): Boolean;
  end;

implementation

const
  TAMANHO_MAXIMO = 8 * 1024 * 1024; // bytes, já decodificado

// Prefixo vem do UUID da loja (ou de um GUID gerado no servidor). Só aceita o que um
// UUID pode ter, então nunca carrega barra, ponto ou espaço para dentro do caminho.
function PrefixoSeguro(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (Length(S) >= 1) and (Length(S) <= 64);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9', 'a'..'f', 'A'..'F', '-', '{', '}']) then
    begin
      Result := False;
      Exit;
    end;
end;

function ExtensaoPeloConteudo(const D: string): string;
begin
  Result := '';
  if Length(D) < 12 then Exit;

  // JPEG: FF D8 FF
  if (D[1] = #$FF) and (D[2] = #$D8) and (D[3] = #$FF) then
    Result := '.jpg'
  // PNG: 89 'PNG' 0D 0A 1A 0A
  else if Copy(D, 1, 8) = (#$89 + 'PNG' + #$0D#$0A#$1A#$0A) then
    Result := '.png'
  // WEBP: 'RIFF' ???? 'WEBP'
  else if (Copy(D, 1, 4) = 'RIFF') and (Copy(D, 9, 4) = 'WEBP') then
    Result := '.webp';
end;

class function TArquivoSeguro.Preparar(const APrefixo, ABase64: string;
  out ACaminho, AUrlBanco, ADecodificado: string): Boolean;
var
  ext, nome, pasta: string;
  g: TGuid;
begin
  Result := False;
  ACaminho := '';
  AUrlBanco := '';
  ADecodificado := '';

  if (ABase64 = '') or (not PrefixoSeguro(APrefixo)) then Exit;

  // base64 ocupa ~4/3 do tamanho real: recusa o que já é grande demais sem decodificar
  if Length(ABase64) > ((TAMANHO_MAXIMO div 3) + 1) * 4 then Exit;

  try
    ADecodificado := DecodeStringBase64(ABase64);
  except
    ADecodificado := '';
    Exit;
  end;

  if Length(ADecodificado) > TAMANHO_MAXIMO then
  begin
    ADecodificado := '';
    Exit;
  end;

  ext := ExtensaoPeloConteudo(ADecodificado);
  if ext = '' then
  begin
    ADecodificado := '';
    Exit;
  end;

  CreateGUID(g);
  nome := APrefixo + '_' +
    StringReplace(StringReplace(GUIDToString(g), '{', '', [rfReplaceAll]),
                  '}', '', [rfReplaceAll]) + ext;

  pasta := IncludeTrailingPathDelimiter(ExpandFileName('./uploads'));
  ACaminho := ExpandFileName(pasta + nome);

  // última barreira: o arquivo TEM que ficar dentro de ./uploads
  if Pos(pasta, ACaminho) <> 1 then
  begin
    ACaminho := '';
    ADecodificado := '';
    Exit;
  end;

  AUrlBanco := '/imagens/' + nome;
  Result := True;
end;

end.

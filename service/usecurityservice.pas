unit usecurityservice;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, RegExpr;

type
  { TSecurityService }
  { Classe responsável por fornecer métodos de segurança para limpeza e sanitização de dados.
    Segue o paradigma de orientação a objetos com métodos de classe para acesso global. }

  TSecurityService = class
  private
    class function RemoveScripts(const AValue: string): string;
    class function RemoveEventHandlers(const AValue: string): string;
  public
    /// <summary>
    /// Remove tags HTML de uma string de forma robusta, incluindo scripts e manipuladores de eventos.
    /// </summary>
    /// <param name="AValue">O texto original contendo possivelmente HTML.</param>
    /// <returns>O texto limpo, sem tags HTML.</returns>
    class function SanitizeHTML(const AValue: string): string;

    /// <summary>
    /// Escapa caracteres que podem ser usados para injeção de SQL simples em strings.
    /// Nota: O uso de Parâmetros em queries é sempre preferível à sanitização manual.
    /// </summary>
    /// <param name="AValue">A string de entrada.</param>
    /// <returns>A string com caracteres perigosos escapados.</returns>
    class function SanitizeSQL(const AValue: string): string;

    /// <summary>
    /// Método geral de sanitização que aplica múltiplas camadas de proteção.
    /// Ideal para campos de entrada de texto genéricos.
    /// </summary>
    /// <param name="AValue">O valor de entrada bruto.</param>
    /// <returns>O valor sanitizado.</returns>
    class function SanitizeInput(const AValue: string): string;
    
    /// <summary>
    /// Remove caracteres de controle não imprimíveis que podem causar problemas em logs ou exibições.
    /// </summary>
    class function StripControlChars(const AValue: string): string;
  end;

implementation

{ TSecurityService }

class function TSecurityService.RemoveScripts(const AValue: string): string;
var
  Regex: TRegExpr;
begin
  Result := AValue;
  Regex := TRegExpr.Create;
  try
    Regex.ModifierI := True; // Case-insensitive
    // Remove <script>...</script>
    Regex.Expression := '<script.*?>.*?</script>';
    Result := Regex.Replace(Result, '', False);
    
    // Remove tags de estilo que podem conter vetores XSS
    Regex.Expression := '<style.*?>.*?</style>';
    Result := Regex.Replace(Result, '', False);
  finally
    Regex.Free;
  end;
end;

class function TSecurityService.RemoveEventHandlers(const AValue: string): string;
var
  Regex: TRegExpr;
begin
  Result := AValue;
  Regex := TRegExpr.Create;
  try
    Regex.ModifierI := True;
    // Remove manipuladores de eventos (onmouseover, onclick, etc)
    Regex.Expression := '\son\w+\s*=\s*".*?"';
    Result := Regex.Replace(Result, '', False);
    Regex.Expression := '\son\w+\s*=\s*''.*?''';
    Result := Regex.Replace(Result, '', False);
  finally
    Regex.Free;
  end;
end;

class function TSecurityService.SanitizeHTML(const AValue: string): string;
var
  i: Integer;
  InTag: Boolean;
  ProcessedValue: string;
begin
  if AValue = '' then Exit('');

  // 1. Remove scripts e estilos primeiro
  ProcessedValue := RemoveScripts(AValue);
  
  // 2. Remove manipuladores de eventos
  ProcessedValue := RemoveEventHandlers(ProcessedValue);

  // 3. Remoção de tags básica por iteração (mais performático que Regex para este fim simples)
  Result := '';
  InTag := False;
  for i := 1 to Length(ProcessedValue) do
  begin
    case ProcessedValue[i] of
      '<': InTag := True;
      '>': InTag := False;
    else
      if not InTag then
        Result := Result + ProcessedValue[i];
    end;
  end;
  
  Result := Trim(Result);
end;

class function TSecurityService.SanitizeSQL(const AValue: string): string;
begin
  // Escapa aspas simples dobrando-as (padrão SQL)
  Result := StringReplace(AValue, '''', '''''', [rfReplaceAll]);
  // Remove comentários SQL para evitar quebra de queries
  Result := StringReplace(Result, '--', '', [rfReplaceAll]);
  Result := StringReplace(Result, '/*', '', [rfReplaceAll]);
  Result := StringReplace(Result, '*/', '', [rfReplaceAll]);
end;

class function TSecurityService.StripControlChars(const AValue: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(AValue) do
  begin
    if Ord(AValue[i]) >= 32 then
      Result := Result + AValue[i];
  end;
end;

class function TSecurityService.SanitizeInput(const AValue: string): string;
begin
  if AValue = '' then Exit('');
  
  // Combina as proteções
  Result := SanitizeHTML(AValue);
  Result := StripControlChars(Result);
  // O SanitizeSQL é deixado para ser usado especificamente onde queries manuais são montadas
end;

end.

unit uPDFService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, uanamnesemodel, BaseUnix, base64;

type
  { TPDFService }
  TPDFService = class
    class function GerarPDFAnamnese(const ADados: TAnamneseDTO): string;
    class function FileToBase64(const AFileName: string): string;
  private
    class function ExecutarWKHTML(const HTMLContent: string): string;
    class function GetColorClass(const Value: string): string;
    class function SalvarAssinaturaTemp(const Base64Str: string): string;
  end;

implementation

{ TPDFService }


class function TPDFService.GerarPDFAnamnese(const ADados: TAnamneseDTO): string;
var
  Template: TStringList;
  HTMLFinal: string;
  CaminhoImgTemp: string;
begin
  Template := TStringList.Create;
  CaminhoImgTemp := '';
  try
    if FileExists('templates/anamnese.html') then
      Template.LoadFromFile('templates/anamnese.html')
    else
      if FileExists(ExtractFilePath(ParamStr(0)) + 'templates/anamnese.html') then
        Template.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'templates/anamnese.html')
      else
        raise Exception.Create('Template "templates/anamnese.html" não encontrado.');

    HTMLFinal := Template.Text;

    // Substituições de Campos
    HTMLFinal := StringReplace(HTMLFinal, '{{DATA_NASCIMENTO}}', FormatDateTime('dd/mm/yyyy', ADados.DataNascimento), [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{NOME_ESTUDIO}}',         ADados.nome_estudio,        [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{NOME}}',                 ADados.Nome,                [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{TELEFONE}}',             ADados.Telefone,            [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{INSTA}}',                ADados.Insta,               [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{PROFISSAO}}',            ADados.Profissao,           [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{COMO_CONHECEU}}',        ADados.ComoConheceu,        [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{ESTILO_TATUAGEM}}',      ADados.EstiloTatuagem,      [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{GOSTO_PIERCING}}',       ADados.GostoPiercing,       [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{GOSTO_TATUAGEM}}',       ADados.GostoTatuagem,       [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{PROBLEMA_PELE}}',        ADados.ProblemaPele,        [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{QUAL_PROBLEMA_PELE}}',   ADados.QualProblemaPele,    [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{ALERGIA}}',              ADados.Alergia,             [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{QUAL_ALERGIA}}',         ADados.QualAlergia,         [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{MEDICAMENTO}}',          ADados.Medicamento,         [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{QUAL_MEDICAMENTO}}',     ADados.QualMedicamento,     [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{DOENCA_TRANSMISSIVEL}}', ADados.DoencaTransmissivel, [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{QUAL_DOENCA}}',          ADados.QualDoenca,          [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{CONCORDA_TERMOS}}',      ADados.ConcordaTermos,      [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{PRATICA_ESPORTE}}',      ADados.PraticaEsporte,      [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{QUAL_ESPORTE}}',         ADados.QualEsporte,         [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{DROGAS}}',               ADados.AlcoolDrogas,        [rfReplaceAll]);
    // Classes CSS
    HTMLFinal := StringReplace(HTMLFinal, '{{DIABETICO}}', ADados.Diabetico, [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{CLASS_DIABETICO}}', GetColorClass(ADados.Diabetico), [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{HIPERTENSO}}', ADados.Hipertenso, [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{CLASS_HIPERTENSO}}', GetColorClass(ADados.Hipertenso), [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{HEMOFILICO}}', ADados.Hemofilico, [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{CLASS_HEMOFILICO}}', GetColorClass(ADados.Hemofilico), [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{GESTANTE_AMAMENTANDO}}', ADados.GestanteAmamentando, [rfReplaceAll]);
    HTMLFinal := StringReplace(HTMLFinal, '{{CLASS_GESTANTE}}', GetColorClass(ADados.GestanteAmamentando), [rfReplaceAll]);

    if ADados.Assinatura <> ''then
    begin
      CaminhoImgTemp:=SalvarAssinaturaTemp(ADados.Assinatura);
      HTMLFinal := StringReplace(HTMLFinal, '{{ASSINATURA_IMG_TAG}}',
                 '<img src="file://' + CaminhoImgTemp + '" class="signature-img">', [rfReplaceAll]);

    end;
    //else
    //begin
    //  HTMLFinal := StringReplace(HTMLFinal, '{{ASSINATURA_IMG_TAG}}',
    //           '<p>[Sem Assinatura]</p>', [rfReplaceAll]);
    //end;
      HTMLFinal := StringReplace(HTMLFinal, '{{DATA_GERACAO}}', FormatDateTime('dd/mm/yyyy hh:nn', Now), [rfReplaceAll]);

      Result := ExecutarWKHTML(HTMLFinal);

  finally
    Template.Free;
  end;
end;


class function TPDFService.SalvarAssinaturaTemp(const Base64Str: string): string;
var
  CleanBase64: string;
  BinData: string;
  OutFile: TFileStream;
  TempFile: string;
  HeaderPos: Integer;
begin
  TempFile := GetTempDir + 'sig_' + IntToStr(GetTickCount64) + '.png';

  CleanBase64 := Base64Str;

  // 1. Remove cabeçalho (data:image/png;base64,) se existir
  HeaderPos := Pos(',', CleanBase64);
  if HeaderPos > 0 then
     Delete(CleanBase64, 1, HeaderPos);

  // 2. Limpeza segura
  CleanBase64 := StringReplace(CleanBase64, #13, '', [rfReplaceAll]);
  CleanBase64 := StringReplace(CleanBase64, #10, '', [rfReplaceAll]);

  // CRÍTICO: Trocar ESPAÇO por MAIS (+). Remover corrompe o arquivo.
  CleanBase64 := StringReplace(CleanBase64, ' ', '+', [rfReplaceAll]);

  // 3. Padding (Base64 precisa ter tamanho múltiplo de 4)
  while (Length(CleanBase64) mod 4) <> 0 do
    CleanBase64 := CleanBase64 + '=';

  BinData := DecodeStringBase64(CleanBase64);

  OutFile := TFileStream.Create(TempFile, fmCreate);
  try
    if Length(BinData) > 0 then
      OutFile.WriteBuffer(BinData[1], Length(BinData));
  finally
    OutFile.Free;
  end;

  // 4. Garante que o wkhtmltopdf consiga ler o arquivo
  fpChmod(PChar(TempFile), &777);

  Result := TempFile;
end;


class function TPDFService.ExecutarWKHTML(const HTMLContent: string): string;
var
  Proc: TProcess;
  TempHTML, TempPDF, fileBase64: string;
  ErrorMsg: TStringList;
begin
  TempHTML := GetTempDir + 'anamnese_' + IntToStr(GetTickCount64) + '.html';
  TempPDF  := GetTempDir + 'anamnese_' + IntToStr(GetTickCount64) + '.pdf';

  with TStringList.Create do
  try
    Text := HTMLContent;
    SaveToFile(TempHTML);
  finally
    Free;
  end;

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := '/usr/bin/xvfb-run';

    // Parâmetros do Xvfb
    Proc.Parameters.Add('-a');

    // CORREÇÃO CRÍTICA: SEM ASPAS DUPLAS ENVOLVENDO O COMANDO
    // O TProcess já faz o escape correto. Aspas aqui quebram o Linux.
    Proc.Parameters.Add('--server-args=-screen 0 640x480x16');

    // Comando payload
    Proc.Parameters.Add('/usr/bin/wkhtmltopdf');

    // Parâmetros do wkhtmltopdf
    Proc.Parameters.Add('-q');
    Proc.Parameters.Add('--enable-local-file-access');

    // Tratamento de erros de load
    Proc.Parameters.Add('--load-error-handling');
    Proc.Parameters.Add('ignore');

    // Margens
    Proc.Parameters.Add('--margin-top'); Proc.Parameters.Add('10mm');
    Proc.Parameters.Add('--margin-bottom'); Proc.Parameters.Add('10mm');
    Proc.Parameters.Add('--margin-left'); Proc.Parameters.Add('10mm');
    Proc.Parameters.Add('--margin-right'); Proc.Parameters.Add('10mm');

    Proc.Parameters.Add(TempHTML);
    Proc.Parameters.Add(TempPDF);

    Proc.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut];
     Proc.Execute;

    if Proc.ExitStatus <> 0 then
    begin
      ErrorMsg := TStringList.Create;
      try
        ErrorMsg.LoadFromStream(Proc.Output);
        if not FileExists(TempPDF) then
           raise Exception.Create('Erro wkhtmltopdf: ' + ErrorMsg.Text);
      finally
        ErrorMsg.Free;
      end;
    end;

    if not FileExists(TempPDF) then
      raise Exception.Create('PDF não foi gerado no caminho esperado.');

    Result := TempPDF;
  finally
    Proc.Free;
    if FileExists(TempHTML) then DeleteFile(TempHTML);
  end;
end;

class function TPDFService.FileToBase64(const AFileName: string): string;
var
  MS: TMemoryStream;
  Str: String;          // Buffer para o conteúdo binário
  ResultBase64: String; // Nova variável para o resultado (não use o nome "Base64")
begin
  Result := '';
  if not FileExists(AFileName) then Exit;

  MS := TMemoryStream.Create;
  try
    MS.LoadFromFile(AFileName);
    if MS.Size > 0 then
    begin
      // 1. Configura o tamanho da string igual ao tamanho do arquivo (bytes)
      SetLength(Str, MS.Size);

      // 2. Lê o binário para dentro da String
      MS.ReadBuffer(Str[1], MS.Size);

      // 3. Converte
      ResultBase64 := EncodeStringBase64(Str);

      // 4. Limpeza de segurança (CRÍTICO para PDF não corromper)
      ResultBase64 := StringReplace(ResultBase64, #13, '', [rfReplaceAll]);
      ResultBase64 := StringReplace(ResultBase64, #10, '', [rfReplaceAll]);

      Result := ResultBase64;
    end;
  finally
    MS.Free;
  end;
end;

class function TPDFService.GetColorClass(const Value: string): string;
begin
  if (Pos('Sim', Value) > 0) or (Pos('True', Value) > 0) or (Pos('S', Value) = 1) then
    Result := 'answer-yes'
  else
    Result := 'answer-no';
end;

end.

unit uNetService;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, RESTRequest4D, fpjson, jsonparser,
  uconfig;

type

  { TNetService }

  TNetService = class
  public
    class procedure EnviarArquivoWhatsapp(numero, arquivo, arquivo64, legenda, instance: string);
    class function getBase64(var arq: string): string;
    class function getGemini(var json: TJSONObject; const prompt: string): UTF8String;
    class function rec_senha(var email, senha:string): string;
    class function get(const url: string; out AStatusCode: integer): UTF8String; overload;
    class function get(url, autname, autvalue: string; out AStatus_code: integer): UTF8String;
    class function post(const url, autname, autvalue: string; const body: UTF8String; out AStatusCode: Integer): UTF8String;
    class function post(const url, autname, autvalue: string; const body: TJSONObject): UTF8String; overload;
    class function getGeminiMultimodal(const APrompt, ABase64Image,
      AMimeType: string): UTF8String;
    class function EnviarPushOneSignal(const AExternalID, ATitulo, AMensagem, AUrl: string): string;
  end;

implementation

{ TNetService }


class function TNetService.getGeminiMultimodal(const APrompt, ABase64Image, AMimeType: string): UTF8String;
var
  LResponse: IResponse;
  LRoot, LContent, LPartText, LPartMedia, LInlineData, LJSONResponse: TJSONObject;
  LContentsArray, LPartsArray: TJSONArray;
  resposta: string;
begin
  LRoot          := TJSONObject.Create;
  LContentsArray := TJSONArray.Create;
  LContent       := TJSONObject.Create;
  LPartsArray    := TJSONArray.Create;

  try
    // 1. Parte de Texto (Prompt + Instruções + Exemplo)
    LPartText := TJSONObject.Create;
    LPartText.Add('text', APrompt);
    LPartsArray.Add(LPartText);

    // 2. Parte de Mídia (se houver imagem)
    if ABase64Image <> '' then
    begin
      LPartMedia  := TJSONObject.Create;
      LInlineData := TJSONObject.Create;
      LInlineData.Add('mime_type', AMimeType);
      LInlineData.Add('data', ABase64Image);
      LPartMedia.Add('inline_data', LInlineData);
      LPartsArray.Add(LPartMedia);
    end;

    LContent.Add('parts', LPartsArray);
    LContentsArray.Add(LContent);
    LRoot.Add('contents', LContentsArray);

    LResponse := TRequest.New.BaseURL('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent')
          .AddHeader('x-goog-api-key', TConfig.ConfigValue('google', 'api_key', ''))
              .ContentType('application/json')
              .AddBody(LRoot.AsJSON)
              .Post;

    if LResponse.StatusCode = 200 then
    begin
      // Extrai o texto da resposta do Gemini
      LJSONResponse := TJSONObject(GetJSON(LResponse.Content));
      try
        resposta := LJSONResponse.Arrays['candidates']
                                 .Objects[0]
                                 .Objects['content']
                                 .Arrays['parts']
                                 .Objects[0]
                                 .Strings['text'];

        // Limpezas de formatação
        resposta := StringReplace(resposta, #10, sLineBreak, [rfReplaceAll]);
        resposta := StringReplace(resposta, '```json', '', [rfReplaceAll, rfIgnoreCase]);
        resposta := StringReplace(resposta, '```', '', [rfReplaceAll]);

        Result := Trim(resposta);
      finally
        LJSONResponse.Free;
      end;
    end
    else
      Result := 'Erro IA: ' + LResponse.Content;

  finally
    LRoot.Free;
  end;
end;

class function TNetService.EnviarPushOneSignal(const AExternalID, ATitulo, AMensagem, AUrl: string): string;
var
  JSONBody, Aliases, Headings, Contents: TJSONObject;
  ExternalIDArray: TJSONArray;
  Response: IResponse;
begin
  JSONBody := TJSONObject.Create;
    try
      // Construir a Estrutura do JSON
      JSONBody.Add('app_id', '77e0ed01-8f73-4091-8870-6561dd849c44');
      JSONBody.Add('target_channel', 'push');

      ExternalIDArray := TJSONArray.Create;
      ExternalIDArray.Add(AExternalID);
      Aliases := TJSONObject.Create;
      Aliases.Add('external_id', ExternalIDArray);
      JSONBody.Add('include_aliases', Aliases);

      Headings := TJSONObject.Create;
      Headings.Add('en', ATitulo);
      Headings.Add('pt', ATitulo);
      JSONBody.Add('headings', Headings);

      Contents := TJSONObject.Create;
      Contents.Add('en', AMensagem);
      Contents.Add('pt', AMensagem);
      JSONBody.Add('contents', Contents);

      if AUrl <> '' then
        JSONBody.Add('url', AUrl);

      // Requisição com RR4D
      Response := TRequest.New.BaseURL('https://api.onesignal.com/notifications?c=push')
        .AddHeader('Authorization', 'Basic ' + TConfig.ConfigValue('onesignal', 'rest_api_key', ''))
        .ContentType('application/json; charset=utf-8')
        .AddBody(JSONBody.AsJSON)
        .Post;

      Result := Response.Content;
    finally
      JSONBody.Free;
    end;

end;

class procedure TNetService.EnviarArquivoWhatsapp(numero, arquivo, arquivo64,
  legenda, instance: string);
var
  LJsonBody, JsonRes: TJSONObject;
  lresponse: IResponse;
  resposta, nome_arquivo, url: string;
begin
  url := '';
  url := TConfig.ConfigValue('services', 'url', '')+'/message/sendMedia/'+instance;
  LJsonBody := TJSONObject.Create;

  nome_arquivo := ExtractFileName(arquivo);

  LJsonBody.Add('number',      '55' + numero );
  LJsonBody.add('mediatype',       'document');
  LJsonBody.add('mimetype', 'application/pdf');
  LJsonBody.add('media',            arquivo64);
  LJsonBody.add('caption',            legenda);
  LJsonBody.add('fileName',      nome_arquivo);

  lresponse := TRequest.New.BaseURL(url)
    .AddBody(LJsonBody)
    .ContentType('application/json; charset=utf-8')
    .AddHeader('apikey', TConfig.ConfigValue('services', 'internal_apikey', ''))
    .Post;

  resposta := lresponse.Content;
  Sleep(1);
end;

class function TNetService.getBase64(var arq: string): string;
var
  lResponse: IResponse;
  respostas: string;
begin
  lResponse := TRequest.New.BaseURL('http://127.0.0.1:8000')
            .Resource('encode-file')
            .AddParam('path', arq)
            .Get;

  respostas := lResponse.Content;

  result := respostas;
end;

class function TNetService.getGemini(var json: TJSONObject; const prompt: string): UTF8String;
var
  lresponse: IResponse;
  LRoot, LContentObj, LPartObj, LJSONResponse: TJSONObject;
  LContentsArray, LPartsArray: TJSONArray;
  resposta: string;
begin
  LRoot          := TJSONObject.Create;
  LContentObj    := TJSONObject.Create;
  LPartObj       := TJSONObject.Create;

  LContentsArray := TJSONArray.Create;
  LPartsArray    := TJSONArray.Create;

  try
    try
      LPartObj.Add('text', prompt + json.AsJSON);
      LPartsArray.Add(LPartObj);
      LContentObj.Add('parts', LPartsArray);
      LContentsArray.Add(LContentObj);
      LRoot.Add('contents', LContentsArray);

      lresponse := TRequest.New.BaseURL(TConfig.ConfigValue('google', 'model', ''))
                .AddHeader('x-goog-api-key', TConfig.ConfigValue('google', 'api_key', ''))
                .ContentType('application/json')
                .AddBody(LRoot.AsJSON)
                .Post;

      LJSONResponse := TJSONObject(GetJSON(LResponse.Content));

      resposta :=   LJSONResponse.Arrays['candidates']
                                 .Objects[0]
                                 .Objects['content']
                                 .Arrays['parts']
                                 .Objects[0]
                                 .Strings['text'];

      resposta := StringReplace(resposta, #10, sLineBreak, [rfReplaceAll]);
      resposta := StringReplace(resposta, '```json', '', [rfReplaceAll, rfIgnoreCase]);
      resposta := StringReplace(resposta, '```', '', [rfReplaceAll]);
      resposta := Trim(resposta);

      Result := resposta;
    except
      result := '';
    end;
  finally
    LRoot.Free;
    LJSONResponse.Free;
  end;
end;

class function TNetService.rec_senha(var email, senha: string): string;
var
  lresponse: IResponse;
  url, resposta: string;
begin
  url := Format('http://127.0.0.1:8085/rec_senha/%s/%s', [email, senha]);
  lresponse := TRequest.New.BaseURL(url).get;
  resposta:=lresponse.Content;
  result := resposta;
end;

class function TNetService.get(const url: string; out
  AStatusCode: integer): UTF8String;
var
  lresponse: IResponse;
begin
  try
    lresponse := TRequest.New
      .BaseURL(url)
      .get;

    AStatusCode := LResponse.StatusCode;
    Result := lresponse.Content;
  except on e:exception do
    begin
      AStatusCode := 500;
      Result := '{"message": "' + E.Message + '"}';
    end;
  end;
end;

class function TNetService.get(url, autname, autvalue: string;
  out AStatus_code: integer): UTF8String;
var
  LResponse: IResponse;
begin
  try
    LResponse := TRequest.New.BaseURL(url).AddHeader(autname, autvalue).Get;
    AStatus_code:= LResponse.StatusCode;
    Result := LResponse.Content;

  except on E: Exception do
    begin
      Result := '{"message": "'+e.Message+'"}';

      if Pos('404', E.Message) > 0 then
        AStatus_code := 404
      else
        AStatus_code := 500;
    end;
  end;
end;


class function TNetService.post(const url, autname, autvalue: string;
  const body: UTF8String; out AStatusCode: Integer): UTF8String;
var
  lresponse: IResponse;
begin
  try
    lresponse := TRequest.New.BaseURL(url)
                  .ContentType('application/json; charset=utf-8')
                  .AddHeader(autname, autvalue)
                  .AddBody(body)
                  .Post;

    Result := LResponse.Content;
    AStatusCode := lresponse.StatusCode;

  except
    raise;
  end;
end;

class function TNetService.post(const url, autname, autvalue: string;
  const body: TJSONObject):UTF8String;
var
  lresponse: IResponse;
begin
  try
    lresponse := TRequest.New.BaseURL(url)
                  .ContentType('application/json; charset=utf-8')
                  .AddHeader(autname, autvalue)
                  .AddBody(body)
                  .Post;

    Result := LResponse.Content;
  except
    raise;
  end;
end;



end.


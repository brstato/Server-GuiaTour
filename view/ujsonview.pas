// TJsonView.pas - Novo unit em Views/
unit uJsonView;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, fpjson, LazUTF8, StrUtils;

type

  { TJsonView }

  TJsonView = class
  public
    class procedure SendResponse(Res: THorseResponse; AJSONObject: TJSONObject; Status: integer); overload;
    class procedure SendResponse(Res: THorseResponse; StatusCode: integer); overload;
    class procedure SendResponseJsonObject(Res: THorseResponse; var AJSONObject: TJSONObject; Status: integer);
    class procedure SendSuccess(Res: THorseResponse; const AMessage: string = 'Operação realizada com sucesso.');
    class procedure SendError(Res: THorseResponse; const AStatusCode: Integer; const AMessage: string);
    class procedure SendHtml(Res: THorseResponse; const AStatusCode: Integer; const AHtml: string);
    class procedure SendText(Res: THorseResponse; const AStatusCode: Integer; const Str: string);
  end;

implementation

class procedure TJsonView.SendResponse(Res: THorseResponse; AJSONObject: TJSONObject; Status: integer);
begin
  Res.Status(Status).ContentType('application/json; charset=UTF-8')
     .Send(AJSONObject.AsJSON);
end;

class procedure TJsonView.SendResponse(Res: THorseResponse; StatusCode: integer);
begin
  Res.Status(StatusCode).ContentType('application/text; charset=UTF-8').Send('');
end;

class procedure TJsonView.SendResponseJsonObject(Res: THorseResponse;
  var AJSONObject: TJSONObject; Status: integer);
begin
  try
    Res.Status(Status).ContentType('application/json; charset=UTF-8')
       .Send(AJSONObject.AsJSON);
  finally
     AJSONObject.Free;
  end;
end;

class procedure TJsonView.SendSuccess(Res: THorseResponse; const AMessage: string);
var
  SuccessObject: TJSONObject;
begin
  SuccessObject := TJSONObject.Create;
  try
    SuccessObject.Add('success', TJSONBoolean.Create(True));
    SuccessObject.Add('message', AMessage);
    Res.Status(200).ContentType('application/json; charset=UTF-8').Send(SuccessObject.AsJSON);
  finally
    SuccessObject.Free;
  end;
end;

class procedure TJsonView.SendError(Res: THorseResponse; const AStatusCode: Integer; const AMessage: string);
var
  ErrorObject: TJSONObject;
begin
  ErrorObject := TJSONObject.Create;
  try
    ErrorObject.Add('success', TJSONBoolean.Create(False));
    ErrorObject.Add('error', AMessage);
    Res.Status(AStatusCode).ContentType('application/json; charset=UTF-8').Send(ErrorObject.AsJSON);
  finally
    ErrorObject.Free;
  end;
end;

class procedure TJsonView.SendHtml(Res: THorseResponse;
  const AStatusCode: Integer; const AHtml: string);
begin
  Res.Status(AStatusCode).ContentType('text/html; charset=utf-8')
     .Send(AHtml);
end;

class procedure TJsonView.SendText(Res: THorseResponse;
  const AStatusCode: Integer; const Str: string);
begin
  Res.Status(AStatusCode).ContentType('text/plain; charset=utf-8')
     .Send(Str);
end;

end.

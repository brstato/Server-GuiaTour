unit uanamneseview;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  { TAnamneseView }
  TAnamneseView = class
    public
      class function Render(const IdLoja: string): string;
  end;

implementation

uses
  urouter;

{ TAnamneseView }

class function TAnamneseView.Render(const IdLoja: string): string;
var
  HTMLFinal, OptionsHtml: string;
  i: Integer;
  ProfObj: TJSONObject;
begin

  HTMLFinal := tAppRouter.anamnese_html;
  OptionsHtml := '<option value="" disabled selected hidden>Selecione o profissional que irá atendê-lo</option>';

  //if Assigned(ProfissionaisJSON) then
  //begin
  //  for i := 0 to ProfissionaisJSON.Count - 1 do
  //  begin
  //    ProfObj := TJSONObject(ProfissionaisJSON.Items[i]);
  //    OptionsHtml := OptionsHtml +
  //                   '<option value="' + IntToStr(ProfObj.Integers['id']) + '">' +
  //                   ProfObj.Strings['nome'] +
  //                   '</option>';
  //  end;
  //end;

  // Motor de Substituição de Tags
  //HTMLFinal := StringReplace(HTMLFinal, '{{PROFISSIONAIS_OPTIONS}}', OptionsHtml, [rfReplaceAll]);
  HTMLFinal := StringReplace(HTMLFinal, '{{ESTUDIO_ID}}', IdLoja, [rfReplaceAll]);

  Result := HTMLFinal;
end;

end.

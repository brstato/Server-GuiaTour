unit uconfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  TConfig = class
    public
      class function ConfigValue(const Section, Name, Default: string): string;
  end;

implementation

var
  Ini: TIniFile;

class function TConfig.ConfigValue(const Section, Name, Default: string): string;
begin
  if Assigned(Ini) then
    Result := Ini.ReadString(Section, Name, Default)
  else
    Result := Default;
end;

initialization
  try
    Ini := TIniFile.Create(ExpandFileName(ExtractFilePath(ParamStr(0)) + 'resources' + PathDelim + 'config.ini'));
  except
    Ini := nil;
  end;

finalization
  if Assigned(Ini) then
    Ini.Free;

end.

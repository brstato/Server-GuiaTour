unit utokenmanager;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, uoauthtokenmodel;

type

  { TTokenManager }

  TTokenManager = class
    private
      class var FAccessToken: string;
      class var FRefreshToken: string;
      class var FInitialized: Boolean;
      class procedure InitializeTokens;
    public
      class function GetTokens(out AccessToken, RefreshToken: string): Boolean;
      class procedure UpdateTokens(const NewAccessToken, NewRefreshToken: string);
      class procedure RefreshTokens;
  end;

implementation

{ TTokenManager }

class procedure TTokenManager.InitializeTokens;
begin
  FAccessToken := '';
  FRefreshToken := '';
  FInitialized := True;
end;

class function TTokenManager.GetTokens(out AccessToken, RefreshToken: string
  ): Boolean;
begin
  if not FInitialized then
    InitializeTokens;

  AccessToken := FAccessToken;
  RefreshToken := FRefreshToken;
  Result := (AccessToken <> '') and (RefreshToken <> '');
end;

class procedure TTokenManager.UpdateTokens(const NewAccessToken,
  NewRefreshToken: string);
begin
  FAccessToken := NewAccessToken;
  if NewRefreshToken <> '' then
    FRefreshToken := NewRefreshToken;
end;

class procedure TTokenManager.RefreshTokens;
var
  OAuthModel: TOAuthTokenModel;
  NewAccessToken: string;
begin
  if not FInitialized then
    InitializeTokens;

  OAuthModel := TOAuthTokenModel.Create('');
  try
    if OAuthModel.RefreshAccessToken() then
      UpdateTokens(NewAccessToken, '');
  finally
    OAuthModel.Free;
  end;
end;

end.


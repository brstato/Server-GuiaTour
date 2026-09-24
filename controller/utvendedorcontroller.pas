unit utvendedorcontroller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, uloginmodel, uvendedormodel, uJsonView, fpjson,
  udata, uconfig, usecurityservice, Horse.JWT;

type

  { TVendedorController }

  TVendedorController = class
  private
  public
    class procedure RegisterRoutes();
  end;

implementation

{ TVendedorController }

procedure HandleLoginGoogleVendedor(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  RequestJson, LoginData: TJSONObject;
  GoogleCode, r_token: string;
  status: integer;
begin
  RequestJson := nil;
  try
    try
      if Trim(Req.Body) = '' then
      begin
        TJsonView.SendError(Res, 400, 'Corpo da requisição está vazio.');
        Exit;
      end;

      RequestJson := TJSONObject(GetJSON(Req.Body));
      GoogleCode := RequestJson.Get('g_code', '');
      r_token    := RequestJson.Get('r_token', '');

      if GoogleCode = '' then
      begin
        TJsonView.SendError(Res, 400, 'Código de autorização ausente.');
        Exit;
      end;

      LoginData := TJSONObject(GetJSON(
        TLoginModel.LoginGoogleVendedor(GoogleCode, status, r_token)
      ));

      TJsonView.SendResponse(Res, LoginData, status);
    except on e: Exception do
      begin
        WriteLn('Erro em: HandleLoginGoogleVendedor - ' + e.Message);
        TJsonView.SendError(Res, 500, 'Erro interno.');
      end;
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
  end;
end;

function ExigirDonoDaLoja(Req: THorseRequest; Res: THorseResponse;
        const uuidLoja: string; out idVendedor: string): Boolean;
var
  tipo: string;
begin
  Result := False;
  tipo := TDataModule1.GetTipoUsuario(Req.Headers['Authorization']);

  if tipo <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
    Exit;
  end;

  idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']); // claim 'id'

  if Trim(uuidLoja) = '' then
  begin
    TJsonView.SendError(Res, 400, 'Comércio não informado.');
    Exit;
  end;

  if not TVendedorModel.DonoDaLoja(idVendedor, uuidLoja) then
  begin
    TJsonView.SendError(Res, 403, 'Você não tem acesso a este comércio.');
    Exit;
  end;

  Result := True;
end;

procedure HandlerListarComercios(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor, tipo: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    tipo := TDataModule1.GetTipoUsuario(Req.Headers['Authorization']);
    if tipo <> 'vendedor' then
    begin
      TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
      Exit;
    end;

    idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']);
    arrayItens := TVendedorModel.ListarComercios(idVendedor);

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);

    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      // jsonRes já é dono de arrayItens depois do Add acima — liberar os
      // dois separadamente seria double free. Só libera arrayItens direto
      // se ele ainda não foi anexado a jsonRes.
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerListarComercios - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerCriarComercio(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  RequestJson: TJSONObject;
  idVendedor, tipo, nome, telefone, email, slug, uuidLoja: string;
  idCategoria: integer;
begin
  RequestJson := nil;
  try
    try
      tipo := TDataModule1.GetTipoUsuario(Req.Headers['Authorization']);
      if tipo <> 'vendedor' then
      begin
        TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
        Exit;
      end;

      if Trim(Req.Body) = '' then
      begin
        TJsonView.SendError(Res, 400, 'Corpo da requisição está vazio.');
        Exit;
      end;

      idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']);
      RequestJson := TJSONObject(GetJSON(Req.Body));

      nome        := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome', '')));
      telefone    := TSecurityService.SanitizeInput(Trim(RequestJson.Get('telefone', '')));
      email       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('email', '')));
      slug        := TSecurityService.SanitizeInput(Trim(RequestJson.Get('slug', '')));
      idCategoria := RequestJson.Get('id_categoria', 11);

      if (nome = '') or (email = '') then
      begin
        TJsonView.SendError(Res, 400, 'Nome e e-mail são obrigatórios.');
        Exit;
      end;

      uuidLoja := TVendedorModel.CriarComercio(
        idVendedor, nome, telefone, email, slug, idCategoria
      );

      TJsonView.SendResponse(Res,
        TJSONObject(GetJSON('{"uuid":"' + uuidLoja + '"}')), 201);
    except on e: Exception do
      begin
        WriteLn('Erro em: HandlerCriarComercio - ' + e.Message);
        TJsonView.SendError(Res, 500, 'Erro interno.');
      end;
    end;
  finally
    if Assigned(RequestJson) then RequestJson.Free;
  end;
end;

class procedure TVendedorController.RegisterRoutes();
begin
  THorse.Post('api/v1/login_google_vendedor', HandleLoginGoogleVendedor);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/comercios', HandlerListarComercios);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/vendedor/comercio', HandlerCriarComercio);
end;

end.

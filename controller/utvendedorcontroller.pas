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
  vendorList: TVendorList;
  tipo, uuidLoja: string;
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

      vendorList.idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']);
      RequestJson := TJSONObject(GetJSON(Req.Body));

      with vendorList do
      begin
        nome            := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome',             '')));
        slug            := TSecurityService.SanitizeInput(Trim(RequestJson.Get('slug',             '')));
        telefone        := TSecurityService.SanitizeInput(Trim(RequestJson.Get('telefone',         '')));
        email           := TSecurityService.SanitizeInput(Trim(RequestJson.Get('email',            '')));
        insta           := TSecurityService.SanitizeInput(Trim(RequestJson.Get('insta',            '')));
        cep             := TSecurityService.SanitizeInput(Trim(RequestJson.Get('cep',              '')));
        endereco        := TSecurityService.SanitizeInput(Trim(RequestJson.Get('endereco',         '')));
        numero          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('numero',           '')));
        complemento     := TSecurityService.SanitizeInput(Trim(RequestJson.Get('complemento',      '')));
        bairro          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('bairro',           '')));
        cidade          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('cidade',           '')));
        estado          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('estado',           '')));
        g_analytcs      := TSecurityService.SanitizeInput(Trim(RequestJson.Get('g_analytcs',       '')));
        meta_pixel_id   := TSecurityService.SanitizeInput(Trim(RequestJson.Get('meta_pixel_id',    '')));
        conta_google_ads:= TSecurityService.SanitizeInput(Trim(RequestJson.Get('conta_google_ads', '')));
        horario         := TSecurityService.SanitizeInput(Trim(RequestJson.Get('horario',          '')));
        titulo          := TSecurityService.SanitizeInput(Trim(RequestJson.Get('titulo',           '')));
        subtitulo       := TSecurityService.SanitizeInput(Trim(RequestJson.Get('subtitulo',        '')));
        bio             := TSecurityService.SanitizeInput(Trim(RequestJson.Get('bio',              '')));

        nome_arquivo_foto_avatar := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome_arquivo_foto_avatar','')));
        nome_arquivo_foto_bio    := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome_arquivo_foto_bio',   '')));
        nome_arquivo_foto_capa   := TSecurityService.SanitizeInput(Trim(RequestJson.Get('nome_arquivo_foto_capa',  '')));

        foto_bio        := RequestJson.Get('foto_bio',  '');
        avatar          := RequestJson.Get('avatar',    '');
        foto_capa       := RequestJson.Get('foto_capa', '');
        trabalhos       := RequestJson.Get('trabalhos', '');

        vendorList.id_categoria := RequestJson.Get('id_categoria', 0);
      end;

      if vendorList.id_categoria <= 0 then
      begin
        TJsonView.SendError(Res, 400, 'Categoria é obrigatória.');
        Exit;
      end;

      if (vendorList.nome = '') or (vendorList.email = '') then
      begin
        TJsonView.SendError(Res, 400, 'Nome e e-mail são obrigatórios.');
        Exit;
      end;

      uuidLoja := TVendedorModel.CriarComercio(vendorList);

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

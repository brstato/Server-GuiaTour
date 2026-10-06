unit uautorizacao;

{$mode delphi}{$H+}

{
  Autorização por loja, num lugar só.

  Problema que resolve: várias rotas pegavam o id da loja do corpo ou da query da
  requisição (TDataModule1.GetTargetIdLoja, Query id_loja) e operavam nela sem conferir se
  quem chamou era o dono. Qualquer usuário logado lia (inclusive o meta_long_token) e
  alterava qualquer loja.

  Regras (todas conferidas no banco a cada requisição, falhando FECHADO: erro de banco
  nunca libera):
    - token tipo "loja":     só opera a PRÓPRIA loja (o UUID do token). Qualquer id_loja
                             enviado pelo cliente é ignorado.
    - token tipo "vendedor": precisa estar ATIVO e ser o DONO da loja. Se AAdminPode for
                             True, o vendedor ADMINISTRADOR (ATIVO e ADM) também passa.
    - qualquer outro tipo:   403.

  ResolverLoja     : descobre a loja da requisição (token ou id_loja) e autoriza.
  ExigirAcessoALoja: autoriza o acesso a uma loja cujo UUID já se conhece.
  ExigirAcessoAFoto: descobre a loja dona da foto da galeria e autoriza.
  ExigirVendedorAtivo: só exige vendedor ATIVO (rotas que não são de uma loja só).
}

interface

uses
  Classes, SysUtils, Horse, fpjson, udata, uJsonView, uvendedormodel, uadminmodel;

type
  TAutorizacao = class
  public
    class function UuidPareceValido(const S: string): Boolean;
    class function ExigirVendedorAtivo(Req: THorseRequest; Res: THorseResponse;
      out AIdVendedor: string): Boolean;
    class function ExigirAcessoALoja(Req: THorseRequest; Res: THorseResponse;
      const AUuidLoja: string; AAdminPode: Boolean; out AComoAdmin: Boolean): Boolean;
    class function ResolverLoja(Req: THorseRequest; Res: THorseResponse;
      ABody: TJSONObject; AAdminPode: Boolean; out AUuidLoja: string;
      out AComoAdmin: Boolean): Boolean;
    class function ResolverLojaDono(Req: THorseRequest; Res: THorseResponse;
      ABody: TJSONObject; out AUuidLoja: string): Boolean;
    class function ExigirAcessoAFoto(Req: THorseRequest; Res: THorseResponse;
      AIdFoto: Integer): Boolean;
  end;

implementation

// id_loja vindo do cliente: só hexadecimais, hífen e chaves, de 32 a 38 caracteres.
// Barra lixo e quebras de linha antes de chegar ao banco e aos logs.
class function TAutorizacao.UuidPareceValido(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (Length(S) >= 32) and (Length(S) <= 38);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9', 'a'..'f', 'A'..'F', '-', '{', '}']) then
    begin
      Result := False;
      Exit;
    end;
end;

class function TAutorizacao.ExigirVendedorAtivo(Req: THorseRequest;
  Res: THorseResponse; out AIdVendedor: string): Boolean;
var
  auth: string;
begin
  Result := False;
  AIdVendedor := '';

  auth := Req.Headers['Authorization'];
  if TDataModule1.GetTipoUsuario(auth) <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
    Exit;
  end;

  AIdVendedor := TDataModule1.GetIdLoja(auth); // claim "id" = UUID do vendedor

  try
    // o JWT pode ter sido emitido antes de o vendedor ser desativado
    if not TAdminModel.VendedorAtivo(AIdVendedor) then
    begin
      TJsonView.SendError(Res, 403, 'Vendedor inativo.');
      Exit;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Erro em: ExigirVendedorAtivo - ' + E.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
      Exit;
    end;
  end;

  Result := True;
end;

class function TAutorizacao.ExigirAcessoALoja(Req: THorseRequest;
  Res: THorseResponse; const AUuidLoja: string; AAdminPode: Boolean;
  out AComoAdmin: Boolean): Boolean;
var
  auth, tipo, idToken: string;
begin
  Result := False;
  AComoAdmin := False;

  auth := Req.Headers['Authorization'];
  idToken := TDataModule1.GetIdLoja(auth);
  tipo := TDataModule1.GetTipoUsuario(auth);

  if idToken = '' then
  begin
    TJsonView.SendError(Res, 401, 'Não autenticado.');
    Exit;
  end;

  if tipo = 'loja' then
  begin
    if not SameText(idToken, AUuidLoja) then
    begin
      TJsonView.SendError(Res, 403, 'Acesso negado.');
      Exit;
    end;
    Result := True;
    Exit;
  end;

  if tipo <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso negado.');
    Exit;
  end;

  try
    if not TAdminModel.VendedorAtivo(idToken) then
    begin
      TJsonView.SendError(Res, 403, 'Vendedor inativo.');
      Exit;
    end;

    if not TVendedorModel.DonoDaLoja(idToken, AUuidLoja) then
    begin
      if AAdminPode and TAdminModel.VendedorAdmin(idToken) then
        AComoAdmin := True
      else
      begin
        TJsonView.SendError(Res, 403, 'Esta loja não pertence a este vendedor.');
        Exit;
      end;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Erro em: ExigirAcessoALoja - ' + E.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
      Exit;
    end;
  end;

  Result := True;
end;

class function TAutorizacao.ResolverLoja(Req: THorseRequest; Res: THorseResponse;
  ABody: TJSONObject; AAdminPode: Boolean; out AUuidLoja: string;
  out AComoAdmin: Boolean): Boolean;
var
  auth, tipo, idToken: string;
begin
  Result := False;
  AUuidLoja := '';
  AComoAdmin := False;

  auth := Req.Headers['Authorization'];
  idToken := TDataModule1.GetIdLoja(auth);
  tipo := TDataModule1.GetTipoUsuario(auth);

  if idToken = '' then
  begin
    TJsonView.SendError(Res, 401, 'Não autenticado.');
    Exit;
  end;

  if tipo = 'loja' then
  begin
    AUuidLoja := idToken; // loja só age sobre si mesma; id_loja do cliente é ignorado
    Result := True;
    Exit;
  end;

  if tipo <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso negado.');
    Exit;
  end;

  try
    if ABody <> nil then
      AUuidLoja := ABody.Get('id_loja', '');
    if AUuidLoja = '' then
      AUuidLoja := Req.Query['id_loja'];
  except
    AUuidLoja := '';
  end;

  if AUuidLoja = '' then
  begin
    TJsonView.SendError(Res, 400, 'Informe o id_loja.');
    Exit;
  end;
  if not UuidPareceValido(AUuidLoja) then
  begin
    AUuidLoja := '';
    TJsonView.SendError(Res, 400, 'id_loja inválido.');
    Exit;
  end;

  if not ExigirAcessoALoja(Req, Res, AUuidLoja, AAdminPode, AComoAdmin) then
  begin
    AUuidLoja := '';
    Exit;
  end;

  Result := True;
end;

// Atalho para as rotas que LEEM ou ALTERAM dados de uma loja: só a própria loja ou o
// vendedor DONO passam (administrador NÃO edita loja alheia por aqui).
class function TAutorizacao.ResolverLojaDono(Req: THorseRequest; Res: THorseResponse;
  ABody: TJSONObject; out AUuidLoja: string): Boolean;
var
  comoAdmin: Boolean;
begin
  Result := ResolverLoja(Req, Res, ABody, False, AUuidLoja, comoAdmin);
end;

class function TAutorizacao.ExigirAcessoAFoto(Req: THorseRequest;
  Res: THorseResponse; AIdFoto: Integer): Boolean;
var
  uuidLoja: string;
  comoAdmin: Boolean;
begin
  Result := False;

  try
    uuidLoja := TAdminModel.LojaDaFoto(AIdFoto);
  except
    on E: Exception do
    begin
      WriteLn('Erro em: ExigirAcessoAFoto - ' + E.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
      Exit;
    end;
  end;

  if uuidLoja = '' then
  begin
    TJsonView.SendError(Res, 404, 'Foto não encontrada.');
    Exit;
  end;

  // remover foto é destrutivo: só o dono (ou a própria loja), nunca "como administrador"
  Result := ExigirAcessoALoja(Req, Res, uuidLoja, False, comoAdmin);
end;

end.

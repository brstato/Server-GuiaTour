unit utlojacontroller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, ulojamodel, uJsonView, fpjson,
  sql_queries, udata, ucacheservice, Horse.JWT, usecurityservice, uconfig;

type

  { TlojaController }

  TlojaController = class
    private
    public
      class procedure RegisterRoutes();
  end;

implementation

{ TlojaController }

procedure handlerGetDataAccount(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   JsonResponse: TJSONObject;
   LModel: TLojaModel;
   id: string;
begin
   //id := Req.Params['id'];
   id := TDataModule1.GetIdLoja(Req.Headers['Authorization']);
   LModel := TLojaModel.Create;
   try
     try
       JsonResponse :=  LModel.getDataAccount(id);
       TJsonView.SendResponseJsonObject(Res, JsonResponse, 200);
     except on e:exception do
       begin
         WriteLn('Erro em: handlerGetDataAccount ' + e.Message);
         TJsonView.SendError(res, 500, 'Erro interno.');
       end;
     end;
   finally
     FreeAndNil(LModel);
   end;
end;

procedure HandlerUpdateAccounPass(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   RequestJson, horario: TJSONObject;
   LojaDados: TLojaReturn;
   lojaModel: TLojaModel;
begin
  try
     try
       RequestJson := TJSONObject(GetJSON(req.Body));

       LojaDados.nome           := TSecurityService.SanitizeInput(RequestJson.Find('nome'           ).AsString);
       LojaDados.telefone       := TSecurityService.SanitizeInput(RequestJson.Find('telefone'       ).AsString);
       LojaDados.email          := TSecurityService.SanitizeInput(RequestJson.Find('email'          ).AsString);
       LojaDados.id             := TSecurityService.SanitizeInput(RequestJson.Find('id'             ).AsString);
       LojaDados.logradouro     := TSecurityService.SanitizeInput(RequestJson.Find('endereco'       ).AsString);
       LojaDados.uf             := TSecurityService.SanitizeInput(RequestJson.Find('estado'         ).AsString);
       LojaDados.cidade         := TSecurityService.SanitizeInput(RequestJson.find('cidade'         ).AsString);
       LojaDados.cep            := TSecurityService.SanitizeInput(RequestJson.Find('cep'            ).AsString);
       LojaDados.bairro         := TSecurityService.SanitizeInput(RequestJson.Find('bairro'         ).AsString);
       LojaDados.complemento    := TSecurityService.SanitizeInput(RequestJson.Find('complemento'    ).AsString);
       LojaDados.numero         := TSecurityService.SanitizeInput(RequestJson.Find('numero'         ).AsString);
       LojaDados.meta_pixel     := TSecurityService.SanitizeInput(RequestJson.Find('meta_pixel'     ).AsString);
       LojaDados.g_tag          := TSecurityService.SanitizeInput(RequestJson.Find('g_analytics_id' ).AsString);
       LojaDados.insta_str      := TSecurityService.SanitizeInput(RequestJson.find('insta'          ).AsString);
       LojaDados.google_ads_nome:= TSecurityService.SanitizeInput(RequestJson.Find('google_ads_nome').AsString);
       LojaDados.google_ads_id  := TSecurityService.SanitizeInput(RequestJson.Find('google_ads_id'  ).AsString);
       LojaDados.slug           := LowerCase(TSecurityService.SanitizeInput(RequestJson.Find('slug' ).AsString));
       LojaDados.horario_str    := RequestJson.Find('horario' ).AsJSON;

       lojaModel := TLojaModel.Create;

       lojaModel.updateAccount(LojaDados);

     finally
       lojaModel.Free;
       TJsonView.SendResponse(res, TJSONObject(GetJSON(('{"message":"Success"}'))), 200);
       RequestJson.Free;
     end;

  except on e:exception do
  begin
      TJsonView.SendError(res, 500, e.Message);
   end;
  end;
end;

procedure HandleRegisterRoute(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   RequestJson, horario: TJSONObject;
   nome, email, telefone, senha, MsgErro, slug: UTF8String;

   lojaModel: TLojaModel;
   NewlojaId: integer;
begin
  try
    try
        RequestJson := TJSONObject(GetJSON(req.Body));

        nome     := TSecurityService.SanitizeInput(RequestJson.Find('nome'    ).AsString);
        telefone := TSecurityService.SanitizeInput(RequestJson.Find('telefone').AsString);
        email    := TSecurityService.SanitizeInput(RequestJson.Find('email'   ).AsString);
        slug     := TSecurityService.SanitizeInput(LowerCase(RequestJson.Find('slug').AsString));

        horario  := TJSONObject(GetJSON(RequestJson.Find('horario').AsJSON));

        if (nome = '') or (telefone = '') or (email = '') then
        begin
           TJsonView.SendError(res, 400, 'Preencha todos os campos corretamente');
           exit;
        end;

        lojaModel := TLojaModel.Create;

        try
           NewlojaId := LojaModel.createloja(nome, telefone, email, horario.AsJSON, slug);
           if NewlojaId > 0 then
               TJsonView.SendResponse(res, TJSONObject(GetJSON(('{"message":"Registro criado com sucesso."}'))), 200)
           else
               TJsonView.SendError(res, 500, 'Erro ao criar conta: ID inválido retornado.');
        finally
          lojaModel.Free;
          horario.Free;
        end;
    except on e:Exception do
    begin
      MsgErro := E.Message;
      if (Pos('unique', LowerCase(MsgErro)) > 0) or (Pos('duplicate', LowerCase(MsgErro)) > 0) then
      begin
         TJsonView.SendError(Res, 409, 'Já existe uma conta registrada com este Nome, Telefone ou Email.');
      end
      else
      begin
         TJsonView.SendError(Res, 500, 'Erro interno: ' + MsgErro);
      end;
    end;
    end;
  finally
    RequestJson.Free;
  end;
end;

procedure handlerGetSlug(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   jsonreq, jsonres: TJSONObject;
   slug: string;
   slug_bool: Boolean;
   status_code: integer;
begin
   try
     try
       slug := Req.Params['slug'];

       //status_code := TLojaModel.get_slug(slug);

       TJsonView.SendResponse(res, status_code);
     except on e:exception do
       TJsonView.SendError(res, 500, e.Message);
     end;
   finally
     jsonreq.Free;
     jsonres.Free;
   end;
end;

procedure HandleStudio(Req: THorseRequest; Res: THorseResponse);
var
   jsonRes, jsonreq: TJSONObject;

   slug: string;
begin
  try
    try
       jsonreq := TJSONObject(GetJSON(req.Body));

       slug := jsonreq.Find('slug').AsString;

       jsonRes := TLojaModel.GetInfoStudio(slug);

       if Assigned(jsonRes) then
         TJsonView.SendResponseJsonObject(res, jsonRes, 200)
       else
         TJsonView.SendError(res, 404, '{"erro": "Estúdio não encontrado"}');
    except
      on e:exception do
      begin
        TJsonView.SendError(res, 500, e.message);
      end;
    end;
  finally
    jsonreq.Free;
  end;
end;

procedure HandleEndereco(Req: THorseRequest; Res: THorseResponse);
var
   jsonRes, jsonreq: TJSONObject;
   endereco: string;
begin
  try
     jsonreq := TJSONObject(GetJSON(req.Body));

     jsonRes := TLojaModel.get_endereco(jsonreq);

     if Assigned(jsonRes) then
       TJsonView.SendResponseJsonObject(res, jsonRes, 200)
     else
       TJsonView.SendError(res, 400, '{"erro": "CEP não informado"}');
  except
    on e:exception do
    begin
      TJsonView.SendError(res, 500, e.message);
    end;
  end;
end;

procedure HandleSincronizarCache(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  instanceUUID: string;
begin
  // Captura o UUID da instância que veio na URL da requisição
  instanceUUID := req.Params['instance'];

  if instanceUUID = '' then
  begin
    TJsonView.SendError(res, 400, 'O parâmetro instance é obrigatório na URL.');
    Exit;
  end;

  try
    // Atualiza apenas a instância específica na memória, sem travar o servidor
    TCacheService.AtualizarInstancia(instanceUUID);

    // Retorna sucesso mantendo o padrão do seu TJsonView
    TJsonView.SendResponse(res, TJSONObject(GetJSON('{"message":"Cache da instância ' + instanceUUID + ' atualizado com sucesso."}')), 200);
  except
    on E: Exception do
      TJsonView.SendError(res, 500, 'Erro ao atualizar cache: ' + E.Message);
  end;
end;

procedure HandlerUpdateMetaLongToken(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq: TJSONObject;
  id_loja, meta_long_token: string;
  DM: TDataModule1;
begin
  try
    try
      DM := TDataModule1.Create(nil);
      id_loja := DM.GetIdLoja(req.Headers['Authorization']);

      jsonreq := TJSONObject(GetJSON(req.Body));

      meta_long_token := jsonreq.Find('meta_long_token').AsString;

      TLojaModel.UpdateMetaLongToken(id_loja, meta_long_token);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    jsonreq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateMetaAdsId(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq: TJSONObject;
  IdLoja, MetaAdsId: string;
  DM: TDataModule1;
begin
  try
    try
      DM := TDataModule1.Create(nil);
      IdLoja := DM.GetIdLoja(req.Headers['Authorization']);

      jsonreq := TJSONObject(GetJSON(req.Body));

      MetaAdsId := jsonreq.Find('MetaAdsId').AsString;

      TLojaModel.UpdateMetaAdsId(IdLoja, MetaAdsId);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    jsonreq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateMetaPixelId(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  DM: TDataModule1;
  JsonReq: TJSONObject;
  IdLoja, MetaPixelId: string;
begin
  try
    try
      DM := TDataModule1.Create(nil);
      IdLoja := DM.GetIdLoja(req.Headers['Authorization']);

      JsonReq := TJSONObject(GetJSON(req.Body));

      MetaPixelId := JsonReq.Find('MetaPixelId').AsString;

      TLojaModel.UpdateMetaPixelId(IdLoja, MetaPixelId);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    JsonReq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateGoogleAnalyticsId(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  JsonReq: TJSONObject;
  IdLoja, GoogleAnalyticsId: string;
  DM: TDataModule1;
begin
  try
    try
      DM := TDataModule1.Create(nil);

      IdLoja := DM.GetIdLoja(req.Headers['Authorization']);

      JsonReq := TJSONObject(GetJSON(req.Body));

      GoogleAnalyticsId := JsonReq.Find('GoogleAnalyticsId').AsString;

      TLojaModel.UpdateGoogleAnalyticsId(IdLoja, GoogleAnalyticsId);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    JsonReq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateStatusCampanhaMeta(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  IdLoja, StatusCampanhaMeta: String;
  StatusCampanhaMetaBool: Boolean;
  JsonReq: TJSONObject;
  DM: TDataModule1;
begin
  try
    try
      DM := TDataModule1.Create(nil);

      IdLoja := DM.GetIdLoja(req.Headers['Authorization']);

      JsonReq := TJSONObject(GetJSON(req.Body));

      StatusCampanhaMetaBool := JsonReq.Find('StatusCampanhaMeta').AsBoolean;

      TLojaModel.UpdateStatusCampanhaMeta(IdLoja, StatusCampanhaMetaBool);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendError(res, 500, e.Message);
    end;
  finally
    JsonReq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateAccounBasico(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja, nome, apelido: string;
  json_req: TJSONObject;
  id_categoria: integer;
begin
  id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);

  try
    try
      json_req := TJSONObject(GetJSON(req.Body));

      if not  Assigned(json_req) then
      begin
        TJsonView.SendError(res, 400, 'Json invalido');
        exit;
      end;

      nome    := TSecurityService.SanitizeInput(json_req.get('nome',    ''));
      apelido := TSecurityService.SanitizeInput(json_req.get('apelido', ''));

      id_categoria := json_req.Get('id_categoria', 0);

      apelido := TLojaModel.GerarSlug(apelido);

      if TLojaModel.get_slug(apelido, id_loja) then
      begin
        TJsonView.SendResponse(res, 409);
        exit;
      end;

      TLojaModel.UpdateAccounBasico(id_loja, nome, apelido, id_categoria);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno');
        WriteLn('Erro em HandlerUpdateAccounBasico: ' + e.Message);
      end;
    end;
  finally
    if Assigned(json_req) then FreeAndNil(json_req);
  end;
end;

procedure HandlerUpdateAccounContato(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja, telefone, email, instagram: string;
  json_req: TJSONObject;
begin
  json_req := nil;
  try
    try
        id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
        if id_loja = '' then
        begin
          TJsonView.SendError(res, 400, 'Id não informado.');
          exit;
        end;

        json_req := TJSONObject(GetJSON(req.Body));
        if not Assigned(json_req) then
        begin
          TJsonView.SendError(res, 400, 'Json mal formado.');
          exit;
        end;

        telefone := json_req.Find('telefone' ).AsString;
        email    := json_req.Find('email'    ).AsString;
        instagram:= json_req.Find('instagram').AsString;

        TLojaModel.UpdateAccounContato(id_loja, telefone, email, instagram);

        TJsonView.SendSuccess(res);

    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno.');
        WriteLn('Erro em HandlerUpdateAccounContato: ' + e.Message);
      end;
    end;
  finally
    if Assigned(json_req) then FreeAndNil(json_req);
  end;
end;


procedure HandlerUpdateEndereco(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja, cep, endereco,
    numero, bairro, cidade,
    estado, complemento:string;
  jsonReq: TJSONObject;
begin
  jsonReq := nil;
  try
    try
      id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      if (id_loja = '') or (id_loja.IsEmpty) then
      begin
        TJsonView.SendError(res, 400, 'Id não informado.');
        exit;
      end;

      jsonReq := TJSONObject(GetJSON(req.Body));
      if not Assigned(jsonReq) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      cep         := jsonReq.find('cep'        ).AsString;
      endereco    := jsonReq.find('endereco'   ).AsString;
      numero      := jsonReq.find('numero'     ).AsString;
      bairro      := jsonReq.find('bairro'     ).AsString;
      cidade      := jsonReq.find('cidade'     ).AsString;
      estado      := jsonReq.find('estado'     ).AsString;
      complemento := jsonReq.find('complemento').AsString;

      TLojaModel.UpdateEndereco(id_loja, cep, endereco, numero, bairro,
        cidade, estado, complemento);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno.');
        WriteLn('Erro em HandlerUpdateEndereco: ' + e.Message);
      end;
    end;
  finally
    if Assigned(jsonReq) then FreeAndNil(jsonReq);
  end;
end;


procedure HandlerGetEnderecoCep(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  LStatusCode: Integer;

  jsonRes: TJSONObject;
  id_loja, cep, jsonText: string;
begin
  jsonRes := nil;
  try
    cep := req.Params['cep'];

    cep := StringReplace(cep, '-', '', [rfReplaceAll]);
    cep := StringReplace(cep, '.', '', [rfReplaceAll]);

    if Length(cep) <> 8 then
    begin
      TJsonView.SendError(res, 400, 'Informe um CEP válido.');
      Exit;
    end;

    jsonRes := TLojaModel.GetEnderecoCep(cep);
    if not Assigned(jsonRes) then
    begin
      TJsonView.SendError(res, 400, 'Cep não encontrado.');
      exit;
    end;

    TJsonView.SendResponseJsonObject(res, jsonRes, 200);

  except on e:exception do
    begin
      TJsonView.SendError(res, 500, 'Erro interno.');
      WriteLn('Erro em: HandlerGetEnderecoCep - ' + e.Message);
    end;
  end;
end;


procedure HandlerUpdateConfiguracoesAvancadas(req: THorseRequest; res: THorseResponse;
  next: TNextProc);
var
  id_loja,
    g_analytcs,
    meta_pixel_id,
    conta_google_ads,
    horario_str: string;
  jsonReq: TJSONObject;
begin
       jsonReq := nil;

  try
    try
      id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);
      if (id_loja = '') or (id_loja.IsEmpty) then
      begin
        TJsonView.SendError(res, 400, 'Id não informado.');
        exit;
      end;

      jsonReq := TJSONObject(GetJSON(req.Body));
      if not Assigned(jsonReq) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      g_analytcs       := jsonReq.Get('g_analytcs',      '');
      meta_pixel_id    := jsonReq.Get('meta_pixel_id',   '');
      conta_google_ads := jsonReq.Get('conta_google_ads','');

      horario_str      := jsonReq.Find('horario' ).AsJSON;

      TLojaModel.UpdateConfiguracoesAvancadas(id_loja, g_analytcs,
        meta_pixel_id, conta_google_ads, horario_str);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendError(res, 500, 'Erro interno');
        WriteLn('Erro em: HandlerUpdateConfiguracoesAvancadas - '+e.Message);
      end;
    end;
  finally
    FreeAndNil(jsonReq);
  end;
end;


procedure handlerGetCategorias(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonRes: TJSONObject;
  arrayItens: TJSONArray;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    arrayItens := TLojaModel.GetCategorias;
    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);
    TJsonView.SendResponseJsonObject(res, jsonRes, 200);
  except on e: exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      if Assigned(arrayItens) then FreeAndNil(arrayItens);
      TJsonView.SendError(res, 500, 'Erro interno');
      WriteLn('Erro em: handlerGetCategorias - '+e.Message);
    end;
  end;
end;

class procedure TlojaController.RegisterRoutes;
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/portfolio/account/:cep', HandlerGetEnderecoCep);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/account/update_configuracoes_avancadas', HandlerUpdateConfiguracoesAvancadas);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/account/update_endereco',   HandlerUpdateEndereco);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/account/update_account_basico',   HandlerUpdateAccounBasico);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/account/contato',   HandlerUpdateAccounContato);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/account/get_slug/:slug', handlerGetSlug);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .get('api/v1/account/get_data', handlerGetDataAccount);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .get('api/v1/account/get_categorias', handlerGetCategorias);

  THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/update',   HandlerUpdateAccounPass);

     THorse.Post('api/v1/account/register', HandleRegisterRoute);

     THorse.Post('api/v1/public/studio', HandleStudio);

     thorse.post('api/v1/public/endereco', HandleEndereco);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/sincronizar-cache/:instance', HandleSincronizarCache);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/metatoken',   HandlerUpdateMetaLongToken);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/meta_ads_id',   HandlerUpdateMetaAdsId);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/meta_pixel_id',   HandlerUpdateMetaPixelId);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/google_analytics_id',   HandlerUpdateGoogleAnalyticsId);

     THorse.AddCallback(HorseJWT(TConfig.Token))
     .Post('api/v1/account/status_campanha_meta',   HandlerUpdateStatusCampanhaMeta);
end;



end.


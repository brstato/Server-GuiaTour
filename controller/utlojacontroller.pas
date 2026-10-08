unit utlojacontroller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, ulojamodel, uJsonView, fpjson,
  sql_queries, udata, ucacheservice, Horse.JWT, usecurityservice, uconfig,
  uautorizacao;

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
   if not TAutorizacao.ResolverLojaDono(Req, Res, nil, id) then Exit;

   LModel := TLojaModel.Create;
   try
     try
       JsonResponse :=  LModel.getDataAccount(id);
       TJsonView.SendResponseJsonObject(Res, JsonResponse, 200);
     except on e:exception do
       begin
         WriteLn('Erro em: handlerGetDataAccount ' + e.Message);
         TJsonView.SendErrorInternal(res);
       end;
     end;
   finally
     FreeAndNil(LModel);
   end;
end;

procedure HandlerUpdateAccounPass(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   RequestJson, horario: TJSONObject;
   LojaDados: TLojaDados;
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
      TJsonView.SendErroInterno(res, 'utlojacontroller', e);
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
         TJsonView.SendErroInterno(Res, 'HandleRegisterRoute', E);
      end;
    end;
    end;
  finally
    RequestJson.Free;
  end;
end;

procedure handlerGetSlug(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
   slug, idLoja: string;
   slug_bool: Boolean;
begin
   try
     slug := Req.Params['slug'];

     idLoja := TDataModule1.GetIdLoja(req.Headers['Authorization']);

     if TLojaModel.get_slug(slug, idLoja) then
        TJsonView.SendResponse(res, 409)
     else
        TJsonView.SendResponse(res, 200);
   except on e:exception do
     TJsonView.SendErroInterno(res, 'utlojacontroller', e);
   end;
end;

procedure HandleStudio(Req: THorseRequest; Res: THorseResponse);
var
   jsonRes, jsonreq: TJSONObject;
   lJSONData, f: TJSONData;
   slug: string;
begin
  jsonreq := nil;
  try
    try
       lJSONData := GetJSON(req.Body);
       if lJSONData.JSONType <> jtObject then
       begin
         lJSONData.Free;
         TJsonView.SendError(res, 400, 'Json mal formado.');
         Exit;
       end;
       jsonreq := TJSONObject(lJSONData);

       f := jsonreq.Find('slug');
       if not (Assigned(f) and (f.JSONType = jtString)) then
       begin
         TJsonView.SendError(res, 400, 'Informe o slug.');
         Exit;
       end;
       slug := Trim(f.AsString);
       if slug = '' then
       begin
         TJsonView.SendError(res, 400, 'Informe o slug.');
         Exit;
       end;

       jsonRes := TLojaModel.GetInfoStudio(slug);

       if Assigned(jsonRes) then
         TJsonView.SendResponseJsonObject(res, jsonRes, 200)
       else
         TJsonView.SendError(res, 404, 'Estúdio não encontrado.');
    except
      on e:exception do
        TJsonView.SendErroInterno(res, 'HandleStudio', e);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
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
      TJsonView.SendErroInterno(res, 'HandleEndereco', e);
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
      TJsonView.SendErroInterno(res, 'HandleSincronizarCache', E);
  end;
end;

procedure HandlerUpdateMetaLongToken(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  jsonreq: TJSONObject;
  lJSONData, f: TJSONData;
  id_loja, meta_long_token: string;
  DM: TDataModule1;
begin
  jsonreq := nil;
  DM := nil;
  try
    try
      DM := TDataModule1.Create(nil);
      id_loja := DM.GetIdLoja(req.Headers['Authorization']);
      if id_loja = '' then
      begin
        TJsonView.SendError(res, 401, 'Não autenticado.');
        Exit;
      end;

      lJSONData := GetJSON(req.Body);
      if lJSONData.JSONType <> jtObject then
      begin
        lJSONData.Free;
        TJsonView.SendError(res, 400, 'Json mal formado.');
        Exit;
      end;
      jsonreq := TJSONObject(lJSONData);

      f := jsonreq.Find('meta_long_token');
      if not (Assigned(f) and (f.JSONType = jtString)) then
      begin
        TJsonView.SendError(res, 400, 'Informe o meta_long_token.');
        Exit;
      end;
      meta_long_token := Trim(f.AsString);

      TLojaModel.UpdateMetaLongToken(id_loja, meta_long_token);

      TJsonView.SendSuccess(res);
    except on e:exception do
      TJsonView.SendErroInterno(res, 'HandlerUpdateMetaLongToken', e);
    end;
  finally
    if Assigned(jsonreq) then jsonreq.Free;
    if Assigned(DM) then DM.Free;
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
      TJsonView.SendErroInterno(res, 'utlojacontroller', e);
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
      TJsonView.SendErroInterno(res, 'utlojacontroller', e);
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
      TJsonView.SendErroInterno(res, 'utlojacontroller', e);
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
      TJsonView.SendErroInterno(res, 'utlojacontroller', e);
    end;
  finally
    JsonReq.Free;
    DM.Free;
  end;
end;


procedure HandlerUpdateAccounBasico(req: THorseRequest; res: THorseResponse; next: TNextProc);
var
  id_loja, nome, apelido: string;
  json_req: TJSONObject;
  id_categoria: integer;
begin
  try
    try
      json_req := TJSONObject(GetJSON(req.Body));

      if not Assigned(json_req) then
      begin
        TJsonView.SendError(res, 400, 'Json invalido');
        exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, json_req, id_loja) then Exit;

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
        TJsonView.SendErrorInternal(res);
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
  lJSONData: TJSONData;
begin
  json_req := nil;
  try
    try
        lJSONData := GetJSON(req.Body);
        if lJSONData.JSONType <> jtObject then
        begin
          lJSONData.Free;
          TJsonView.SendError(res, 400, 'Json mal formado.');
          exit;
        end;
        json_req := TJSONObject(lJSONData);

        if not TAutorizacao.ResolverLojaDono(req, res, json_req, id_loja) then Exit;

        // os três campos são obrigatórios: se faltar um, recusa (não grava vazio por cima)
        if not (Assigned(json_req.Find('telefone')) and
                Assigned(json_req.Find('email')) and
                Assigned(json_req.Find('instagram'))) then
        begin
          TJsonView.SendError(res, 400, 'Informe telefone, email e instagram.');
          exit;
        end;

        // sanitizados: o instagram e o telefone vão para a página pública (inclusive dentro de <script>)
        telefone := TSecurityService.SanitizeInput(Trim(json_req.Get('telefone',  '')));
        email    := TSecurityService.SanitizeInput(Trim(json_req.Get('email',     '')));
        instagram:= TSecurityService.SanitizeInput(Trim(json_req.Get('instagram', '')));

        TLojaModel.UpdateAccounContato(id_loja, telefone, email, instagram);

        TJsonView.SendSuccess(res);

    except on e:exception do
      begin
        TJsonView.SendErrorInternal(res);
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
    estado, complemento, latitude, longitude:string;
  jsonReq: TJSONObject;
begin
  jsonReq := nil;
  try
    try
      jsonReq := TJSONObject(GetJSON(req.Body));
      if not Assigned(jsonReq) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonReq, id_loja) then Exit;

      cep         := TSecurityService.SanitizeInput(Trim(jsonReq.Get('cep',         '')));
      endereco    := TSecurityService.SanitizeInput(Trim(jsonReq.Get('endereco',    '')));
      numero      := TSecurityService.SanitizeInput(Trim(jsonReq.Get('numero',      '')));
      bairro      := TSecurityService.SanitizeInput(Trim(jsonReq.Get('bairro',      '')));
      cidade      := TSecurityService.SanitizeInput(Trim(jsonReq.Get('cidade',      '')));
      estado      := TSecurityService.SanitizeInput(Trim(jsonReq.Get('estado',      '')));
      complemento := TSecurityService.SanitizeInput(Trim(jsonReq.Get('complemento', '')));
      latitude    := TSecurityService.SanitizeInput(Trim(jsonReq.Get('latitude',    '')));
      longitude   := TSecurityService.SanitizeInput(Trim(jsonReq.Get('longitude',   '')));

      TLojaModel.UpdateEndereco(id_loja, cep, endereco, numero, bairro,
        cidade, estado, complemento, latitude, longitude);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendErrorInternal(res);
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
      TJsonView.SendErrorInternal(res);
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
      jsonReq := TJSONObject(GetJSON(req.Body));
      if not Assigned(jsonReq) then
      begin
        TJsonView.SendError(res, 400, 'Json mal formado.');
        exit;
      end;

      if not TAutorizacao.ResolverLojaDono(req, res, jsonReq, id_loja) then Exit;

      g_analytcs       := jsonReq.Get('g_analytcs',      '');
      meta_pixel_id    := jsonReq.Get('meta_pixel_id',   '');
      conta_google_ads := jsonReq.Get('conta_google_ads','');

      horario_str      := jsonReq.Find('horario' ).AsJSON;

      TLojaModel.UpdateConfiguracoesAvancadas(id_loja, g_analytcs,
        meta_pixel_id, conta_google_ads, horario_str);

      TJsonView.SendSuccess(res);
    except on e:exception do
      begin
        TJsonView.SendErrorInternal(res);
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
      TJsonView.SendErrorInternal(res);
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

  // DESATIVADA: HandlerUpdateAccounPass usa o id da loja vindo do body, sem conferir
  // o dono (qualquer usuário logado alteraria outra loja). O painel não usa esta rota.
  // Se um dia precisar dela, reescreva o handler com TAutorizacao.ResolverLojaDono.
  // THorse.AddCallback(HorseJWT(TConfig.Token))
  //    .Post('api/v1/account/update',   HandlerUpdateAccounPass);

     // DESATIVADA: rota pública que criava loja sem login (abuso de cadastro e de slugs).
     // O painel não usa. O cadastro é feito pelo vendedor ou pelo login com Google.
     // THorse.Post('api/v1/account/register', HandleRegisterRoute);

     // DESATIVADA (rota pública do Inkers, sem uso)
     // THorse.Post('api/v1/public/studio', HandleStudio);

     thorse.post('api/v1/public/endereco', HandleEndereco);

     // DESATIVADAS (herdadas do Inkers, sem uso no painel). Pixel e Analytics são
     // salvos por account/update_configuracoes_avancadas.
     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/sincronizar-cache/:instance', HandleSincronizarCache);

     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/metatoken',   HandlerUpdateMetaLongToken);

     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/meta_ads_id',   HandlerUpdateMetaAdsId);

     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/meta_pixel_id',   HandlerUpdateMetaPixelId);

     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/google_analytics_id',   HandlerUpdateGoogleAnalyticsId);

     // THorse.AddCallback(HorseJWT(TConfig.Token))
     // .Post('api/v1/account/status_campanha_meta',   HandlerUpdateStatusCampanhaMeta);
end;



end.


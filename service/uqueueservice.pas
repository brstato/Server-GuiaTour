unit uQueueService;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, SyncObjs,
  uAssistenteIaModel, ugetdata, uAssistenteIaDAO, uNetService, fpjson, jsonparser;

type
  { Thread que processa as mensagens em segundo plano }

  { TQueueThread }

  TQueueThread = class(TThread)
  private
    FQueue: TObjectList<TAssistantMessage>;
    FLock: TCriticalSection;
    FTextoLog: string;
    procedure AtualizarTelaSeguro;
    procedure ProcessarMensagens;

    { Funções auxiliares para IA e WhatsApp }
    function MontarPromptSistema(AMsg: TAssistantMessage): string;
    procedure EnviarRespostaWhatsApp(AInstance, ANumero, ATexto: string);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AdicionarAFila(AMsg: TAssistantMessage);
  end;

  { Singleton para acesso global no Controller }
  TQueueService = class
  private
    class var FInstance: TQueueThread;
    class function GetInstance: TQueueThread; static;
  public
    class property Instance: TQueueThread read GetInstance;
  end;

implementation

uses
 uconfig;

{ TQueueService }

class function TQueueService.GetInstance: TQueueThread;
begin
  if FInstance = nil then
    FInstance := TQueueThread.Create;
  Result := FInstance;
end;

{ TQueueThread }

constructor TQueueThread.Create;
begin
  inherited Create(False); // Inicia a thread imediatamente
  FQueue := TObjectList<TAssistantMessage>.Create(True); // True = Deleta o objeto ao remover da lista
  FLock  := TCriticalSection.Create;
  FreeOnTerminate := False;
end;

destructor TQueueThread.Destroy;
begin
  Terminate;
  WaitFor; // Aguarda a thread finalizar antes de destruir os objetos
  FQueue.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TQueueThread.AdicionarAFila(AMsg: TAssistantMessage);
begin
  FLock.Enter;
  try
    FQueue.Add(AMsg);
  finally
    FLock.Leave;
  end;
end;

function TQueueThread.MontarPromptSistema(AMsg: TAssistantMessage): string;
begin
  Result := 'Você é o assistente virtual de um tatuador veterano (seu nome: ' + AMsg.NomeAssistente + ').' + sLineBreak +
            'Sua linguagem é de estúdio de tattoo: parceira, informal, direta e sem textos longos.' + sLineBreak +
            
            'REGRA DE TRANSBORDO (MUITO IMPORTANTE):' + sLineBreak +
            'Se o cliente pedir explicitamente para falar com o tatuador, tirar uma dúvida técnica complexa (como coberturas), '+
            'ou se recusar a passar os dados, PAUSE o atendimento.' + sLineBreak +
            'Para isso, comece sua resposta OBRIGATORIAMENTE com a tag [CHAMAR_HUMANO].' + sLineBreak +
            'Ex: "[CHAMAR_HUMANO] Pode deixar, vou chamar alguem para te ajudar ' + 
            ' aqui pra dar uma olhada nisso com você!"' + sLineBreak + sLineBreak +
            
            'REGRAS DE ESTIMATIVA DE TEMPO (Baseado em Realismo Preto e Cinza ou colorido):' + sLineBreak +
            '- Pequenos/Simples (até 10cm, traços ou blocos sólidos): 1 a 3 horas.' + sLineBreak +
            '- Médios (10cm a 20cm, sombreamento moderado): 4 a 8 horas.' + sLineBreak +
            '- Grandes/Complexos (20cm a 30cm, fechamento de antebraço/panturrilha, rostos, texturas): 12 a 16 horas.' + sLineBreak +
            '- Projetos Gigantes (braço/perna/costas inteiras): 30 a 50+ horas.' + sLineBreak + sLineBreak +
            
            'REGRAS RÍGIDAS DE CONTINUIDADE (LEIA O HISTÓRICO ANTES DE RESPONDER):' + sLineBreak +
            '1. PROIBIDO REPETIR SAUDAÇÃO: Se o histórico mostra que você já deu oi/bom dia, NÃO repita a saudação. Vá direto ao assunto.' + sLineBreak +
            '2. TRAVA DA FASE 2 PARA FASE 3: Olhe para a SUA última mensagem no histórico. Se você acabou de perguntar o local, tamanho e alterações, a sua ÚNICA ação agora é calcular o orçamento (Fase 3). Não volte fases.' + sLineBreak + sLineBreak +
            
            'COMO CONDUZIR A CONVERSA (Siga as Fases Rigorosamente):' + sLineBreak +
            'FASE 1 - Saudação: Se a mensagem for só cumprimento (Ex: Oi, Bom dia), responda o cumprimento e se apresente com seu nome. Em seguida, pergunte se o cliente deseja iniciar um orçamento ou prefere falar com um humano. AGUARDE a resposta antes de prosseguir.' + sLineBreak +
            'FASE 2 - Coleta de Dados: Ao receber a ideia/imagem, ELOGIE e ANALISE visualmente. Se a imagem JÁ MOSTRAR o local (ex: um mockup no peito/braço), deduza o local e NÃO pergunte. Pergunte APENAS o que falta: 1) Tamanho exato em cm. 2) Se haverá alterações na arte. NUNCA dê estimativas de horas ou valores nesta fase.' + sLineBreak +
            'FASE 3 - Orçamento: APENAS após o cliente responder tamanho e alterações, estime o tempo e calcule o valor exato: (Horas estimadas x R$ ' + FormatFloat('0.00', AMsg.ValorHora) + '). Se passar de 6 horas, dívida o valor total em múltiplas sessões (Ex: 2 sessões de R$ X).' + sLineBreak +
            'FASE 4 - Fechamento Suave: Após dar o preço, NÃO force o pagamento imediato. Meça o interesse abrindo a porta para a agenda. Exemplo: "O que achou da proposta? Se o valor ficar bacana pra você, a gente já vê as datas livres na agenda. Me dá um toque!"' + sLineBreak;

  if AMsg.ContextoHistorico <> '' then
  begin
    Result := Result + sLineBreak + '---- INÍCIO DO HISTÓRICO DA CONVERSA ----' + sLineBreak +
              AMsg.ContextoHistorico + sLineBreak +
              '---- FIM DO HISTÓRICO DA CONVERSA ----' + sLineBreak + 
              sLineBreak + 'Como "Assistente", escreva apenas a sua próxima resposta para continuar a conversa acima considerando a mensagem atual do cliente abaixo.' + sLineBreak +
              'Mensagem atual do cliente: ' + AMsg.Content;
  end
  else
    Result := Result + sLineBreak + 'Mensagem atual do cliente: ' + AMsg.Content;
end;

procedure TQueueThread.EnviarRespostaWhatsApp(AInstance, ANumero, ATexto: string);
var
  LBody: TJSONObject;
  LStatus: Integer;
  LURL: string;
begin
  LBody := TJSONObject.Create;
  try
    LBody.Add('number', StringReplace(ANumero, '@s.whatsapp.net', '', []));
    LBody.Add('text', ATexto);

    LURL := 'http://100.72.176.93:8080/message/sendText/' + AInstance;

    TNetService.post(LURL, 'apikey', TConfig.ConfigValue('services', 'internal_apikey', ''), LBody.AsJSON, LStatus);
  finally
    LBody.Free;
  end;
end;

procedure TQueueThread.AtualizarTelaSeguro;
begin
    //if assigned(form1) then
    //    form1.logmessage(ftextolog);
end;

procedure TQueueThread.ProcessarMensagens;
var
  lMsg: TAssistantMessage;
  vPrompt, vRespostaIA: string;
begin
  while True do
  begin
    lMsg := nil;

    FLock.Enter;
    try
      if FQueue.Count > 0 then
      begin
        lMsg := FQueue[0];
        FQueue.Extract(lMsg);
      end;
    finally
      FLock.Leave;
    end;

    if Assigned(lMsg) then
    begin
      try
        FTextoLog := 'Processando msg de: ' + lMsg.WhatsAppId;
        Synchronize(AtualizarTelaSeguro);

        vPrompt := MontarPromptSistema(lMsg);
        vRespostaIA := TNetService.getGeminiMultimodal(vPrompt, lMsg.Base64Data, lMsg.MimeType);

        // --- DISJUNTOR DA IA: INTERCEPTA A TAG DE TRANSBORDO ---
        if Pos('[CHAMAR_HUMANO]', vRespostaIA) > 0 then
        begin
          // Desliga o bot no banco para este contato
          TMensagemDAO.DesativarBotParaContato(lMsg.InstanciaId, lMsg.WhatsAppId);

          // Remove a tag para o cliente ler uma mensagem limpa
          vRespostaIA := StringReplace(vRespostaIA, '[CHAMAR_HUMANO]', '', [rfReplaceAll]);
          vRespostaIA := Trim(vRespostaIA);

          FTextoLog := '⚠️ Bot pausado! Cliente transferido para o humano.';
          Synchronize(AtualizarTelaSeguro);
        end;
        // -------------------------------------------------------

        FTextoLog := '🤖 [IA]: ' + vRespostaIA;
        Synchronize(AtualizarTelaSeguro);

        if (vRespostaIA <> '') and (Pos('Erro IA', vRespostaIA) = 0) then
        begin
           EnviarRespostaWhatsApp(lMsg.InstanciaId, lMsg.WhatsAppId, vRespostaIA);

           lMsg.Content := vRespostaIA;
           lMsg.Role    := 'assistant';
           TMensagemDAO.Inserir(lMsg);
        end;

        WriteLn('Mensagem processada para Instance: ' + lMsg.InstanciaId);
      finally
        lMsg.Free;
      end;
    end
    else
      Break;
  end;
end;
procedure TQueueThread.Execute;
begin
  while not Terminated do
  begin
    ProcessarMensagens; // Mantido o nome exato
    Sleep(1000); // Aguarda 1 segundo antes de verificar a fila novamente
  end;
end;

initialization

finalization
  if TQueueService.FInstance <> nil then
    TQueueService.FInstance.Free;

end.

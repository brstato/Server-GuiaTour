# Backend Pascal (Server-GuiaTour) — instruções de alteração

Para o agente de código. Aplique **na ordem** (as partes 1 e 2 são segurança e vêm antes das funcionalidades).
Cada seção diz **ARQUIVO**, **AÇÃO** e traz o trecho. Compile no Lazarus ao fim de cada parte.

## 0. Antes de começar

- **Não altere o banco.** A coluna `VENDEDOR.ADM` (`BOOLEAN NOT NULL DEFAULT FALSE`) já foi criada pelo usuário.
- Units **novas** vão em `service/` (já está no caminho de units do `.lpi`). **Não** precisa editar `.lpi` nem `.lpr`.
- Mantenha as convenções do projeto: `{$mode delphi}{$H+}`, `TGetData.getData` com SQL começando em `SELECT`, sem CTE, parâmetros posicionais na ordem em que aparecem no SQL.
- **Nunca** escreva `}` dentro de um comentário `{ ... }` (fecha o comentário no meio e quebra a compilação).
- Colunas que o SQL novo usa (você não tem acesso ao banco, então confie nesta lista):

| Tabela | Colunas usadas |
|---|---|
| `VENDEDOR` | `ID`, `UUID`, `NOME`, `ATIVO` (bool), `ADM` (bool) |
| `LOJA` | `ID`, `UUID`, `NOME`, `SLUG`, `TELEFONE`, `EMAIL`, `CIDADE`, `UF`, `VALIDADE` (date), `ID_CATEGORIA`, `ID_VENDEDOR` |
| `CATEGORIA` / `CATEGORIA_PONTO_TURISTICO` | `ID`, `NOME` |
| `PONTO_TURISTICO` | `ID`, `UUID`, `NOME`, `SLUG`, `ATIVO`, `CIDADE`, `UF`, `ID_CATEGORIA`, `ID_VENDEDOR` |
| `SITE` | `ID`, `ID_LOJA_EX` (= `LOJA.UUID`) |
| `SITE_GALERIA` | `ID`, `ID_SITE`, `URL_FOTO` |
| `ASAAS_ASSINATURA` | `ID`, `LOJA_ID` (= `LOJA.ID`), `STATUS`, `BILLING_TYPE`, `VALOR` |
| `LOG_ACAO_VENDEDOR` | `ID_VENDEDOR` (int), `ID_LOJA` (= `LOJA.UUID`), `ACAO` (até 50 caracteres) |

## Resumo

| Parte | O que é | Arquivos |
|---|---|---|
| **1.1** | **CRÍTICO** — upload escreve fora de `uploads/` (sobrescreve `config.ini`) | `uarquivoseguro` (novo), `uportifoliomodel`, `uvendedormodel` |
| **1.2** | **CRÍTICO** — qualquer usuário logado lê e altera qualquer loja | `uautorizacao` (novo), `udata`, `utlojacontroller`, `uportifoliocontroller`, `utpontoscontroller` |
| **1.3** | Vendedor desativado continua com acesso | `uloginmodel`, `utvendedorcontroller`, `utpontoscontroller` |
| **2** | Administração geral (só vendedor `ADM`) | `uadminmodel` (novo), `utadmincontroller` (novo), `urouter` |
| **3** | Administrador gera cobrança de qualquer loja | `utasaascontroller` |
| **4** | Cache público em rota autenticada | `utpontoscontroller` |
| **5** | Checklist de verificação | — |

---

# PARTE 1 — SEGURANÇA (fazer primeiro)

## 1.1 Upload de arquivo: o nome do cliente escapa de `uploads/` (CRÍTICO)

**Problema.** O nome do arquivo vem do cliente e é concatenado no caminho:
`ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo)`.
Com `nome_arquivo = "/../../resources/config.ini"` o servidor grava **fora** de `uploads/` e sobrescreve o `config.ini` (segredo do JWT, banco, webhook) com o conteúdo que o atacante enviou. `TSecurityService.SanitizeInput` não ajuda (só remove `<script>`/`<style>`). Qualquer usuário logado, inclusive vendedor terceirizado, consegue.

**Solução.** Nunca usar o nome do cliente. O nome final é gerado no servidor (`PREFIXO_GUID.ext`) e a extensão sai dos **bytes** da imagem (JPEG/PNG/WEBP). Assim foto de iPhone chamada `IMG_1.HEIC`, já convertida para JPEG pelo front, continua funcionando.

### 1.1.1 ARQUIVO NOVO `service/uarquivoseguro.pas`
Copie o código do **Anexo A**.

### 1.1.2 ARQUIVO `model/uportifoliomodel.pas`
1. No `uses`, acrescente `uarquivoseguro`.
2. Em **4 funções** — `UpdateFotoCapa`, `UpdateAvatar`, `UpdateFotoBio`, `UploadFoto` — faça duas coisas:
   - **a)** logo depois do `begin` da função (**antes** do `try`), valide e prepare a imagem;
   - **b)** apague as linhas que montavam `caminho_salvar`/`url_banco`/`DecodedStr` com o nome do cliente.

**a) Inserir logo após o `begin` (antes do `try`):**

```pascal
  // Valida a imagem ANTES de tudo, fora do try (nada a liberar se recusar). O nome que o
  // cliente mandou NÃO é usado: o arquivo é gravado como ID_GUID.ext, ext pelos bytes.
  if not TArquivoSeguro.Preparar(id_loja, base64_str, caminho_salvar, url_banco, DecodedStr) then
    raise Exception.Create('Imagem inválida: envie JPEG, PNG ou WEBP de até 8 MB.');
  dataset := nil;        // só em UpdateAvatar e UpdateFotoBio (UpdateFotoCapa já faz isso)
  StringStream := nil;   // idem
```
Em `UploadFoto` o parâmetro se chama `base64Str` (não `base64_str`) e **não** há `dataset`:

```pascal
  if not TArquivoSeguro.Preparar(id_loja, base64Str, caminho_salvar, url_banco, DecodedStr) then
    raise Exception.Create('Imagem inválida: envie JPEG, PNG ou WEBP de até 8 MB.');
  StringStream := nil;
```

**b) Apagar (dentro do `try`) — exemplo de `UpdateAvatar`:**

```pascal
// ANTES (apagar estas 4 linhas)
    caminho_salvar := ExpandFileName('./uploads/' + id_loja + '_' + nome_arquivo);
    url_banco      := '/imagens/' + id_loja + '_' + nome_arquivo;

    DecodedStr := DecodeStringBase64(base64_str);

// DEPOIS: nada no lugar. O resto continua igual
// (StringStream := TStringStream.Create(DecodedStr); StringStream.SaveToFile(caminho_salvar); ...)
```
Em `UploadFoto` apague também a linha `url_relativa := 'uploads/' + id_loja + '_' + nome;`.

> **Não mexa em `SaveDepoimento`**: já é seguro (nome gerado no servidor e checagem dos bytes).

### 1.1.3 ARQUIVO `model/uvendedormodel.pas` (função `CriarComercio`)
1. No `uses`, acrescente `uarquivoseguro`.
2. Inicialize `StringStream := nil;` junto de `dataSet := nil;` (hoje ela é liberada no `finally` sem ser inicializada).
3. **Antes do `INSERT INTO loja`** (logo depois de calcular `uuidString`), valide as 3 imagens. Vazia = sem imagem. Assim, se alguma for inválida, **nada** é gravado, nem a loja:

```pascal
      if (vendor.avatar <> '') and not TArquivoSeguro.Preparar(uuidString, vendor.avatar,
           caminho_salvar_avatar, url_banco_avatar, DecodedStrAvatar) then
        raise Exception.Create('Avatar inválido: envie JPEG, PNG ou WEBP de até 8 MB.');
      if (vendor.foto_bio <> '') and not TArquivoSeguro.Preparar(uuidString, vendor.foto_bio,
           caminho_salvar_fotobio, url_banco_fotobio, DecodedStrFotoBio) then
        raise Exception.Create('Foto da bio inválida: envie JPEG, PNG ou WEBP de até 8 MB.');
      if (vendor.foto_capa <> '') and not TArquivoSeguro.Preparar(uuidString, vendor.foto_capa,
           caminho_salvar_fotocapa, url_banco_fotocapa, DecodedStrFotocapa) then
        raise Exception.Create('Foto de capa inválida: envie JPEG, PNG ou WEBP de até 8 MB.');
```

4. Onde hoje se monta caminho e se grava avatar, bio e capa, troque cada bloco por (exemplo do avatar; repita para `fotobio`/`DecodedStrFotoBio` e `fotocapa`/`DecodedStrFotocapa`):

```pascal
// ANTES (apagar)
      caminho_salvar_avatar := ExpandFileName('./uploads/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar);
      url_banco_avatar      := '/imagens/' + uuidString + '_' + vendor.nome_arquivo_foto_avatar;

      DecodedStrAvatar := DecodeStringBase64(vendor.avatar);
      StringStream := TStringStream.Create(DecodedStrAvatar);
      StringStream.SaveToFile(caminho_salvar_avatar);
      FreeAndNil(StringStream);

// DEPOIS
      if caminho_salvar_avatar <> '' then
      begin
        StringStream := TStringStream.Create(DecodedStrAvatar);
        StringStream.SaveToFile(caminho_salvar_avatar);
        FreeAndNil(StringStream);
      end;
```

5. No laço dos `trabalhos`, troque a montagem do caminho (foto inválida é ignorada; nada é gravado):

```pascal
// ANTES (apagar as 3 primeiras instruções, até DecodedStr := ...)
           caminho_salvar := ExpandFileName('./uploads/' + uuidString + '_' + itemTrabalho.Strings['nome_arquivo']);
           url_banco      := '/imagens/' + uuidString + '_' + itemTrabalho.Strings['nome_arquivo'];

           DecodedStr := DecodeStringBase64(itemTrabalho.Strings['itemTrabalho']);

// DEPOIS
           if not TArquivoSeguro.Preparar(uuidString, itemTrabalho.Strings['itemTrabalho'],
                caminho_salvar, url_banco, DecodedStr) then
             Continue;
           StringStream := TStringStream.Create(DecodedStr);
           // (as linhas seguintes — SaveToFile, FreeAndNil, INSERT em site_galeria — ficam iguais)
```

**Comportamento novo (esperado):** o nome enviado pelo cliente é ignorado; o arquivo vira `uuid_GUID.jpg|png|webp`; avatar/bio/capa vazios gravam `''` no banco (antes gravavam `'/imagens/<uuid>_'`, uma imagem quebrada).

---

## 1.2 Controle de acesso por loja: qualquer usuário logado lê e altera qualquer loja (CRÍTICO)

**Problema.** Rotas de loja e portfólio pegam o id da loja do **corpo** (`TDataModule1.GetTargetIdLoja`) ou da **query** (`id_loja`) e operam nela **sem conferir o dono**. Qualquer usuário logado (loja ou vendedor terceirizado):
- **lê** qualquer loja em `GET account/get_data?id_loja=X`, e a resposta traz o `meta_long_token` (token do Meta/Facebook, segredo);
- **altera** nome, slug, contato, endereço, horários, Google/Meta ads e fotos de qualquer loja;
- **anexa** fotos no `SITE` de outra loja (o `id_site` vem do cliente) e **apaga** fotos de qualquer loja (`portfolio/remove` por id sequencial).

**Solução.** Uma unit única decide o acesso, sempre no banco e **falhando fechado** (erro de banco nunca libera):
- token `loja`: só a própria loja; qualquer `id_loja` enviado é **ignorado**;
- token `vendedor`: precisa estar **ativo** e ser o **dono** da loja;
- qualquer outro tipo: 403.

### 1.2.1 ARQUIVOS NOVOS / ADIÇÕES
- **NOVO** `service/uautorizacao.pas` → código no **Anexo B**.
- **`model/uadminmodel.pas`** (novo, Parte 2) → já traz `VendedorAtivo`, `VendedorAdmin`, `SiteDaLoja` e `LojaDaFoto`, que a `uautorizacao` usa. Crie-o agora (**Anexo C**).

### 1.2.2 ARQUIVO `data/udata.pas`
**Apague** `GetTargetIdLoja` (a declaração na classe **e** a implementação). Depois de trocar todos os pontos abaixo, o compilador acusa qualquer uso que sobrar. Isso é proposital.

### 1.2.3 Trocar os pontos de uso
Dois padrões. Em cada handler, **apague** a linha antiga e **ponha** a nova (o 3º argumento é a variável do corpo JSON que o handler já usa: `jsonreq`, `json_req` ou `jsonReq`).

**Padrão A: id vindo do corpo (escrita)**

```pascal
// ANTES
id_loja := TDataModule1.GetTargetIdLoja(req.Headers['Authorization'], jsonreq);

// DEPOIS
if not TAutorizacao.ResolverLojaDono(req, res, jsonreq, id_loja) then Exit;
```

**Padrão B: id vindo da query (leitura)**

```pascal
// ANTES
id_loja := req.Query['id_loja'];
if id_loja = '' then
  id_loja := TDataModule1.GetIdLoja(req.Headers['Authorization']);

// DEPOIS
if not TAutorizacao.ResolverLojaDono(req, res, nil, id_loja) then Exit;
```

| Arquivo | Handler | Padrão |
|---|---|---|
| `uportifoliocontroller.pas` | `HandlePortifolioUpdate` | A |
| `uportifoliocontroller.pas` | `HandlerPortifolioGetInfo` | B |
| `uportifoliocontroller.pas` | `HandleUploadFoto` | A **+ 1.2.4** |
| `uportifoliocontroller.pas` | `HandleUpdateAvatar` | A |
| `uportifoliocontroller.pas` | `HandleUpdateFotoBio` | A |
| `uportifoliocontroller.pas` | `HandlePortifolioUpdateBasico` | A |
| `uportifoliocontroller.pas` | `HandleUpdateFotoCapa` | A |
| `uportifoliocontroller.pas` | `HandleRemoveItem` | **1.2.5** |
| `utlojacontroller.pas` | `handlerGetDataAccount` (variável `id`, parâmetros `Req, Res`) | B |
| `utlojacontroller.pas` | `HandlerUpdateAccounBasico` | A |
| `utlojacontroller.pas` | `HandlerUpdateAccounContato` | A |
| `utlojacontroller.pas` | `HandlerUpdateEndereco` | A |
| `utlojacontroller.pas` | `HandlerUpdateConfiguracoesAvancadas` | A |

No `uses` de **`uportifoliocontroller.pas`** acrescente `uautorizacao, uadminmodel`; no de **`utlojacontroller.pas`**, `uautorizacao`.

> Os outros handlers de `utlojacontroller` que usam `DM.GetIdLoja(token)` (sincronizar cache etc.) só leem o id do **token**: não mexa.
> Não mexa em `HandleGetGaleria` (as fotos da galeria já são públicas na página da loja).

### 1.2.4 `HandleUploadFoto`: o `id_site` vem do cliente
Logo antes de `TProtifolioModel.UploadFoto(...)`:

```pascal
      // id_site vem do cliente: só aceita o site desta mesma loja
      if not TAdminModel.SiteDaLoja(id_site, id_loja) then
      begin
        TJsonView.SendError(res, 403, 'Este site não pertence a esta loja.');
        Exit;
      end;

      TProtifolioModel.UploadFoto(id_site, nome_arquivo, base64_str, id_loja);
```

### 1.2.5 `HandleRemoveItem`: o id da foto é sequencial
Logo antes de `TProtifolioModel.RemoveItem(id);`:

```pascal
      // id da foto é sequencial: confere se a foto é de uma loja que o chamador pode alterar
      if not TAutorizacao.ExigirAcessoAFoto(req, res, id) then Exit;

      TProtifolioModel.RemoveItem(id);
```

### 1.2.6 ARQUIVO `utpontoscontroller.pas`: rota duplicada e sem autorização
Existe um segundo `HandlerRemoveItem` (chama `TPontoTuristicoModel.RemoveItem(id)` **sem nenhuma checagem**) registrado na mesma rota `api/v1/portfolio/remove`. O front só usa essa rota para fotos de **loja**; as fotos de ponto turístico usam `DELETE vendedor/ponto-turistico/:uuid/galeria/:idFoto` (que já confere o dono). **Apague** o procedimento `HandlerRemoveItem` inteiro **e** esta linha de `RegisterRoutes`:

```pascal
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Post('api/v1/portfolio/remove', HandlerRemoveItem);
```

---

## 1.3 Vendedor desativado continua com acesso

**Problema.** A renovação do token do vendedor não confere `ativo`, e cada renovação vale 1 mês: desativar um vendedor (por exemplo um terceirizado que saiu) **não revoga** nada. Além disso, as rotas de vendedor só olham o `tipo` do JWT.

### 1.3.1 ARQUIVO `model/uloginmodel.pas` (função `updateRefreshToken`)
Uma linha no SQL do vendedor:

```pascal
// ANTES
'select expire from vendedor where refresh_token = :refresh_token and uuid = :uuid',
// DEPOIS
'select expire from vendedor where refresh_token = :refresh_token and uuid = :uuid and ativo = TRUE',
```

### 1.3.2 ARQUIVO `controller/utvendedorcontroller.pas`
1. `uses`: acrescente `uautorizacao`.
2. Em **`ExigirDonoDaLoja`**, **`HandlerListarComercios`** e **`HandlerCriarComercio`**, troque o bloco que lê `tipo` e `idVendedor` por **uma linha**:

```pascal
// ANTES (nos 3 lugares)
tipo := TDataModule1.GetTipoUsuario(Req.Headers['Authorization']);
if tipo <> 'vendedor' then
begin
  TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
  Exit;
end;
idVendedor := TDataModule1.GetIdLoja(Req.Headers['Authorization']);

// DEPOIS
if not TAutorizacao.ExigirVendedorAtivo(Req, Res, idVendedor) then Exit;
```
Remova a variável `tipo` das declarações. Em `HandlerCriarComercio` declare `idVendedor: string` no lugar de `tipo` e use `vendorList.idVendedor := idVendedor;`.

### 1.3.3 ARQUIVO `controller/utpontoscontroller.pas`
1. `uses`: acrescente `uautorizacao`.
2. Troque o corpo inteiro de `ExigirVendedor` (todas as rotas de vendedor de pontos passam por ela):

```pascal
function ExigirVendedor(Req: THorseRequest; Res: THorseResponse;
        out idVendedor: string): Boolean;
begin
  // tipo vendedor E ativo agora (o JWT pode ser de antes de o vendedor ser desativado)
  Result := TAutorizacao.ExigirVendedorAtivo(Req, Res, idVendedor);
end;
```

---

# PARTE 2 — ADMINISTRAÇÃO GERAL (só vendedor administrador)

Vendedor com `ADM = TRUE` **e** `ATIVO = TRUE` vê todas as lojas, todos os pontos turísticos e as mensalidades vencidas / por vencer. Vendedor terceirizado (`ADM = FALSE`) recebe **403**. A checagem é no banco a cada requisição.

- **NOVO `model/uadminmodel.pas`** → **Anexo C**.
- **NOVO `controller/utadmincontroller.pas`** → **Anexo D**. Rotas (todas `GET`, com JWT):
  - `api/v1/vendedor/perfil` devolve `{"adm": true|false}` para qualquer vendedor (o front usa para mostrar o botão);
  - `api/v1/admin/lojas`, `api/v1/admin/pontos-turisticos`, `api/v1/admin/mensalidades?dias=7` (janela 1 a 60, padrão 7).
- **`router/urouter.pas`**: registre o controller.

```pascal
uses
  ..., utasaascontroller,
  utadmincontroller,                    // <-- NOVO
  fpjson;

class procedure tAppRouter.load_routes();
begin
    ...
    TAsaasController.RegisterRoutes;
    TAdminController.RegisterRoutes;    // <-- NOVO
end;
```

**Regras de mensalidade** (`LOJA.VALIDADE` já inclui a tolerância do Asaas):
- **vencida**: `VALIDADE < hoje`;
- **por vencer**: vence dentro da janela **e** a assinatura mais recente da loja (`ASAAS_ASSINATURA` de maior `ID`) não existe ou não está `ATIVA`;
- `VALIDADE` nula não entra nas listas de mensalidade.

---

# PARTE 3 — ADMINISTRADOR GERA COBRANÇA DE QUALQUER LOJA

**ARQUIVO `controller/utasaascontroller.pas`.** Quem passa em `checkout`, `status` e `pix`: a própria loja, o vendedor dono, ou o vendedor **administrador** (qualquer loja). `cancelar` continua **só para o dono** (é destrutivo).

1. **`uses`**: acrescente `SyncObjs, uautorizacao, uratelimit` (e mantenha `uvendedormodel`, usado na auditoria).

2. **Apague** a função local `ResolverLoja` (a regra agora vive em `TAutorizacao.ResolverLoja`) e, no lugar, coloque a **trava de checkout** (antes de `ParseBody`):

```pascal
var
  // Lojas com um checkout em andamento neste processo. Sem isso, duplo clique ou duas
  // pessoas gerando cobrança ao mesmo tempo passam juntas pela checagem de "assinatura em
  // andamento" e criam DUAS assinaturas no Asaas (cobrança em dobro para o comerciante).
  GCheckoutLock: TCriticalSection;
  GCheckoutLojas: TStringList;

// True = esta chamada ganhou a vez para a loja. Quem ganhar DEVE chamar SairCheckout.
function EntrarCheckout(const AUuidLoja: string): Boolean;
begin
  GCheckoutLock.Enter;
  try
    Result := GCheckoutLojas.IndexOf(AUuidLoja) < 0;
    if Result then
      GCheckoutLojas.Add(AUuidLoja);
  finally
    GCheckoutLock.Leave;
  end;
end;

procedure SairCheckout(const AUuidLoja: string);
var
  i: Integer;
begin
  GCheckoutLock.Enter;
  try
    i := GCheckoutLojas.IndexOf(AUuidLoja);
    if i >= 0 then
      GCheckoutLojas.Delete(i);
  finally
    GCheckoutLock.Leave;
  end;
end;
```

3. **Chamadas**: troque `ResolverLoja(...)` por `TAutorizacao.ResolverLoja(...)` nos 4 handlers. O 4º argumento diz se o administrador pode:

```pascal
// HandleCheckout, HandleStatus e HandlePix: administrador pode
if not TAutorizacao.ResolverLoja(Req, Res, body, True,  uuid, comoAdmin) then Exit;   // em Status e Pix o 3º argumento é nil
// HandleCancel: só o dono
if not TAutorizacao.ResolverLoja(Req, Res, body, False, uuid, comoAdmin) then Exit;
```
Declare `comoAdmin: Boolean;` na seção `var` dos 4 handlers (`emCheckout: Boolean;` só no `HandleCheckout`).

4. **`HandleCheckout`**: inicialize `emCheckout := False;` no início e, logo depois do `ResolverLoja`, entre na trava:

```pascal
    if not TAutorizacao.ResolverLoja(Req, Res, body, True, uuid, comoAdmin) then Exit;

    // uma cobrança por vez por loja (ver GCheckoutLojas)
    if not EntrarCheckout(uuid) then
    begin
      TJsonView.SendError(Res, 409, 'Já existe uma cobrança sendo gerada para esta loja. Aguarde alguns segundos.');
      Exit;
    end;
    emCheckout := True;
```

5. **`HandleCheckout`**: limite por usuário + **auditoria antes de chamar o Asaas** (logo antes de `client := TAsaasClient.FromConfig;`). Se o registro de auditoria falhar, cai no `except` e a cobrança **não** é criada:

```pascal
      // No máximo 1 cobrança a cada 3 s por usuário: trava disparo em massa (cada cobrança
      // faz o Asaas notificar o comerciante). Só conta quando vai mesmo chamar o Asaas.
      if not TDedupe.Permitir('checkout:' + TDataModule1.GetIdLoja(Req.Headers['Authorization']), 3000) then
      begin
        TJsonView.SendError(Res, 429, 'Muitas tentativas. Aguarde alguns segundos.');
        Exit;
      end;

      // Ação financeira em loja de OUTRO vendedor: registra ANTES de chamar o Asaas. Se o
      // registro falhar, cai no except abaixo e a cobrança não é criada (falha fechada).
      if comoAdmin then
        TVendedorModel.RegistrarLog(TDataModule1.GetIdLoja(Req.Headers['Authorization']),
          loja.Uuid, 'adm_iniciou_cobranca');
```

6. **`HandleCheckout`**: libere a trava no `finally` final da procedure:

```pascal
  finally
    if emCheckout then
      SairCheckout(uuid);
    client.Free;
    body.Free;
  end;
end;
```

7. **Final do arquivo**, antes do `end.` (a trava precisa existir quando a primeira requisição chegar):

```pascal
initialization
  GCheckoutLock := TCriticalSection.Create;
  GCheckoutLojas := TStringList.Create;

finalization
  GCheckoutLojas.Free;
  GCheckoutLock.Free;
```

---

# PARTE 4 — CACHE PÚBLICO EM ROTA AUTENTICADA

**ARQUIVO `controller/utpontoscontroller.pas`, `HandlerListarPontos`** (`GET vendedor/pontos-turisticos`): a resposta é de um vendedor específico, mas saía com `Cache-Control: public`. Troque **só nesse handler**:

```pascal
// ANTES
Res.AddHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
// DEPOIS
Res.AddHeader('Cache-Control', 'no-store');
```
> **Não** altere os outros `Cache-Control: public` do arquivo: são rotas públicas de propósito (`HandlerGetPontoPublico`, `HandlerComerciosProximos`, `HandlerPontosProximos`, `HandlerPontosPorGPS`).

---

# PARTE 5 — CHECKLIST DE VERIFICAÇÃO

Compile (`guiatourapi.lpi`) e rode estes cenários. `T_LOJA` = token de loja, `T_VEND` = vendedor comum ativo (dono da loja X), `T_ADM` = vendedor `ADM=TRUE`, `T_TERC` = terceirizado (`ADM=FALSE`).

| # | Cenário | Esperado |
|---|---|---|
| 1 | `POST portfolio/foto-capa` com `nome_arquivo = "/../../resources/config.ini"` e base64 de texto | **400/500 "Imagem inválida"**; `config.ini` intacto |
| 2 | Mesmo envio, com um JPEG real | grava `uploads/<uuid>_<guid>.jpg`; `nome_arquivo` ignorado |
| 3 | `T_LOJA` (loja A) em `GET account/get_data?id_loja=<loja B>` | devolve os dados da loja **A** (não a B) |
| 4 | `T_LOJA` (loja A) em `POST account/contato` com `id_loja = <loja B>` | altera a loja **A**; B intacta |
| 5 | `T_TERC` em `GET account/get_data?id_loja=<loja X>` (de outro vendedor) | **403** |
| 6 | `T_VEND` em `GET account/get_data?id_loja=<loja X>` (a dele) | **200** |
| 7 | `POST portfolio/upload` com `id_site` de **outra** loja | **403** |
| 8 | `POST portfolio/remove` com `id_foto` de **outra** loja | **403** |
| 9 | Vendedor com `ATIVO=FALSE` em qualquer rota de vendedor | **403 "Vendedor inativo"** |
| 10 | Renovar token (`token/refresh`) de vendedor com `ATIVO=FALSE` | **401** |
| 11 | `T_TERC` em `GET admin/lojas` | **403** |
| 12 | `T_ADM` em `GET admin/lojas`, `admin/pontos-turisticos`, `admin/mensalidades?dias=7` | **200** |
| 13 | `GET vendedor/perfil` com `T_TERC` e com `T_ADM` | `{"adm":false}` e `{"adm":true}` (sempre 200) |
| 14 | `T_ADM` em `POST assinatura/checkout` de loja de outro vendedor | **201** e 1 linha `adm_iniciou_cobranca` em `LOG_ACAO_VENDEDOR` |
| 15 | `T_TERC` no mesmo checkout | **403** |
| 16 | `T_ADM` em `POST assinatura/cancelar` de loja de outro vendedor | **403** |
| 17 | Dois `checkout` simultâneos da mesma loja | um **201**, o outro **409** |
| 18 | Dois `checkout` seguidos do mesmo usuário em menos de 3 s | o 2º recebe **429** |
| 19 | `GET vendedor/pontos-turisticos` | header `Cache-Control: no-store` |

## Observações

- **Recomendado no nginx:** servir `/imagens/` com `X-Content-Type-Options: nosniff` (um arquivo com cabeçalho de JPEG e conteúdo extra continua sendo tratado como imagem).
- **Não corrigido de propósito:** `GET portfolio/galeria/:id_portfolio` continua lendo a galeria por id (as fotos já são públicas na página da loja).
- Depois de aplicar a Parte 1.2 o front **continua igual**: ele já envia `id_loja` só quando o usuário é vendedor, e agora o servidor valida esse id.

---

# ANEXOS: código completo das units novas

## Anexo A: `service/uarquivoseguro.pas`

```pascal
unit uarquivoseguro;

{$mode delphi}{$H+}

{
  Gravação segura de imagens enviadas pelo cliente.

  Problema que resolve: o nome do arquivo vinha do cliente e era concatenado direto no
  caminho (./uploads/ + id + _ + nome). Um nome como /../../resources/config.ini escapava
  da pasta uploads e sobrescrevia arquivos do servidor.

  Regras desta unit:
    - o nome que o cliente mandou é IGNORADO (nunca entra no caminho nem no banco);
    - o nome final é PREFIXO + _ + GUID + extensão, gerado aqui;
    - a extensão sai dos BYTES da imagem (JPEG, PNG ou WEBP), não do nome. Por isso uma
      foto de iPhone chamada IMG_1.HEIC, já convertida para JPEG pelo front, continua
      funcionando;
    - tamanho máximo de 8 MB decodificado, e o base64 é medido ANTES de decodificar;
    - o caminho final é conferido: tem que ficar dentro de ./uploads.

  Uso: Preparar devolve o caminho, a URL para o banco e os bytes decodificados. Quem
  chama grava os bytes em ACaminho e guarda AUrlBanco.
}

interface

uses
  Classes, SysUtils, base64;

type
  TArquivoSeguro = class
  public
    class function Preparar(const APrefixo, ABase64: string;
      out ACaminho, AUrlBanco, ADecodificado: string): Boolean;
  end;

implementation

const
  TAMANHO_MAXIMO = 8 * 1024 * 1024; // bytes, já decodificado

// Prefixo vem do UUID da loja (ou de um GUID gerado no servidor). Só aceita o que um
// UUID pode ter, então nunca carrega barra, ponto ou espaço para dentro do caminho.
function PrefixoSeguro(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (Length(S) >= 1) and (Length(S) <= 64);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9', 'a'..'f', 'A'..'F', '-', '{', '}']) then
    begin
      Result := False;
      Exit;
    end;
end;

function ExtensaoPeloConteudo(const D: string): string;
begin
  Result := '';
  if Length(D) < 12 then Exit;

  // JPEG: FF D8 FF
  if (D[1] = #$FF) and (D[2] = #$D8) and (D[3] = #$FF) then
    Result := '.jpg'
  // PNG: 89 'PNG' 0D 0A 1A 0A
  else if Copy(D, 1, 8) = (#$89 + 'PNG' + #$0D#$0A#$1A#$0A) then
    Result := '.png'
  // WEBP: 'RIFF' ???? 'WEBP'
  else if (Copy(D, 1, 4) = 'RIFF') and (Copy(D, 9, 4) = 'WEBP') then
    Result := '.webp';
end;

class function TArquivoSeguro.Preparar(const APrefixo, ABase64: string;
  out ACaminho, AUrlBanco, ADecodificado: string): Boolean;
var
  ext, nome, pasta: string;
  g: TGuid;
begin
  Result := False;
  ACaminho := '';
  AUrlBanco := '';
  ADecodificado := '';

  if (ABase64 = '') or (not PrefixoSeguro(APrefixo)) then Exit;

  // base64 ocupa ~4/3 do tamanho real: recusa o que já é grande demais sem decodificar
  if Length(ABase64) > ((TAMANHO_MAXIMO div 3) + 1) * 4 then Exit;

  try
    ADecodificado := DecodeStringBase64(ABase64);
  except
    ADecodificado := '';
    Exit;
  end;

  if Length(ADecodificado) > TAMANHO_MAXIMO then
  begin
    ADecodificado := '';
    Exit;
  end;

  ext := ExtensaoPeloConteudo(ADecodificado);
  if ext = '' then
  begin
    ADecodificado := '';
    Exit;
  end;

  CreateGUID(g);
  nome := APrefixo + '_' +
    StringReplace(StringReplace(GUIDToString(g), '{', '', [rfReplaceAll]),
                  '}', '', [rfReplaceAll]) + ext;

  pasta := IncludeTrailingPathDelimiter(ExpandFileName('./uploads'));
  ACaminho := ExpandFileName(pasta + nome);

  // última barreira: o arquivo TEM que ficar dentro de ./uploads
  if Pos(pasta, ACaminho) <> 1 then
  begin
    ACaminho := '';
    ADecodificado := '';
    Exit;
  end;

  AUrlBanco := '/imagens/' + nome;
  Result := True;
end;

end.
```

## Anexo B: `service/uautorizacao.pas`

```pascal
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
```

## Anexo C: `model/uadminmodel.pas`

```pascal
unit uadminmodel;

{$mode delphi}{$H+}

{
  Camada de dados da administração geral (somente vendedores administradores).

  "Vendedor administrador" = linha em VENDEDOR com ATIVO = TRUE e ADM = TRUE. Vendedor
  terceirizado fica com ADM = FALSE (padrão): loga e usa o painel normal, mas não vê a
  administração. A condição é conferida no banco a cada requisição, então tirar o ADM ou
  desativar o vendedor corta o acesso na hora, sem esperar o JWT expirar.

  Regras de mensalidade (LOJA.VALIDADE já inclui os dias de tolerância do Asaas):
    - VENCIDA   : VALIDADE < hoje (mesma regra do login e das páginas públicas)
    - POR VENCER: VALIDADE entre hoje e hoje + N dias  E  a loja NÃO tem pagamento
                  recorrente, ou seja, a assinatura mais recente (ASAAS_ASSINATURA de
                  maior ID) não existe ou não está com STATUS = 'ATIVA'
    - Loja com VALIDADE nula não entra nas listas de mensalidade (aparece como
      "sem_validade" na lista geral de lojas).

  Padrão do projeto: TGetData com SQL que começa em SELECT, nenhum CTE. NUMERIC lido com
  CAST(... AS DOUBLE PRECISION) e diferenças de data com CAST(... AS INTEGER).
}

interface

uses
  Classes, SysUtils, db, fpjson, ugetdata, uasaas;

type
  TAdminModel = class
  public
    class function VendedorAtivo(const AIdVendedor: string): Boolean;
    class function VendedorAdmin(const AIdVendedor: string): Boolean;
    class function SiteDaLoja(AIdSite: Integer; const AUuidLoja: string): Boolean;
    class function LojaDaFoto(AIdFoto: Integer): string;
    class function ListarLojas(const AIdVendedor: string): TJSONArray;
    class function ListarPontos: TJSONArray;
    class function ListarMensalidades(const AIdVendedor: string;
      ADiasAviso: Integer): TJSONObject;
  end;

implementation

const
  // Colunas e junções compartilhadas entre a lista de lojas e a de mensalidades.
  // A assinatura "atual" da loja é a de maior ID (mesma regra de TAsaasModel.UltimaAssinatura).
  SQL_LOJA_COLUNAS =
    'SELECT l.uuid, l.nome, l.slug, l.telefone, l.email, l.cidade, l.uf, l.validade, ' +
    'CAST(DATEDIFF(DAY FROM CURRENT_DATE TO l.validade) AS INTEGER) AS dias, ' +
    'c.nome AS categoria, v.nome AS vendedor, v.uuid AS vendedor_uuid, ' +
    'COALESCE(a.status, ''SEM_ASSINATURA'') AS assinatura_status, ' +
    'a.billing_type AS forma_pagamento, ' +
    'CAST(a.valor AS DOUBLE PRECISION) AS valor ';

  SQL_LOJA_ORIGEM =
    'FROM loja l ' +
    'LEFT JOIN categoria c ON c.id = l.id_categoria ' +
    'LEFT JOIN vendedor v ON v.id = l.id_vendedor ' +
    'LEFT JOIN asaas_assinatura a ON a.id = ' +
    '  (SELECT MAX(x.id) FROM asaas_assinatura x WHERE x.loja_id = l.id) ';

function DataOuNulo(AField: TField): TJSONData;
begin
  if AField.IsNull then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(DateToIso(AField.AsDateTime));
end;

// Monta o item JSON de uma loja a partir da linha atual do dataset.
// O UUID do vendedor NÃO vai para o cliente: só serve para marcar "meu" (loja do
// próprio vendedor logado), usado na tela para destacar "(você)".
function LojaParaJson(ADs: TDataSet; const AIdVendedor: string): TJSONObject;
var
  situacao: string;
begin
  if ADs.FieldByName('validade').IsNull then
    situacao := 'sem_validade'
  else if ADs.FieldByName('dias').AsInteger < 0 then
    situacao := 'vencida'
  else
    situacao := 'no_ar';

  Result := TJSONObject.Create;
  Result.Add('uuid', ADs.FieldByName('uuid').AsString);
  Result.Add('nome', ADs.FieldByName('nome').AsString);
  Result.Add('slug', ADs.FieldByName('slug').AsString);
  Result.Add('telefone', ADs.FieldByName('telefone').AsString);
  Result.Add('email', ADs.FieldByName('email').AsString);
  Result.Add('cidade', ADs.FieldByName('cidade').AsString);
  Result.Add('uf', ADs.FieldByName('uf').AsString);
  Result.Add('categoria', ADs.FieldByName('categoria').AsString);
  Result.Add('vendedor', ADs.FieldByName('vendedor').AsString);
  Result.Add('meu', (AIdVendedor <> '') and
    (ADs.FieldByName('vendedor_uuid').AsString = AIdVendedor));
  Result.Add('validade', DataOuNulo(ADs.FieldByName('validade')));
  if ADs.FieldByName('dias').IsNull then
    Result.Add('dias', TJSONNull.Create)
  else
    Result.Add('dias', ADs.FieldByName('dias').AsInteger);
  Result.Add('situacao', situacao);
  Result.Add('assinatura_status', ADs.FieldByName('assinatura_status').AsString);
  Result.Add('forma_pagamento', ADs.FieldByName('forma_pagamento').AsString);
  if ADs.FieldByName('valor').IsNull then
    Result.Add('valor', TJSONNull.Create)
  else
    Result.Add('valor', ADs.FieldByName('valor').AsFloat);
end;

// Vendedor existe e está ATIVO (VENDEDOR.ATIVO = TRUE). Usado pela cobrança, que também
// atende vendedor comum (dono da loja) e por isso não exige ADM.
class function TAdminModel.VendedorAtivo(const AIdVendedor: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if Trim(AIdVendedor) = '' then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM vendedor WHERE uuid = :uuid AND ativo = TRUE',
    [AIdVendedor], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.VendedorAdmin(const AIdVendedor: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if Trim(AIdVendedor) = '' then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM vendedor WHERE uuid = :uuid AND ativo = TRUE AND adm = TRUE',
    [AIdVendedor], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

// O SITE de id AIdSite pertence à loja AUuidLoja? (impede anexar foto no site de outra loja)
class function TAdminModel.SiteDaLoja(AIdSite: Integer; const AUuidLoja: string): Boolean;
var
  ds: TDataSet;
begin
  Result := False;
  if (AIdSite <= 0) or (Trim(AUuidLoja) = '') then Exit;

  ds := TGetData.getData(
    'SELECT 1 FROM site WHERE id = :id AND id_loja_ex = :uuid',
    [AIdSite, AUuidLoja], True);
  try
    Result := not ds.IsEmpty;
  finally
    ds.Free;
  end;
end;

// UUID da loja dona da foto da galeria (SITE_GALERIA.ID); '' se a foto não existe.
class function TAdminModel.LojaDaFoto(AIdFoto: Integer): string;
var
  ds: TDataSet;
begin
  Result := '';
  if AIdFoto <= 0 then Exit;

  ds := TGetData.getData(
    'SELECT s.id_loja_ex FROM site_galeria g JOIN site s ON s.id = g.id_site WHERE g.id = :id',
    [AIdFoto], True);
  try
    if not ds.IsEmpty then
      Result := ds.Fields[0].AsString;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.ListarLojas(const AIdVendedor: string): TJSONArray;
var
  ds: TDataSet;
begin
  Result := TJSONArray.Create;
  ds := nil;
  try
    try
      ds := TGetData.getData(
        SQL_LOJA_COLUNAS + SQL_LOJA_ORIGEM + 'ORDER BY l.nome',
        [], True);
      while not ds.Eof do
      begin
        Result.Add(LojaParaJson(ds, AIdVendedor));
        ds.Next;
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    ds.Free;
  end;
end;

class function TAdminModel.ListarPontos: TJSONArray;
var
  ds: TDataSet;
  item: TJSONObject;
begin
  Result := TJSONArray.Create;
  ds := nil;
  try
    try
      ds := TGetData.getData(
        'SELECT p.uuid, p.nome, p.slug, p.ativo, p.cidade, p.uf, ' +
        'c.nome AS categoria, v.nome AS vendedor ' +
        'FROM ponto_turistico p ' +
        'JOIN categoria_ponto_turistico c ON c.id = p.id_categoria ' +
        'JOIN vendedor v ON v.id = p.id_vendedor ' +
        'ORDER BY p.nome',
        [], True);
      while not ds.Eof do
      begin
        item := TJSONObject.Create;
        item.Add('uuid', ds.FieldByName('uuid').AsString);
        item.Add('nome', ds.FieldByName('nome').AsString);
        item.Add('slug', ds.FieldByName('slug').AsString);
        item.Add('ativo', ds.FieldByName('ativo').AsBoolean);
        item.Add('cidade', ds.FieldByName('cidade').AsString);
        item.Add('uf', ds.FieldByName('uf').AsString);
        item.Add('categoria', ds.FieldByName('categoria').AsString);
        item.Add('vendedor', ds.FieldByName('vendedor').AsString);
        Result.Add(item);
        ds.Next;
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    ds.Free;
  end;
end;

// Devolve { "dias_aviso": N, "vencidas": [...], "por_vencer": [...] }.
// Ordenação: vencidas = as mais atrasadas primeiro; por_vencer = as mais próximas primeiro.
class function TAdminModel.ListarMensalidades(const AIdVendedor: string;
  ADiasAviso: Integer): TJSONObject;
var
  ds: TDataSet;
  vencidas, porVencer: TJSONArray;
begin
  // Faixa saneada (1..60) e injetada como inteiro: DATEADD não aceita bem parâmetro
  // de quantidade no Firebird, e um Integer não carrega nada além de dígitos.
  if ADiasAviso < 1 then ADiasAviso := 1;
  if ADiasAviso > 60 then ADiasAviso := 60;

  Result := TJSONObject.Create;
  vencidas := TJSONArray.Create;
  porVencer := TJSONArray.Create;
  Result.Add('dias_aviso', ADiasAviso);
  Result.Add('vencidas', vencidas);
  Result.Add('por_vencer', porVencer);

  ds := nil;
  try
    try
      ds := TGetData.getData(
        SQL_LOJA_COLUNAS + SQL_LOJA_ORIGEM +
        'WHERE l.validade IS NOT NULL AND (' +
        '  l.validade < CURRENT_DATE ' +
        '  OR (l.validade <= DATEADD(' + IntToStr(ADiasAviso) + ' DAY TO CURRENT_DATE) ' +
        '      AND COALESCE(a.status, '''') <> ''ATIVA'')) ' +
        'ORDER BY l.validade, l.nome',
        [], True);
      while not ds.Eof do
      begin
        if ds.FieldByName('dias').AsInteger < 0 then
          vencidas.Add(LojaParaJson(ds, AIdVendedor))
        else
          porVencer.Add(LojaParaJson(ds, AIdVendedor));
        ds.Next;
      end;
    except
      FreeAndNil(Result); // dono de vencidas e porVencer
      raise;
    end;
  finally
    ds.Free;
  end;
end;

end.
```

## Anexo D: `controller/utadmincontroller.pas`

```pascal
unit utadmincontroller;

{$mode delphi}{$H+}

{
  Administração geral — SOMENTE vendedores administradores (VENDEDOR.ATIVO = TRUE e
  VENDEDOR.ADM = TRUE). Vendedor terceirizado (ADM = FALSE) recebe 403.

  Rotas (todas GET, com JWT):
    api/v1/vendedor/perfil             devolve adm true ou false, para o front decidir se
                                       mostra o botão da administração (vendedor qualquer,
                                       sem 403)
    api/v1/admin/lojas                 todas as lojas cadastradas (de todos os vendedores)
    api/v1/admin/pontos-turisticos     todos os pontos turísticos (de todos os vendedores)
    api/v1/admin/mensalidades?dias=7   lojas vencidas e lojas por vencer sem pagamento
                                       recorrente (dias = janela de aviso, 1..60, padrão 7)

  Autorização (ExigirVendedorAdmin):
    1. o token precisa ser do tipo "vendedor" (token sem claim "tipo" vale como "loja"
       em GetTipoUsuario, então nunca passa);
    2. o vendedor do token precisa existir, estar ATIVO e ter ADM = TRUE no banco AGORA
       (não confia só no JWT, que pode ter sido emitido antes da mudança).

  As respostas trazem dados de todos os comércios (e-mail, telefone), por isso saem com
  Cache-Control: no-store.
}

interface

uses
  Classes, SysUtils, Horse, Horse.JWT, fpjson, udata, uconfig, uJsonView,
  uadminmodel;

type

  { TAdminController }

  TAdminController = class
  public
    class procedure RegisterRoutes();
  end;

implementation

// Responde 403 e devolve False quando o chamador não é um vendedor administrador.
function ExigirVendedorAdmin(Req: THorseRequest; Res: THorseResponse;
  out AIdVendedor: string): Boolean;
var
  auth: string;
begin
  Result := False;
  AIdVendedor := '';

  auth := Req.Headers['Authorization'];

  if TDataModule1.GetTipoUsuario(auth) <> 'vendedor' then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a administradores.');
    Exit;
  end;

  AIdVendedor := TDataModule1.GetIdLoja(auth); // claim "id" = UUID do vendedor

  if not TAdminModel.VendedorAdmin(AIdVendedor) then
  begin
    TJsonView.SendError(Res, 403, 'Acesso restrito a administradores.');
    Exit;
  end;

  Result := True;
end;

// Qualquer vendedor pode perguntar se é administrador (200 sempre, nunca 403 por não
// ser adm): o front usa isso só para mostrar ou esconder o botão da administração.
procedure HandlerPerfilVendedor(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  auth: string;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    auth := Req.Headers['Authorization'];
    if TDataModule1.GetTipoUsuario(auth) <> 'vendedor' then
    begin
      TJsonView.SendError(Res, 403, 'Acesso restrito a vendedores.');
      Exit;
    end;

    jsonRes := TJSONObject.Create;
    jsonRes.Add('adm', TAdminModel.VendedorAdmin(TDataModule1.GetIdLoja(auth)));

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerPerfilVendedor - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminLojas(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    arrayItens := TAdminModel.ListarLojas(idVendedor);

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);
    arrayItens := nil; // agora pertence a jsonRes

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerAdminLojas - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminPontos(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  arrayItens: TJSONArray;
  jsonRes: TJSONObject;
begin
  arrayItens := nil;
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    arrayItens := TAdminModel.ListarPontos;

    jsonRes := TJSONObject.Create;
    jsonRes.Add('itens', arrayItens);
    arrayItens := nil; // agora pertence a jsonRes

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes)
      else if Assigned(arrayItens) then FreeAndNil(arrayItens);
      WriteLn('Erro em: HandlerAdminPontos - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

procedure HandlerAdminMensalidades(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
var
  idVendedor: string;
  dias: Integer;
  jsonRes: TJSONObject;
begin
  jsonRes := nil;
  try
    if not ExigirVendedorAdmin(Req, Res, idVendedor) then Exit;

    dias := StrToIntDef(Trim(Req.Query['dias']), 7); // o model limita a 1..60

    jsonRes := TAdminModel.ListarMensalidades(idVendedor, dias);

    Res.AddHeader('Cache-Control', 'no-store');
    TJsonView.SendResponseJsonObject(Res, jsonRes, 200);
  except on e: Exception do
    begin
      if Assigned(jsonRes) then FreeAndNil(jsonRes);
      WriteLn('Erro em: HandlerAdminMensalidades - ' + e.Message);
      TJsonView.SendError(Res, 500, 'Erro interno.');
    end;
  end;
end;

class procedure TAdminController.RegisterRoutes();
begin
  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/vendedor/perfil', HandlerPerfilVendedor);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/lojas', HandlerAdminLojas);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/pontos-turisticos', HandlerAdminPontos);

  THorse.AddCallback(HorseJWT(TConfig.Token))
  .Get('api/v1/admin/mensalidades', HandlerAdminMensalidades);
end;

end.
```

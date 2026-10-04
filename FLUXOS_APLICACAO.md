# Detalhamento do Fluxo de Ações da Aplicação - Guia Tour API

Este documento descreve detalhadamente o fluxo de funcionamento, as rotas, os controladores, os modelos e as regras de negócio para cada ação principal do sistema **Guia Tour API**.

---

## 1. Módulo de Autenticação e Gestão de Sessão

O sistema utiliza autenticação baseada em tokens JWT (`Horse.JWT`), hashing seguro com BCrypt e tokens de atualização (*refresh tokens*).

### A. Renovação de Token (`/api/v1/token/refresh`)
- **Rota:** `POST /api/v1/token/refresh`
- **Controlador:** [`HandleRefreshToken`](controller/utlogincontroller.pas:30) em [`uTlogincontroller.pas`](controller/utlogincontroller.pas:1)
- **Fluxo:**
  1. A aplicação cliente envia um JSON contendo `r_token` (refresh token) e `uuid`.
  2. O middleware valida se o corpo da requisição está vazio ou malformado.
  3. O método [`TLoginModel.updateRefreshToken`](model/uloginmodel.pas) valida o refresh token no banco de dados.
  4. Se válido, novos tokens de acesso são gerados e retornados com o status HTTP adequado (ex: `200 OK`). Caso contrário, retorna `401 Unauthorized`.

### B. Autenticação via Google (`/api/v1/login_google`)
- **Rota:** `POST /api/v1/login_google`
- **Controlador:** [`HandleLogin_Google`](controller/utlogincontroller.pas:85) em [`uTlogincontroller.pas`](controller/utlogincontroller.pas:1)
- **Fluxo:**
  1. O cliente envia o código de autorização do Google (`g_code`) e opcionalmente o `r_token`.
  2. O backend valida a presença do código.
  3. O [`TLoginModel.LoginGoogle`](model/uloginmodel.pas) troca o código por tokens junto ao provedor Google, identifica ou registra o usuário no banco de dados Firebird via [`udata.pas`](data/udata.pas:1) e gera a sessão JWT da aplicação.
  4. Retorna os dados do usuário e tokens de acesso.

---

## 2. Módulo de Lojas / Estabelecimentos Parceiros

Gerencia o cadastro, endereços, redes sociais, pixels de rastreamento e configurações avançadas de estabelecimentos comerciais.

### A. Registro de Nova Loja (`/api/v1/account/register`)
- **Rota:** `POST /api/v1/account/register`
- **Controlador:** [`HandleRegisterRoute`](controller/utlojacontroller.pas:97) em [`utlojacontroller.pas`](controller/utlojacontroller.pas:1)
- **Fluxo:**
  1. Recebe os dados básicos (`nome`, `telefone`, `email`, `slug`, `horario`) no corpo da requisição.
  2. Sanitiza os inputs utilizando [`TSecurityService.SanitizeInput`](service/usecurityservice.pas).
  3. Aciona [`TLojaModel.createloja`](model/ulojamodel.pas) para persistir o registro no banco Firebird.
  4. Em caso de duplicidade de chave única (nome, telefone ou email), captura o erro e retorna `409 Conflict`. Caso contrário, retorna `200 OK` com mensagem de sucesso.

### B. Atualização de Dados e Configurações
- **Rotas Protegidas por JWT (`HorseJWT`)**:
  - `POST /api/v1/account/update` ([`HandlerUpdateAccounPass`](controller/utlojacontroller.pas:51)): Atualiza dados cadastrais gerais e horários.
  - `POST /api/v1/account/update_account_basico` ([`HandlerUpdateAccounBasico`](controller/utlojacontroller.pas:391)): Atualiza nome, apelido/slug e categoria da loja.
  - `POST /api/v1/account/contato` ([`HandlerUpdateAccounContato`](controller/utlojacontroller.pas:435)): Atualiza telefone, email e Instagram.
  - `POST /api/v1/account/update_endereco` ([`HandlerUpdateEndereco`](controller/utlojacontroller.pas:478)): Atualiza o endereço completo (CEP, logradouro, número, bairro, cidade, estado, latitude, longitude).
  - `POST /api/v1/account/update_configuracoes_avancadas` ([`HandlerUpdateConfiguracoesAvancadas`](controller/utlojacontroller.pas:568)): Atualiza IDs de rastreamento (Google Analytics, Meta Pixel, Google Ads) e horários de funcionamento.
  - `POST /api/v1/account/metatoken`, `meta_ads_id`, `meta_pixel_id`, `google_analytics_id`, `status_campanha_meta`: Endpoints específicos para configurar integrações de marketing e anúncios.

### C. Consulta de Endereço por CEP (`/api/v1/portfolio/account/:cep`)
- **Rota:** `GET /api/v1/portfolio/account/:cep`
- **Controlador:** [`HandlerGetEnderecoCep`](controller/utlojacontroller.pas:529)
- **Fluxo:**
  1. Limpa formatações do CEP informado na URL.
  2. Valida se possui exatamente 8 dígitos.
  3. Consulta o serviço externo/base de dados via [`TLojaModel.GetEnderecoCep`](model/ulojamodel.pas) e retorna os dados de logradouro, bairro, cidade e estado em formato JSON.

---

## 3. Módulo de Portfólios e Vitrines Digitais

Controla a exibição das páginas públicas personalizadas de cada loja.

- **Rotas gerenciadas por** [`TPortifolioController`](controller/uportifoliocontroller.pas:1):
  - Consulta e renderização de portfólios, galeria de produtos/serviços e informações comerciais da loja para exibição no frontend ou via SSR.

---

## 4. Módulo de Pontos Turísticos (`/pontos`)

Gerencia o cadastro, histórico, coordenadas geográficas e mídias dos locais de interesse.

- **Rotas gerenciadas por** [`TPontoTuristicoController`](controller/utpontoscontroller.pas:1) em [`utpontoscontroller.pas`](controller/utpontoscontroller.pas:1):
  - Cadastro, listagem, atualização e remoção de pontos turísticos.
  - Associação de pontos geográficos (latitude e longitude) para visualização em mapas.

---

## 5. Módulo Público, Busca e Eventos (`/api/v1/...`)

Gerencia a experiência de descoberta pública e o rastreamento de interações dos usuários.

### A. Busca Inteligente (`/api/v1/explorar/buscar?q=`)
- **Rota:** `GET /api/v1/explorar/buscar`
- **Controlador:** [`HandlerBuscar`](controller/utguiatourpublicocontroller.pas:27) em [`utguiatourpublicocontroller.pas`](controller/utguiatourpublicocontroller.pas:1)
- **Fluxo:**
  1. Captura o termo de busca `q` na query string e o limpa usando [`LimparTermo`](service/uguiatourutils.pas).
  2. Executa [`TBuscaModel.Buscar`](model/ubuscamodel.pas) para consultar pontos turísticos e lojas correspondentes.
  3. Adiciona cabeçalho de cache (`Cache-Control: public, max-age=30, s-maxage=60`) e retorna os resultados formatados em JSON via [`TJsonView.SendResponseJsonObject`](view/ujsonview.pas).

### B. Renderização de Página de Ponto Turístico (`/ponto/:slug`)
- **Rota:** `GET /ponto/:slug`
- **Controlador:** [`HandlerPaginaPonto`](controller/utguiatourpublicocontroller.pas:47)
- **Fluxo:**
  1. Valida se o slug informado é válido através de [`SlugValido`](service/uguiatourutils.pas).
  2. Busca os dados do ponto turístico no banco via [`TPontoTuristicoModel.GetBySlug`](model/upontoturisticomodel.pas).
  3. Se encontrado, renderiza o template HTML correspondente utilizando [`TPontoView.Render`](view/uguiatourpontoview.pas) (Server-Side Rendering).
  4. Retorna a página HTML com status `200 OK` e diretivas de cache otimizadas para SEO.

### C. Rastreamento de Eventos e Métricas (`/api/v1/evento`)
- **Rota:** `POST /api/v1/evento`
- **Controlador:** [`HandlerEvento`](controller/utguiatourpublicocontroller.pas:88)
- **Fluxo:**
  1. Verifica se a requisição provém de um bot conhecido (`EhBot`).
  2. Valida o tamanho e a estrutura JSON do corpo da requisição (tipos permitidos: `card`, `pin`, `ver`, `whats`, `rota`).
  3. Identifica o IP do cliente (considerando proxies Cloudflare / X-Forwarded-For).
  4. Aplica controle anti-abuso (*Rate Limiting* / deduplicação por IP, loja e tipo) através de [`TDedupe.Permitir`](service/uratelimit.pas).
  5. Se permitido, registra o evento de interação no banco via [`TEventoModel.Registrar`](model/ueventomodel.pas).
  6. Responde sempre com status `204 No Content` para não expor detalhes internos ao visitante.

---

## 6. Módulo de SEO, Robots e Sitemaps

- **`/robots.txt`**: Gerado dinamicamente por [`HandlerRobots`](controller/utguiatourpublicocontroller.pas:135) utilizando [`TGuiaTourSeo.Robots`](service/uguiatourseo.pas).
- **`/sitemap.xml`, `/sitemap-pontos.xml`, `/sitemap-lojas.xml`**: Gerenciados por [`EnviarSitemap`](controller/utguiatourpublicocontroller.pas:142), construindo índices XML otimizados para indexação em motores de busca.

---

## 7. Módulo de Integração de Pagamentos (`/asaas`)

- **Rotas gerenciadas por** [`TAsaasController`](controller/utasaascontroller.pas:1) em [`utasaascontroller.pas`](controller/utasaascontroller.pas:1):
  - Integração com a API de pagamentos Asaas para controle de cobranças, assinaturas e webhooks de confirmação de pagamento para os lojistas parceiros.

---
*Documentação gerada automaticamente para o ecossistema Guia Tour API.*

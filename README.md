# Guia Tour API

O **Guia Tour API** é o motor de backend para uma plataforma de turismo inteligente. Desenvolvida em Pascal utilizando o framework Horse, a aplicação gerencia informações sobre pontos turísticos, estabelecimentos comerciais (lojas), vendedores e portfólios, oferecendo uma interface robusta para gestão e consulta de dados turísticos.

## 🚀 Funcionalidades

- **Gestão de Pontos Turísticos:** Cadastro completo com histórico, localização (latitude/longitude), galeria de fotos e categorização.
- **Ecossistema de Lojas:** Gerenciamento de estabelecimentos parceiros, incluindo endereços, contatos e integração com redes sociais.
- **Portfólios Personalizados:** Geração automática de páginas (sites) para lojas, servindo como uma vitrine digital dentro do guia.
- **Busca Inteligente:** Motor de busca para encontrar pontos de interesse e estabelecimentos.
- **Segurança e Controle:** 
  - Autenticação baseada em **JWT**.
  - Proteção de rotas e hashing de senhas com **BCrypt**.
  - Sistema de **Rate Limit** para prevenir abusos.
- **Integração com IA:** Assistente baseado em IA para suporte ou enriquecimento de dados.
- **Rastreamento de Eventos:** Monitoramento de interações (cliques em cards, rotas, WhatsApp) para análise de métricas.
- **Renderização Híbrida:** Suporte a respostas em JSON para aplicações mobile/SPA e SSR (Server-Side Rendering) para páginas SEO-friendly.

## 🌐 Endpoints Principais da API

A API está organizada em rotas modulares gerenciadas pelos controllers:

- **Autenticação (`/login`):** Geração e validação de tokens JWT, autenticação de usuários e lojistas com hash seguro (BCrypt).
- **Lojas (`/lojas`):** CRUD completo e gestão de estabelecimentos parceiros e dados cadastrais.
- **Portfólios (`/portifolio`):** Gerenciamento e renderização de portfólios e páginas digitais das lojas.
- **Vendedores (`/vendedores`):** Gestão de vendedores, comissões, cadastros e vínculos comerciais.
- **Pontos Turísticos (`/pontos`):** Cadastro, histórico, geolocalização e mídias de pontos de interesse.
- **Público (`/publico`):** Endpoints abertos para consulta pública de guias, listagem otimizada e renderização SSR amigável para SEO.
- **Asaas (`/asaas`):** Integração de pagamentos e cobranças com a plataforma Asaas.

## 🛠️ Tecnologias e Dependências

A aplicação foi construída utilizando o ecossistema **Lazarus/Free Pascal**:

- **Linguagem:** [Pascal (Object Pascal)](https://www.freepascal.org/)
- **Framework Web:** [Horse](https://github.com/HashLoad/horse) (v3.1.6)
- **Banco de Dados:** Firebird (acesso via **ZeosLib**)
- **Segurança:**
  - [Horse-JWT](https://github.com/HashLoad/horse-jwt)
  - [LazJWT](https://github.com/wanderlan-santos/LazJWT)
  - [BCrypt](https://github.com/dlioti/bcrypt)
- **Comunicação REST:** [RESTRequest4Delphi](https://github.com/viniciussanchez/RESTRequest4Delphi)
- **Utilitários:**
  - HashLib4Pascal
  - Horse-Compression (Compressão Gzip/Deflate)

## 📂 Estrutura do Projeto

- `controller/`: Controladores responsáveis por processar as requisições e aplicar as regras de negócio.
- `model/`: Camada de persistência e lógica de dados (Interação com o banco).
- `view/`: Camada de apresentação, incluindo renderização de HTML e formatação de JSON.
- `service/`: Serviços utilitários (Segurança, PDF, Cache, IA, Notificações).
- `router/`: Definição centralizada das rotas da API.
- `data/`: DataModule central para conexão com o banco de dados.
- `resources/`: Arquivos de configuração (`config.ini`) e definições de queries SQL.
- `templates/`: Templates HTML para renderização no servidor.

## 💡 Casos de Uso

1. **Turistas:** Utilizam a aplicação (via frontend/mobile) para descobrir pontos turísticos, ver fotos, ler histórias e traçar rotas para locais de interesse.
2. **Lojistas/Parceiros:** Gerenciam sua presença no guia, atualizando informações de contato, horários e fotos, além de acompanhar cliques e interações dos usuários.
3. **Vendedores/Administradores:** Gerenciam a base de dados de pontos turísticos e lojas, validando cadastros e garantindo a qualidade da informação.
4. **Marketing:** Analisam os eventos de clique para entender quais pontos e lojas são mais populares em determinadas regiões.

## ⚙️ Configuração e Execução

### Pré-requisitos
- [Lazarus IDE](https://www.lazarus-ide.org/) instalado.
- Banco de Dados Firebird configurado.
- Dependências (Horse, ZeosLib, etc.) instaladas no ambiente Lazarus.

### Passos para rodar
1. Clone o repositório.
2. Certifique-se de que o arquivo `resources/config.ini` contém as credenciais corretas do banco de dados.
3. Execute o script `guiatour.sql` no seu banco Firebird para criar a estrutura de tabelas.
4. Abra o projeto `guiatourapi.lpi` no Lazarus.
5. Compile e execute o projeto.
6. O servidor estará disponível por padrão em `http://localhost:8100`.

---
*Desenvolvido como parte do ecossistema Guia Tour.*

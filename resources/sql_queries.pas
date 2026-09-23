unit sql_queries;

{$mode delphi}{$H+}

interface

const
  //****************************************************************************
  // SITE
  //****************************************************************************
  site_config = 'update or insert into site (titulo, subtitulo, id_loja_ex) '+
    'values(:titulo, :subtitulo, :id_loja) matching(id_loja_ex);';

  //****************************************************************************
  // DESPESAS
  //****************************************************************************
  criar_despesa = 'EXECUTE PROCEDURE SP_DESPESAS(:descricao, :status, '+
    ':valor, :qtd, :f_pagamento, :data, :id_loja);';

  list_resume_despesas = 'select * from SP_RESUMO_FINANCEIRO(:id_loja);';

  list_despesas_por_mes_e_residuo = 'SELECT * FROM SP_LISTAR_DESPESAS_MES(:ID_LOJA, :DATA_INI, :DATA_FIM)';

  delete_despesa = 'delete from despesas where id = :id;';

  update_despesa = 'update despesas set descricao = :desc, forma_pagamento = :f_pagamento, '+
    'status = :status, data_vencimento = :date, valor = :valor where id = :id;';

  update_baixa_despesa = 'update despesas set status = ''PAGO'' where id = :id;';

  //****************************************************************************
  // ZAP
  //****************************************************************************
  criar_instacia_zap = 'update LOJA set ZAP_INSTANCE = :ZAP_INSTANCE '+
    'where uuid = :uuid';

  // ******************************************************************************
  // LOJA
  // ******************************************************************************

  busca_loja_por_email = 'SELECT uuid, validade FROM loja WHERE email = :email';

  criar_loja_dados_google = 'insert into loja(nome, email, validade, '+
    'uuid) values(:nome, :email, :validade, :uuid) returning uuid;';

  criar_loja_simples = 'insert into loja (nome, email, telefone, validade, '+
    'uuid, CONFIG_HORARIO, slug) values(:nome, :email, :telefone, '+
    ':validade, :uuid, :CONFIG_HORARIO, :slug) returning id;';

  busca_loja_login = 'select id, nome, telefone, email, validade, uuid, '+
    'senha, senha_temp, refresh_token, expire, CONFIG_HORARIO from loja where email = :email;';

  busca_loja_login_temp = 'select id, nome, telefone, email, validade, '+
    'uuid, senha, senha_temp, refresh_token, expire, CONFIG_HORARIO = :CONFIG_HORARIO from loja where email = :email;';

  update_loja_simples_senha = 'update loja set nome = :nome, email = :email, '+
    'telefone = :telefone, senha = :senha, CONFIG_HORARIO = :CONFIG_HORARIO, '+
    'slug = :slug where uuid = :id;';

  update_loja_simples = 'update loja set nome = :nome, email = :email, telefone '+
    '= :telefone, CONFIG_HORARIO = :CONFIG_HORARIO, slug = :slug where uuid = :id;';

  update_refresh_token = 'update loja set refresh_token = :token, expire = '+
    ':expire where uuid = :uuid;';

  verify_refresh_token = 'select expire from loja where refresh_token = '+
    ':refresh_token and uuid = :uuid;';

  busca_loja_simples = 'select nome, email, telefone, ZAP_INSTANCE, CONFIG_HORARIO, '+
    'slug, insta from loja where uuid = :id;';

  busca_loja_telefone = 'select uuid, zap_instance from loja where telefone = :telefone;';

  get_slug = 'select slug, uuid from loja where slug = :slug;';

  get_info_studio = 'SELECT l2.NOME, l2.TELEFONE, l2.INSTA, s.TITULO, s.SUBTITULO '+
                  'FROM LOJA l2 LEFT JOIN site s ON (s.ID_LOJA_EX = l2.uuid) '+
                  'WHERE l2.SLUG = :slug;';

  //****************************************************************************
  // PROFISSIONAIS
  //****************************************************************************

  insert_professional_simples = 'insert into profissionais (nome, telefone, '+
    'comicao, id_loja_ex, flag, v_vendido, v_cancelado) values(:nome, :telefone, :comissao, :id, ''A'', 0, 0);';

  list_professional_simples = 'select id, nome, telefone, comicao, v_vendido '+
    'from profissionais where id_loja_ex = :id and flag <> ''D'';';

  detail_professional_simples = 'select id, nome, telefone, comicao, v_vendido '+
    'from profissionais where id = :id;';

  update_professional_simples = 'update profissionais set nome = :nome, '+
    'telefone = :telefone, comicao = :comissao where id = :id;';

  delete_professional_simples = 'update profissionais set flag = ''D'' '+
    'where id = :id;';


  //****************************************************************************
  // PRODUTOS
  //****************************************************************************
  list_products_simples = 'select id, nome, valor_custo, valor_venda, inf_valor, '+
    'margem, comicao, quantidade_estoque, min_estoque, insumo, comissionado, '+
    'vendas from produtos where id_loja_ex = :id and flag <> ''D'' '+
    'and ident_serv = ''0'';';

  insert_product_simples = 'insert into produtos (nome, valor_custo, valor_venda, '+
    'inf_valor, margem, quantidade_estoque, min_estoque, insumo, ident_serv, '+
    'id_loja_ex, flag, comissionado, vendas) values (:nome, :valor_custo, '+
    ':valor_venda, :inf_valor, :margem, :quantidade_estoque, :min_estoque, '+
    ':insumo, ''0'', :id_loja, ''A'', :comissionado, 0);';

  delete_product_simples = 'update produtos set flag = ''D'' where id = :id;';

  update_product_simples = 'update produtos set nome = :nome, valor_custo = :custo, '+
    'valor_venda = :venda, inf_valor = :inf, margem = :margem, '+
    'quantidade_estoque = :estoque, min_estoque = :min, insumo = :insumo, '+
    'comissionado = :comissionado where id = :id;';

  detail_product_simples = 'select id, nome, valor_custo, valor_venda, inf_valor, '+
    'margem, QUANTIDADE_ESTOQUE, MIN_ESTOQUE, insumo, comissionado, comicao '+
    'from produtos where id = :id;';


  //****************************************************************************
  // SERVICOS
  //****************************************************************************
  list_services_simples = 'select id, nome, valor_custo, valor_venda, inf_valor, '+
    'margem, comicao, vendas from produtos where ident_serv = ''1'' '+
    'and id_loja_ex = :id and flag = ''A'';';

  detail_service_simples = 'select id, nome, valor_custo, valor_venda, inf_valor, '+
    'margem, comissionado, comicao  from produtos where id = :id;';

  update_service_simples = 'update produtos set nome = :nome, valor_custo = :custo, '+
    'valor_venda = :venda, inf_valor = :inf, margem = :margem, '+
    'comissionado = :comissionado where id = :id;';

  create_service_simples = 'insert into produtos (nome, valor_custo, valor_venda, '+
    'inf_valor, margem, comissionado, id_loja_ex, ident_serv, flag, insumo) '+
    'values (:nome, :valor_custo, :valor_venda, :inf_valor, :margem, '+
    ':comissionado, :id_loja, ''1'', ''A'', ''False'');';


  //****************************************************************************
  // CLIENTES
  //****************************************************************************
  list_profissionais_publico_por_tel =
    'SELECT P.ID, P.NOME FROM PROFISSIONAIS P ' +
    'INNER JOIN LOJA L ON L.UUID = P.ID_LOJA_EX ' +
    'WHERE L.TELEFONE = :TELEFONE AND P.FLAG <> ''D'' ORDER BY P.NOME;';

  create_client_simples = 'update or insert into clientes (nome, data_nascimento, telefone, '+
    'id_loja_ex, categoria, flag) values(:nome, :data_nascimento, :telefone, '+
    ':id_loja_ex, ''A'', ''A'') matching (telefone);';

  create_client_anamnese = 'update or insert into clientes (nome, data_nascimento, '+
    'telefone, insta, id_loja_ex, categoria, flag) values(:nome, :data_nascimento, '+
    ':telefone, :insta, :id_loja_ex, ''A'', ''A'') matching(telefone) returning id;';

  create_anamnese_client = //'update or insert into anamnese (id_client, profissao, '+
    'insert into anamnese (id_client, profissao, '+
    'como_conheceu, consumo, pratica_esporte, qual_esporte, diabetico, '+
    'hipertenso, hemofilico, problema_de_pele, qual_problema_de_pele, '+
    'gestante_amamentando, alcool_drogas, doenca_transmissivel, qual_doenca, '+
    'alergia, qual_alergia, medicamento, qual_medicamento, concorda_com_termos, '+
    'gosto_de_piercing, gosto_de_tatuagem, estilo_tatuagem, assinatura_b64) '+

    'values(:id_client, :profissao, '+
    ':como_conheceu, :consumo, :pratica_esporte, :qual_esporte, :diabetico, '+
    ':hipertenso, :hemofilico, :problema_de_pele, :qual_problema_de_pele, '+
    ':gestante_amamentando, :alcool_drogas, :doenca_transmissivel, :qual_doenca, '+
    ':alergia, :qual_alergia, :medicamento, :qual_medicamento, :concorda_com_termos, '+
    ':gosto_piercing, :gosto_tatuagem, :estilo_tatuagem, :assinatura)'+
    ';';
    //' matching (id_client);';

  registrar_anamnese = 'execute procedure REGISTRAR_ANAMNESE(:P_NOME, '+
    ':P_TELEFONE, :P_DATA_NASCIMENTO, :P_INSTA, :P_TELEFONE_STUDIO, :P_PROFISSAO, '+
    ':P_COMO_CONHECEU, :P_CONSUMO, :P_PRATICA_ESPORTE, :P_QUAL_ESPORTE, :P_DIABETICO, '+
    ':P_HIPERTENSO, :P_HEMOFILICO, :P_PROBLEMA_PELE, :P_QUAL_PROBLEMA_PELE, '+
    ':P_GESTANTE_AMAMENTANDO, :P_ALCOOL_DROGAS, :P_DOENCA_TRANSMISSIVEL, '+
    ':P_QUAL_DOENCA, :P_ALERGIA, :P_QUAL_ALERGIA, :P_MEDICAMENTO, :P_QUAL_MEDICAMENTO, '+
    ':P_CONCORDA_TERMOS, :P_GOSTO_PIERCING, :P_GOSTO_TATUAGEM, :P_ESTILO_TATUAGEM, '+
    ':P_ASSINATURA, :P_ID_PROFISSIONAL);';

  list_client_simples = 'select id, nome, telefone, data_nascimento, '+
    'data_ultima_compra, v_gasto, categoria from clientes where id_loja_ex = :id '+
    'and flag <> ''D'' order by nome;';

  list_client_simples_a = 'select id, nome, telefone, data_nascimento, '+
    'data_ultima_compra, v_gasto, categoria from clientes where id_loja_ex = :id '+
    'and categoria = ''A''  and flag <> ''D'';';

  list_client_simples_b = 'select id, nome, telefone, data_nascimento, '+
    'data_ultima_compra, v_gasto, categoria from clientes where id_loja_ex = :id '+
    'and categoria = ''B''  and flag <> ''D'';';

  list_client_simples_c = 'select id, nome, telefone, data_nascimento, '+
    'data_ultima_compra, v_gasto, categoria from clientes where id_loja_ex = :id '+
    'and categoria = ''C''  and flag <> ''D'';';

  list_client_simples_order_maior_v_gasto = 'select id, nome, telefone, '+
    'data_nascimento, data_ultima_compra, v_gasto, categoria from clientes '+
    'where id_loja_ex = :id and flag <> ''D'' order by v_gasto desc;';

  list_client_simples_order_menor_v_gasto = 'select id, nome, telefone, '+
    'data_nascimento, data_ultima_compra, v_gasto, categoria from clientes '+
    'where id_loja_ex = :id and flag <> ''D'' order by v_gasto asc;';

  delete_cliente_simples = 'update clientes set flag = ''D'' where id = :id;';

  detail_client_simples = 'select nome, telefone, data_nascimento from clientes '+
    'where id = :id;';

  update_client_simples = 'update clientes set nome = :nome, telefone = :telefone, '+
    'data_nascimento = :aniversario where id = :id;';

  rec_senha = 'update loja set senha_temp = :senha_temp where email = :email;';

  list_itens_simples = 'select id, nome, valor_venda, inf_valor, comicao, '+
    'quantidade_estoque, comissionado, ident_serv from produtos '+
    'where id_loja_ex = :id and flag <> ''D'' and insumo <> ''True'' order by nome;';

  list_client_simples_caixa = 'select id, nome, telefone, data_nascimento, '+
    'data_ultima_compra, v_gasto, categoria from clientes where id_loja_ex = :id '+
    'and flag <> ''D'' order by nome;';


  //****************************************************************************
  // CAIXA
  //****************************************************************************
  retornar_id_loja='select max(id) from loja where telefone = :telefone;';

  create_caixa_simples = 'insert into caixa (status, id_loja_ex, data_abertura, '+
    'troco_abertura, pr_abriu) values(''A'', :id_loja, :data_abertura, '+
    ':troco_abertura, :pr_abriu);';

  retornar_id_caixa = 'select first 1 id, status from caixa where id_loja_ex = '+
    ':id_loja order by id desc;';

  fechar_caixa_simples = 'update caixa set status = ''F'', troco = :troco, '+
    'pr_fechou = :pr, dinheiro = :dinheiro, pix = :pix, debito = :debito, '+
    'credito = :credito, data_fechamento = :data where id = :id';


  //****************************************************************************
  // VENDAS
  //****************************************************************************
  call_registrar_venda_lote = 'SELECT R_ID_VENDA FROM REGISTRAR_VENDA_LOTE(' +
    ':id_prof, :valor, :id_caixa, :id_cliente, :din, :pix, :deb, :cred, :troco, ' +
    ':id_loja, :perc_comissao, :lista_itens);';

// Chama a procedure de cabeçalho e RETORNA o ID gerado (usando SELECT)
  call_registrar_venda_proc = 'SELECT R_ID_VENDA FROM REGISTRAR_VENDA(' +
    ':id_loja, :id_prof, :valor, :id_cliente, :id_caixa, :din, :pix, :deb, :cred, :troco);';

  // Chama a procedure de itens (apenas EXECUTA, sem retorno)
  call_registrar_item_proc = 'EXECUTE PROCEDURE REGISTRAR_ITEM_VENDA(' +
    ':id_venda, :cod_prod, :qtd, :v_unit, :v_total, :perc_comissao, ' +
    ':id_prof, :comissionado, :ident_serv);';

  criar_venda_simples = 'insert into venda (id_loja_ex, id_profissional, valor, '+
    'status, id_cliente, data, id_caixa, din, pix, deb, cred, troco) values(:id_loja_ex, '+
    ':id_profissional, :valor, ''F'', :id_cliente, :data_venda, :id_caixa, :din, '+
    ':pix, :deb, :cred, :troco) returning id;';

  criar_venda_detalhada_simples = 'insert into venda_detalhada (cod_produto, '+
    'valor, cod_venda, quantidade, total, comissao, cod_func, valor_menos_comissao) '+
    'values(:cod_produto, :valor, :cod_venda, :quantidade, :total, :comissao, '+
    ':cod_func, :valor_menos_comissao);';

  update_estoque_simples = 'update produtos set QUANTIDADE_ESTOQUE = '+
    'QUANTIDADE_ESTOQUE - :quantidade, vendas = vendas + :vendas where id = :id;';

  update_vendas_produtos_simples = 'update produtos set vendas = vendas + :vendas '+
    'where id = :id;';

  update_v_vendido_profissional = 'update profissionais set v_vendido = v_vendido + '+
    ':v_vendido where id = :id;';

  list_insumos_simples = 'select id, nome, quantidade_estoque, VALOR_VENDA from produtos where '+
    'id_loja_ex = :id_loja and insumo = ''True'';';

  update_insumos_simples = 'update produtos set quantidade_estoque = '+
    'quantidade_estoque - :quantidade where id = :id;';

  update_consumo_cliente_simples = 'update clientes set v_gasto = v_gasto + :v, '+
    'data_ultima_compra = :data where id = :id;';

  update_nota_cliente_simples = 'update clientes set categoria = :categoria where id = :id;';


  //****************************************************************************
  // AGENDA
  //****************************************************************************

  notificacao_agenda_pendente = 'select id_loja_ex from agenda where id_loja_ex = :id '+
    'and data2 >= current_date and flag = ''P'';';

  list_solicitacoes_pendentes =
    'SELECT * FROM AGENDA ' +
    'WHERE COD_FUNC = :id_prof AND FLAG = ''P'' ' +
    'ORDER BY DATA2 ASC;';

  solicitar_agendamento_app =
    'INSERT INTO AGENDA (COD_FUNC, COD_CLIENT, CLIENTE, TELEFONE, HORA_INI, HORA_FIM, DATA2, FLAG, TAREFA, ID_LOJA_EX) ' +
    'VALUES (:id_prof, :id_cliente, :cliente, :telefone, :hora_ini, :hora_fim, :data_ag, ''P'', ''Solicitação via App'', :uuid);';

  recusar_agendamento = 'update agenda set flag = ''D'' where id = :id_agenda;';

  aprovar_agendamento = 'update agenda set hora_ini = :hora_exata_ini, '+
    'hora_fim = :hora_exata_fim, flag = ''A'' where id = :id_agenda;';

  list_solicitacoes_agendamento_pendentes =
    'select id, cliente, telefone, data2, hora_ini, hora_fim, tarefa ' +
    'from agenda where cod_func = :id_prof and flag = ''P'' order by data2;';

  busca_dados_agenda_turnos = 'select * from SP_BUSCA_DADOS_CLIENTE(:telefone);';

  busca_cliente_telefone_agenda_turnos = 'select id, nome, profissional from clientes '+
    'where telefone = :telefone and flag <> ''D'';';

  busca_profissional_id_turnos = 'id, nome, id_loja_ex from profissionais where id = :id';

  busca_config_loja_publico =
    'SELECT CONFIG_HORARIO FROM LOJA WHERE TELEFONE = :telefone;';

  list_ocupacao_periodo =
    'select cast(data2 as date) as data_ref, hora_ini, hora_fim ' +
    'from agenda where cod_func = :id and data2 >= :data_ini and data2 <= :data_fim ' +
    'and flag <> ''D'' order by data2, hora_ini;';

  list_ocupacao_dia = 'select hora_ini, hora_fim from agenda where cod_func = :id ' +
    'and cast(data2 as date) = :data and flag <> ''D'' order by hora_ini;';

  list_agendamentos_simples = 'select id, cliente, cod_client, telefone, tarefa, '+
  'valor, hora_ini, hora_fim, data2, event_id, valor, sinal from agenda where cod_func = :id and '+
  'data2 = :date and flag = ''A'' and ' +
  '( (data2 <> CURRENT_DATE) OR (data2 = CURRENT_DATE AND hora_ini >= CURRENT_TIME) ) '+
  'order by hora_ini;';

  list_resumo_agenda = 'select data2 from agenda where cod_func = :id '+
  'and data2 >= :data and flag = ''A'' order by data2;';

  create_agendamento_simples = 'insert into agenda (COD_FUNC, COD_CLIENT, '+
  'CLIENTE, TELEFONE, HORA_INI, HORA_FIM, DATA2, event_id, FLAG, valor, sinal, id_loja_ex) '+
  'values(:COD_FUNC, :COD_CLIENT, :CLIENTE, :TELEFONE, :HORA_INI, :HORA_FIM, '+
  ':DATA2, :event_id, ''A'', :valor, :sinal, :id_loja_ex);';

  delete_agendamento_simples = 'update agenda set flag = ''D'' where id = :id;';

  detail_agendamento_simples = 'select COD_FUNC, COD_CLIENT, '+
  'CLIENTE, TELEFONE, HORA_INI, HORA_FIM, DATA2, event_id, valor, sinal '+
  'from agenda where id = :id;';

  update_agendamento_simples = 'update agenda set COD_FUNC = :id_prof, '+
  'COD_CLIENT = :id_client, CLIENTE = :client, TELEFONE = :telefone, '+
  'HORA_INI = :hora_ini, HORA_FIM = :hora_fim, DATA2 = :data, event_id = :event_id, '+
  'valor = :valor, sinal = :sinal, flag = ''A'' where id = :id;';


  busca_config_horario_por_prof =
    'SELECT l.CONFIG_HORARIO FROM LOJA l ' +
    'INNER JOIN PROFISSIONAIS p ON p.ID_LOJA_EX = l.UUID ' +
    'WHERE p.ID = :id_prof';



  //****************************************************************************

  busca_loja = 'SELECT * FROM LOJA WHERE ID = :ID;';

  busca_loja_email =
    'SELECT ID, CONF_SENHA, NOME, '
    + 'INICIAR_WHATSAPP, MSG_RECEBIMENTO_VENDA, MSG_LEMBRETE_AGENDAMENTO, SENHA, SENHA_TEMP, '
    + 'MSG_VENDA, MSG_LEMBRETE_AGENDA, MSG_CONFIRMACAO_AGENDAMENTO, MSG_AUT_AGENDAMENTO, '
    + 'CONFIG_HORARIO FROM LOJA WHERE EMAIL = :EMAIL;';

  atualiza_loja =
    'UPDATE LOJA SET NOME = :NOME, EMAIL = :EMAIL, CPF_CNPJ = :CPF_CNPJ, ' +
    'PAINEL = :PAINEL, CAIXA = :CAIXA, RETIRADAS = :RETIRADAS,' +
    'COMANDAS = :COMANDAS, CAT_CLIENT = :CAT_CLIENT,' +
    'SENHA_ALTER_PACOTE = :SENHA_ALTER_PACOTE, COMANDA = :COMANDA, ' +
    'MSG_AUTOMATICA_BAIXA_PACOTE = :MSG_AUTOMATICA_BAIXA_PACOTE,' +
    'INICIAR_WHATSAPP = :INICIAR_WHATSAPP, MSG_LEMBRETE_AGENDAMENTO = ' +
    ':MSG_LEMBRETE_AGENDAMENTO, MSG_RECEBIMENTO_VENDA = :MSG_RECEBIMENTO_VENDA, '
    + 'MSG_VENDA = :MSG_VENDA, MSG_LEMBRETE_AGENDA = ' +
    ':MSG_LEMBRETE_AGENDA, MSG_CONFIRMACAO_AGENDAMENTO = :MSG_CONFIRMACAO_AGENDAMENTO, '
    + 'MSG_AUT_AGENDAMENTO = :MSG_AUT_AGENDAMENTO ' + 'WHERE ID = :IDLOJA;';

  atualiza_loja_senha =
    'UPDATE LOJA SET NOME = :NOME, EMAIL = :EMAIL, SENHA = :SENHA, ' +
    'CPF_CNPJ = :CPF_CNPJ, PAINEL = :PAINEL, CAIXA = :CAIXA, RETIRADAS = :RETIRADAS,'
    + 'COMANDAS = :COMANDAS, CAT_CLIENT = :CAT_CLIENT,' +
    'SENHA_ALTER_PACOTE = :SENHA_ALTER_PACOTE, COMANDA = :COMANDA, ' +
    'MSG_AUTOMATICA_BAIXA_PACOTE = :MSG_AUTOMATICA_BAIXA_PACOTE,' +
    'INICIAR_WHATSAPP = :INICIAR_WHATSAPP, MSG_LEMBRETE_AGENDAMENTO = ' +
    ':MSG_LEMBRETE_AGENDAMENTO, MSG_RECEBIMENTO_VENDA = :MSG_RECEBIMENTO_VENDA, '
    + 'MSG_VENDA = :MSG_VENDA, MSG_LEMBRETE_AGENDA = ' +
    ':MSG_LEMBRETE_AGENDA, MSG_CONFIRMACAO_AGENDAMENTO = :MSG_CONFIRMACAO_AGENDAMENTO, '
    + 'MSG_AUT_AGENDAMENTO = :MSG_AUT_AGENDAMENTO ' + 'WHERE ID = :IDLOJA;';

  inserir_registro_loja =
    'INSERT INTO LOJA (NOME,EMAIL,SENHA,TELEFONE,CPF_CNPJ,PAINEL,' +
    'CAIXA,RETIRADAS,COMANDAS,CAT_CLIENT, SENHA_ALTER_PACOTE, ' +
    'COMANDA, S, MSG_AUTOMATICA_BAIXA_PACOTE, INICIAR_WHATSAPP, MSG_LEMBRETE_AGENDAMENTO, '
    + 'MSG_RECEBIMENTO_VENDA, MSG_VENDA, MSG_LEMBRETE_AGENDA, MSG_CONFIRMACAO_AGENDAMENTO, '
    + 'MSG_AUT_AGENDAMENTO) ' +

    'VALUES(:NOME,:EMAIL,:SENHA,:TELEFONE,:CPF_CNPJ,:PAINEL,:CAIXA, ' +
    ':RETIRADAS,:COMANDAS,:CAT_CLIENT,:SENHA_ALTER_PACOTE, ' +
    ':COMANDA, :S, :MSG_AUTOMATICA_BAIXA_PACOTE, :INICIAR_WHATSAPP, :MSG_LEMBRETE_AGENDAMENTO, '
    + ':MSG_RECEBIMENTO_VENDA, :MSG_VENDA, :MSG_LEMBRETE_AGENDA, :MSG_CONFIRMACAO_AGENDAMENTO, '
    + ':MSG_AUT_AGENDAMENTO);';

  selecionar_max_id_loja =
    'select max(id) from loja where TELEFONE = :TELEFONE;';

  atualiza_senha_temporaria =
    'UPDATE LOJA SET SENHA_TEMP = '''' where id = :id;';

  // ******************************************************************************
  // PROFISSIONAIS
  // ******************************************************************************

  busca_profissional_apelido =
    'SELECT * FROM PROFISSIONAIS WHERE ID_LOJA = :IDLOJA AND APELIDO = :APELIDO;';
  listar_profissionais =
    'select * from profissionais where id_loja = :idloja';

  // ******************************************************************************
  // CAMPANHA WHATSAPP
  // ******************************************************************************
  consulta_clientes_env_campanha =
    'SELECT c.data_ini, c.data_fim, c.caminho_img, c.saudacao,' +
    'c.mensagem, c.SAUDACAO, c.MENSAGEM, cc.nome_cliente, cc.telefone_cliente, '
    + 'cc.ENVIADO, cc.id, cc.NOME_SOCIAL FROM CAMPANHA_WPP c ' +
    'join clientes_campanha_wpp cc on cc.id_campanha = c.id ' +
    'WHERE c.id_loja = :IDLOJA ' + 'AND c.status = ''Ativo'' ' +
    'and cc.enviado <> ''SIM'';';

  atualiza_clientes_env_campanha = 'UPDATE CLIENTES_CAMPANHA_WPP ' +
    'SET ENVIADO = ''SIM'' ' + 'WHERE ID = :ID_CLIENTE;';

  atualiza_campanha_ativa_para_inativa = 'UPDATE CAMPANHA_WPP ' +
    'SET STATUS = ''Inativo'' ' + 'WHERE ID_LOJA = :IDLOJA ' +
    'AND STATUS = ''Ativo'' ' + 'AND DATA_FIM < :DATA_ATUAL;';

  cria_nova_campanha_wpp = 'INSERT INTO CAMPANHA_WPP ' +
    '(DESCRICAO, DATA_INI, DATA_FIM, CAMINHO_IMG, MENSAGEM, ID_LOJA, STATUS) ' +
    'VALUES(:DESCRICAO, :DATA_INI, :DATA_FIM, :CAMINHO_IMG, :MENSAGEM, :IDLOJA, :STATUS);';

  atualizar_campanha_wpp = 'update CAMPANHA_WPP set ' +
    'DESCRICAO = :DESCRICAO, DATA_INI = :DATA_INI, DATA_FIM = :DATA_FIM, ' +
    'CAMINHO_IMG = :CAMINHO_IMG, MENSAGEM = :MENSAGEM, STATUS = :STATUS ' +
    'where id = :id;';

  delete_campanha = 'delete from CAMPANHA_WPP where id = :idcampanha;';

  delete_publico_campanha =
    'delete from CLIENTES_CAMPANHA_WPP where id_campanha = :idcampanha;';

  delete_interesses_campanha =
    'delete from INTERESSE_CAMPANHA where id_campanha = :idcampanha;';

  consulta_ultimo_id_campanha =
    'SELECT MAX(ID) FROM CAMPANHA_WPP WHERE ID_LOJA = :IDLOJA;';

  cria_publico_campanha = 'INSERT INTO CLIENTES_CAMPANHA_WPP ' +
    '(ID_CLIENTES, ID_CAMPANHA, ID_LOJA, NOME_CLIENTE, TELEFONE_CLIENTE, NOME_SOCIAL, ENVIADO) '
    + 'VALUES(:ID_CLIENTES, :ID_CAMPANHA, :IDLOJA, :NOME_CLIENTE, :TELEFONE_CLIENTE, :NOME_SOCIAL, ''NAO'');';

  listar_campanha = 'SELECT * FROM CAMPANHA_WPP WHERE ID_LOJA = :IDLOJA';

  interesse_campanha =
    'INSERT INTO INTERESSE_CAMPANHA (ID_LOJA, ID_CAMPANHA, ID_INTERESSE) ' +
    'VALUES(:ID_LOJA, :ID_CAMPANHA, :ID_INTERESSE);';

  detalhe_campanha =
    'select cw.id, cw.descricao, cw.data_ini, cw.data_fim, cw.caminho_img, ' +
    'cw.mensagem, cw.status, ccw.id_clientes, ccw.nome_cliente, ' +
    'ccw.telefone_cliente, ccw.nome_social, i.id as id_interesse, i.interesses from campanha_wpp cw '
    + 'left join (select * from interesse_campanha ica where ica.id_campanha = :id_campanha)ica on ica.id_campanha = cw.id '
    + 'left join (select * from clientes_campanha_wpp ccw where ccw.id_campanha = :id_campanha)ccw on ccw.id_campanha = cw.id '
    + 'left join interesse_do_cliente ic on ic.id_cliente = ccw.id_clientes ' +
    'left join interesses i on i.id = ica.id_interesse ' +
    'where cw.id = :id_campanha;';

  // ******************************************************************************
  // VENDA
  // ******************************************************************************
  selecionar_id_max_vendas =
    'SELECT MAX(ID) FROM VENDA WHERE ID_LOJA = :IDLOJA;';

  criar_novo_registro_venda =
    'INSERT INTO VENDA (ID_PROFISSIONAL, DATA, VALOR, PROFISSIONAL, ' +
    'STATUS, ID, ID_CLIENTE, CLIENTE, ID_LOJA, ID_CAIXA, DIN, PIX, DEB, CRED) '
    + 'VALUES (:ID_PROFISSIONAL, :DATA, :VALOR, :PROFISSIONAL, :STATUS, ' +
    ':ID, :ID_CLI, :CLIENTE, :ID_LOJA, :IDCAIXA,  :DIN, :PIX, :DEB, :CRED);';

  selecionar_produtos =
    'SELECT VENDAS, QUANTIDADE_ESTOQUE, IDENT_SERV FROM PRODUTOS WHERE ID = :ID;';

  atualiza_estoque_valor_vendido =
    'UPDATE PRODUTOS SET QUANTIDADE_ESTOQUE = :QTD, VENDAS = :VENDAS WHERE ID = :ID;';

  criar_nova_venda_detalhada =
    'INSERT INTO VENDA_DETALHADA (COD_PRODUTO,PRODUTO,VALOR, ' +
    'COD_VENDA,QUANTIDADE,TOTAL,COMICAO,COD_FUNC,COD_CLIENTE,DATA2, ' +
    'VALOR_MENOS_COMICAO,STATUS_COMICAO,STATUS,V_CUSTO,PROFISSIONAL, ' +
    'Margem, ID_LOJA, ID_CAIXA) ' +

    'VALUES (:COD_PRODUTO,:PRODUTO,:VALOR,:COD_VENDA, ' +
    ':QUANTIDADE,:TOTAL,:COMICAO,:COD_FUNC,:COD_CLIENTE,:DATA, ' +
    ':VALOR_MENOS_COMICAO,:STATUS_COMICAO,:STATUS,:VCUSTO,:PROFISSIONAL, ' +
    ':Margem, :iD_LOJA, :ID_CAIXA);';

  selecionar_pacote = 'SELECT * FROM PACOTE_ITENS WHERE ID_PACOTE = :ID;';

  inserir_itens_pacote = 'INSERT INTO PACOTES_ABERTOS(ID_LOJA,ID_CLIENTE, ' +
    'ID_PROFISSIONAL,ID_PACOTE,CLIENTE, ' +
    'PACOTE,STATUS,PROFISSIONAL,ID_VENDA) ' +
    'VALUES(:ID_LOJA,:ID_CLIENTE,:ID_PROFISSIONAL, ' +
    ':ID_PACOTE,:CLIENTE,:PACOTE,:STATUS,:PROFISSIONAL,:ID_VENDA);';

  seleciona_caixa_aberto =
    'SELECT * FROM CAIXA WHERE ID_LOJA = :ID_LOJA AND STATUS = ''ABERTO'';';

  atualiza_valores_caixa =
    'UPDATE CAIXA SET DINHEIRO = :DINHEIRO, CREDITO = :CREDITO, DEBITO = :DEBITO, PIX = :PIX '
    + 'WHERE ID_LOJA = :ID_LOJA AND STATUS = :STATUS;';

  busca_valor_gasto_cliente = 'SELECT V_GASTO FROM CLIENTES WHERE ID = :ID;';

  atualiza_valor_gasto_cliente =
    'UPDATE CLIENTES SET V_GASTO = :GASTO, DATA_ULTIMA_COMPRA = :d WHERE ID = :ID;';

  consulta_valor_vendido_prof =
    'SELECT V_VENDIDO FROM PROFISSIONAIS WHERE ID = :ID;';

  atualiza_valor_vendido_prof =
    'UPDATE PROFISSIONAIS SET V_VENDIDO = :VENDIDO WHERE ID = :ID;';

  verifica_nome_produto =
    'SELECT NOME FROM PRODUTOS WHERE ID_LOJA = :IDLOJA AND NOME = :NOME;';

  novo_registro_produto =
    'INSERT INTO PRODUTOS (QUANTIDADE_ESTOQUE,NOME,VALOR_CUSTO,VALOR_VENDA,INF_VALOR, '
    + 'MARGEM,COMISSIONADO,MIN_ESTOQUE,INSUMO,ID_LOJA,IDENT_SERV,COMICAO) ' +

    'VALUES(:QTD,:NOME,:VALOR_CUSTO,:VALOR_VENDA,:INF_VALOR, ' +
    ':MARGEM,:COMISSIONADO,:MIN,:INSUMO,:IDLOJA,:IDENT_SERV,:COMICAO);';

  atualizar_registro_produto =
    'UPDATE PRODUTOS SET QUANTIDADE_ESTOQUE = :QTD, NOME = :NOME, ' +
    'VALOR_CUSTO = :VALOR_CUSTO, VALOR_VENDA = :VALOR_VENDA, INF_VALOR = :INF_VALOR, '
    + 'COMICAO = :COMICAO, COMISSIONADO = :COMISSIONADO, MARGEM = :MARGEM, MIN_ESTOQUE = :MIN, '
    + 'INSUMO = :INSUMO WHERE ID = :CODIGO;';

  // ******************************************************************************
  // INTERESSES
  // ******************************************************************************

  novo_interesse =
    'INSERT INTO INTERESSES (ID_LOJA, INTERESSES) VALUES(:IDLOJA, :INTERESSE);';

  busca_ultimo_interesse =
    'SELECT MAX(ID) FROM INTERESSES WHERE ID_LOJA = :IDLOJA;';

  busca_interesse =
    'SELECT * FROM INTERESSES WHERE ID_LOJA = :IDLOJA AND INTERESSES = :INTERESSE;';

  busca_interesse_cliente =
    'SELECT * FROM INTERESSE_DO_CLIENTE WHERE ID_CLIENTE = :idcliente AND ID_INTERESSE = :idinteresse;';

  adicionar_interesse_cliente =
    'INSERT INTO INTERESSE_DO_CLIENTE (ID_LOJA,ID_CLIENTE,ID_INTERESSE) VALUES(:ID_LOJA,:ID_CLIENTE,:ID_INTERESSE);';

  deletar_interesses_cliente =
    'delete from INTERESSE_DO_CLIENTE where ID_CLIENTE = :ID_CLIENTE;';

  // ******************************************************************************
  // CLIENTES
  // ******************************************************************************

  deletar_cliente = 'delete from clientes where id = :id;';

  buscar_cliente =
    'SELECT ID, NOME, TELEFONE, DATA_NASCIMENTO, NOME_SOCIAL FROM CLIENTES WHERE ID_LOJA = :ID_LOJA ORDER BY NOME;';

  buscar_cliente_telefone =
    'SELECT TELEFONE FROM CLIENTES WHERE TELEFONE = :TELEFONE;';

  cadastrar_novo_cliente =
    'INSERT INTO CLIENTES (NOME,NOME_SOCIAL,EMAIL,DATA_NASCIMENTO, TELEFONE, ID_LOJA) '
    + 'VALUES(:CLIENTE,:APELIDO,:EMAIL,:ANIVERSARIO,:TELEFONE,:IDLOJA);';

  selecionar_ultimo_id_cliente =
    'SELECT MAX(ID) FROM CLIENTES WHERE ID_LOJA = :IDLOJA;';

  // ******************************************************************************
  // AGENDA
  // ******************************************************************************

  criar_novo_agendamento =
    'INSERT INTO AGENDA (COD_FUNC,FUNCIONARIO,CLIENTE,COD_CLIENTE,TELEFONE,TAREFA,VALOR,DATA2,HORA_INI,HORA_FIM,ID_LOJA) '
    + 'VALUES(:CODPROF,:NOMEPROF,:CLIENTE,:COD_CLIENT,:TELEFONE,:ATENDIMENTO,:VALOR,:DATA,:HORAINI,:HORAFIM,:IDLOJA);';

  // ******************************************************************************
  // PRODUTOS
  // ******************************************************************************

  listar_produtos =
    'select NOME, QUANTIDADE_ESTOQUE, COMISSIONADO, INF_VALOR, ID, INSUMO, ' +
    'IDENT_SERV, VALOR_VENDA, VALOR_CUSTO, COMICAO FROM PRODUTOS where ID_LOJA = :ID_LOJA '
    + 'and INSUMO = ''Nao'' ORDER BY NOME;';


implementation

end.


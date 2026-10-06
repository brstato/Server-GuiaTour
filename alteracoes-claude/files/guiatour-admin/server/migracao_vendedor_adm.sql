-- Atributo de administrador do vendedor.
-- ADM = TRUE  -> vê a administração geral (lojas, pontos e mensalidades de todos).
-- ADM = FALSE -> vendedor comum/terceirizado: loga e usa o painel normal, sem administração.
-- Todos os vendedores existentes ficam com FALSE; marque abaixo quem é administrador.

ALTER TABLE VENDEDOR ADD ADM BOOLEAN DEFAULT FALSE NOT NULL;

COMMIT;

-- Troque pelo e-mail de quem deve ser administrador:
-- UPDATE VENDEDOR SET ADM = TRUE WHERE EMAIL = 'seu-email@exemplo.com';
-- COMMIT;

-- Para tirar o acesso depois (vale na hora, o servidor confere no banco a cada requisição):
-- UPDATE VENDEDOR SET ADM = FALSE WHERE EMAIL = 'terceirizado@exemplo.com';
-- COMMIT;

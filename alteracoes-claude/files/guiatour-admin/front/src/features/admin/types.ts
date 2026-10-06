import type { FormaPagamento, StatusAssinatura } from "@/features/billing/types";

/** Situação da página da loja em relação à validade (LOJA.VALIDADE). */
export type SituacaoLoja = "no_ar" | "vencida" | "sem_validade";

/**
 * Loja como a administração geral enxerga: usada na lista geral de lojas e nas listas de
 * mensalidade (vencidas / por vencer). Vem de GET admin/lojas e GET admin/mensalidades.
 */
export interface AdminLoja {
  uuid: string;
  nome: string;
  slug: string;
  telefone: string;
  email: string;
  cidade: string;
  uf: string;
  categoria: string;
  vendedor: string;
  /** true quando a loja é do vendedor logado (a tela mostra "(você)"). */
  meu: boolean;
  /** Data (yyyy-mm-dd) até a qual a página fica no ar; null = sem validade. */
  validade: string | null;
  /** Dias até a validade: 0 = vence hoje, negativo = dias de atraso, null = sem validade. */
  dias: number | null;
  situacao: SituacaoLoja;
  /** Status da assinatura mais recente; "SEM_ASSINATURA" quando nunca assinou. */
  assinatura_status: StatusAssinatura;
  /** "" quando não há assinatura. */
  forma_pagamento: FormaPagamento | "UNDEFINED" | "";
  valor: number | null;
}

export interface AdminPonto {
  uuid: string;
  nome: string;
  slug: string;
  ativo: boolean;
  cidade: string;
  uf: string;
  categoria: string;
  vendedor: string;
}

export interface AdminMensalidades {
  /** Janela usada para "por vencer" (1..60). */
  dias_aviso: number;
  /** Já vencidas, as mais atrasadas primeiro. */
  vencidas: AdminLoja[];
  /** Vencem dentro da janela e não têm pagamento recorrente ativo, as mais próximas primeiro. */
  por_vencer: AdminLoja[];
}

import { useMemo, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import {
  AlertTriangle,
  ArrowLeft,
  CalendarClock,
  CreditCard,
  ExternalLink,
  Loader2,
  MapPin,
  MessageCircle,
  RefreshCw,
  Search,
  ShieldAlert,
  Store,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { VendorHeader } from "@/features/vendor/components/VendorHeader";
import { FORMA_LABEL, STATUS_LABEL, formatDate, formatMoney } from "@/features/billing/lib/format";
import type { StatusAssinatura } from "@/features/billing/types";
import { useAdminAcesso } from "../hooks/useAdminAcesso";
import { useAdminController } from "../hooks/useAdminController";
import type { AdminLoja, AdminPonto } from "../types";

type Aba = "mensalidades" | "lojas" | "pontos";

const JANELAS_AVISO = [3, 7, 15, 30];

/** Compara sem diferenciar maiúsculas/acentos. */
function normalizar(valor: string): string {
  return valor
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function combina(busca: string, ...campos: string[]): boolean {
  const termo = normalizar(busca.trim());
  if (!termo) return true;
  return campos.some((campo) => normalizar(campo).includes(termo));
}

function prazoLabel(dias: number | null): string {
  if (dias === null) return "Sem validade";
  if (dias < 0) return `Venceu há ${-dias} ${-dias === 1 ? "dia" : "dias"}`;
  if (dias === 0) return "Vence hoje";
  if (dias === 1) return "Vence amanhã";
  return `Vence em ${dias} dias`;
}

/** Link do WhatsApp a partir de um telefone brasileiro; null se não parecer um telefone. */
function linkWhatsApp(telefone: string): string | null {
  const digitos = telefone.replace(/\D/g, "");
  if (digitos.length < 10) return null;
  const comPais = digitos.startsWith("55") && digitos.length >= 12 ? digitos : `55${digitos}`;
  return `https://wa.me/${comPais}`;
}

const STATUS_COR: Record<StatusAssinatura, string> = {
  ATIVA: "bg-emerald-50 text-emerald-700",
  PENDENTE: "bg-amber-50 text-amber-700",
  INADIMPLENTE: "bg-red-50 text-red-700",
  CANCELADA: "bg-slate-100 text-slate-600",
  SEM_ASSINATURA: "bg-slate-100 text-slate-600",
};

function Badge({ className, children }: { className?: string; children: React.ReactNode }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-1 text-[10px] font-bold uppercase tracking-wider",
        className,
      )}
    >
      {children}
    </span>
  );
}

function ResumoCard({
  titulo,
  valor,
  icone: Icone,
  tom,
  ativo,
  onClick,
}: {
  titulo: string;
  valor: number;
  icone: typeof Store;
  tom: "azul" | "ambar" | "vermelho";
  ativo: boolean;
  onClick: () => void;
}) {
  const tons = {
    azul: "bg-blue-50 text-blue-600",
    ambar: "bg-amber-50 text-amber-600",
    vermelho: "bg-red-50 text-red-600",
  } as const;

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex items-center gap-3 rounded-2xl border bg-white p-4 text-left shadow-xs transition-colors hover:bg-slate-50",
        ativo ? "border-blue-300 ring-2 ring-blue-100" : "border-slate-200/60",
      )}
    >
      <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl", tons[tom])}>
        <Icone className="h-5 w-5" />
      </div>
      <div className="min-w-0">
        <p className="text-2xl font-extrabold leading-none text-slate-900">{valor}</p>
        <p className="mt-1 truncate text-xs font-medium text-slate-500">{titulo}</p>
      </div>
    </button>
  );
}

function LojaLinha({
  loja,
  mostrarPrazo,
  onCobranca,
}: {
  loja: AdminLoja;
  mostrarPrazo: boolean;
  onCobranca: (uuid: string) => void;
}) {
  const whatsapp = linkWhatsApp(loja.telefone);
  const local = [loja.cidade, loja.uf].filter(Boolean).join("/");
  const forma = loja.forma_pagamento ? FORMA_LABEL[loja.forma_pagamento] : "";
  const vencida = loja.situacao === "vencida";

  return (
    <div className="rounded-xl border border-slate-100 bg-slate-50 p-4 transition-colors hover:bg-slate-100/80">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate font-bold text-slate-900">{loja.nome}</h3>
            <Badge className={STATUS_COR[loja.assinatura_status] ?? STATUS_COR.SEM_ASSINATURA}>
              {STATUS_LABEL[loja.assinatura_status] ?? loja.assinatura_status}
            </Badge>
          </div>

          <p className="truncate text-sm text-slate-500">
            /{loja.slug}
            {loja.categoria && ` • ${loja.categoria}`}
            {local && ` • ${local}`}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            Vendedor: {loja.vendedor || "—"}
            {loja.meu && <span className="font-semibold text-blue-600"> (você)</span>}
            {forma && ` • ${forma}`}
            {loja.valor !== null && ` • ${formatMoney(loja.valor)}`}
          </p>

          {mostrarPrazo && (
            <p
              className={cn(
                "mt-2 text-sm font-semibold",
                vencida ? "text-red-600" : loja.dias !== null && loja.dias <= 3 ? "text-amber-600" : "text-slate-700",
              )}
            >
              {prazoLabel(loja.dias)}
              <span className="font-normal text-slate-500"> • {formatDate(loja.validade)}</span>
            </p>
          )}
        </div>

        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {whatsapp && (
            <a
              href={whatsapp}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={`Chamar ${loja.nome} no WhatsApp`}
              className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-2.5 text-sm font-medium text-slate-700 shadow-xs hover:bg-slate-50"
            >
              <MessageCircle className="h-4 w-4 text-emerald-600" />
              <span className="hidden sm:inline">WhatsApp</span>
            </a>
          )}

          {loja.situacao === "no_ar" && (
            <a
              href={`https://guiatour.online/loja/${loja.slug}`}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={`Abrir a página de ${loja.nome}`}
              className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-2.5 text-sm font-medium text-slate-700 shadow-xs hover:bg-slate-50"
            >
              <ExternalLink className="h-4 w-4 text-slate-500" />
              <span className="hidden sm:inline">Página</span>
            </a>
          )}

          <Button
            variant="outline"
            onClick={() => onCobranca(loja.uuid)}
            className="gap-1.5 font-bold text-blue-600"
          >
            <CreditCard className="h-4 w-4" />
            <span className="hidden sm:inline">Cobrança</span>
          </Button>
        </div>
      </div>
    </div>
  );
}

function PontoLinha({ ponto }: { ponto: AdminPonto }) {
  const local = [ponto.cidade, ponto.uf].filter(Boolean).join("/");

  return (
    <div className="flex items-center justify-between gap-3 rounded-xl border border-slate-100 bg-slate-50 p-4 transition-colors hover:bg-slate-100/80">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="truncate font-bold text-slate-900">{ponto.nome}</h3>
          <Badge className={ponto.ativo ? "bg-green-50 text-green-600" : "bg-slate-100 text-slate-500"}>
            {ponto.ativo ? "Ativo" : "Inativo"}
          </Badge>
        </div>
        <p className="truncate text-sm text-slate-500">
          /{ponto.slug}
          {ponto.categoria && ` • ${ponto.categoria}`}
          {local && ` • ${local}`}
        </p>
        <p className="mt-1 text-xs text-slate-500">Vendedor: {ponto.vendedor || "—"}</p>
      </div>

      {ponto.ativo && (
        <a
          href={`https://guiatour.online/ponto/${ponto.slug}`}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={`Abrir a página de ${ponto.nome}`}
          className="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-2.5 text-sm font-medium text-slate-700 shadow-xs hover:bg-slate-50"
        >
          <ExternalLink className="h-4 w-4 text-slate-500" />
          <span className="hidden sm:inline">Página</span>
        </a>
      )}
    </div>
  );
}

function Secao({
  titulo,
  descricao,
  total,
  tom,
  vazio,
  children,
}: {
  titulo: string;
  descricao?: string;
  total: number;
  tom?: "vermelho" | "ambar";
  vazio: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3 flex items-baseline gap-2">
        <h3 className="text-base font-bold text-slate-800">{titulo}</h3>
        <span
          className={cn(
            "rounded-full px-2 py-0.5 text-xs font-bold",
            tom === "vermelho" && total > 0 && "bg-red-50 text-red-600",
            tom === "ambar" && total > 0 && "bg-amber-50 text-amber-600",
            (!tom || total === 0) && "bg-slate-100 text-slate-500",
          )}
        >
          {total}
        </span>
      </div>
      {descricao && <p className="mb-3 text-sm text-slate-500">{descricao}</p>}
      {total > 0 ? <div className="space-y-3">{children}</div> : <p className="py-6 text-center text-slate-500">{vazio}</p>}
    </section>
  );
}

function AdminConteudo() {
  const navigate = useNavigate();
  const {
    lojas,
    pontos,
    vencidas,
    porVencer,
    diasAviso,
    setDiasAviso,
    isLoading,
    isFetching,
    error,
    acessoNegado,
    reload,
  } = useAdminController();

  const [aba, setAba] = useState<Aba>("mensalidades");
  const [busca, setBusca] = useState("");

  const filtraLoja = (l: AdminLoja) =>
    combina(busca, l.nome, l.slug, l.cidade, l.categoria, l.vendedor, l.email);

  const lojasFiltradas = useMemo(
    () => lojas.filter(filtraLoja),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [lojas, busca],
  );
  const vencidasFiltradas = useMemo(
    () => vencidas.filter(filtraLoja),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [vencidas, busca],
  );
  const porVencerFiltradas = useMemo(
    () => porVencer.filter(filtraLoja),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [porVencer, busca],
  );
  const pontosFiltrados = useMemo(
    () =>
      pontos.filter((p) => combina(busca, p.nome, p.slug, p.cidade, p.categoria, p.vendedor)),
    [pontos, busca],
  );

  const irParaCobranca = (uuid: string) => navigate(`/vendedor/comerciantes/${uuid}/assinatura`);

  const abas: { id: Aba; rotulo: string }[] = [
    { id: "mensalidades", rotulo: "Mensalidades" },
    { id: "lojas", rotulo: "Lojas" },
    { id: "pontos", rotulo: "Pontos turísticos" },
  ];

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col">
      <VendorHeader />

      <main className="flex-1 overflow-y-auto">
        <div className="max-w-7xl mx-auto px-6 py-8">
          <Button
            variant="ghost"
            onClick={() => navigate("/vendedor")}
            className="mb-2 gap-2 pl-0 text-slate-600 hover:text-slate-900"
          >
            <ArrowLeft className="h-4 w-4" /> Voltar ao painel
          </Button>

          <div className="mb-8 flex flex-col justify-between gap-4 md:flex-row md:items-center">
            <div>
              <h1 className="text-3xl font-extrabold tracking-tight text-slate-900">Administração geral</h1>
              <p className="mt-1 text-slate-500">
                Todas as lojas, pontos turísticos e mensalidades da rede, de todos os vendedores.
              </p>
            </div>
            <Button
              variant="outline"
              onClick={reload}
              disabled={isFetching}
              className="h-11 gap-2 px-5 font-bold shadow-sm"
            >
              <RefreshCw className={cn("h-4 w-4", isFetching && "animate-spin")} />
              Atualizar
            </Button>
          </div>

          {isLoading ? (
            <div className="flex justify-center py-20">
              <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
            </div>
          ) : error ? (
            <div className="rounded-2xl border border-slate-200/60 bg-white p-10 text-center shadow-xs">
              <ShieldAlert className="mx-auto h-10 w-10 text-slate-400" />
              <p className="mt-3 font-bold text-slate-800">
                {acessoNegado
                  ? "Acesso restrito a administradores."
                  : "Não foi possível carregar a administração."}
              </p>
              {!acessoNegado && (
                <Button onClick={reload} className="mt-4">
                  Tentar de novo
                </Button>
              )}
            </div>
          ) : (
            <>
              <div className="mb-8 grid grid-cols-2 gap-3 lg:grid-cols-4">
                <ResumoCard
                  titulo="Lojas cadastradas"
                  valor={lojas.length}
                  icone={Store}
                  tom="azul"
                  ativo={aba === "lojas"}
                  onClick={() => setAba("lojas")}
                />
                <ResumoCard
                  titulo="Pontos turísticos"
                  valor={pontos.length}
                  icone={MapPin}
                  tom="azul"
                  ativo={aba === "pontos"}
                  onClick={() => setAba("pontos")}
                />
                <ResumoCard
                  titulo={`Por vencer (${diasAviso} dias)`}
                  valor={porVencer.length}
                  icone={CalendarClock}
                  tom="ambar"
                  ativo={aba === "mensalidades"}
                  onClick={() => setAba("mensalidades")}
                />
                <ResumoCard
                  titulo="Mensalidades vencidas"
                  valor={vencidas.length}
                  icone={AlertTriangle}
                  tom="vermelho"
                  ativo={aba === "mensalidades"}
                  onClick={() => setAba("mensalidades")}
                />
              </div>

              <div className="rounded-2xl border border-slate-200/60 bg-white p-6 shadow-xs">
                <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
                  <div className="flex gap-1 rounded-xl bg-slate-100 p-1">
                    {abas.map((item) => (
                      <button
                        key={item.id}
                        type="button"
                        onClick={() => setAba(item.id)}
                        className={cn(
                          "flex-1 rounded-lg px-3 py-1.5 text-sm font-semibold transition-colors lg:flex-none",
                          aba === item.id
                            ? "bg-white text-blue-600 shadow-xs"
                            : "text-slate-600 hover:text-slate-900",
                        )}
                      >
                        {item.rotulo}
                      </button>
                    ))}
                  </div>

                  <div className="relative w-full lg:w-80">
                    <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                    <Input
                      placeholder="Buscar por nome, cidade, vendedor..."
                      className="h-10 border-slate-200 bg-slate-50/50 pl-10 focus-visible:ring-blue-500"
                      value={busca}
                      onChange={(e) => setBusca(e.target.value)}
                    />
                  </div>
                </div>

                {aba === "mensalidades" && (
                  <div className="space-y-8">
                    <div className="flex flex-wrap items-center gap-2 text-sm text-slate-600">
                      <span className="font-medium">Avisar com antecedência de:</span>
                      {JANELAS_AVISO.map((dias) => (
                        <button
                          key={dias}
                          type="button"
                          onClick={() => setDiasAviso(dias)}
                          className={cn(
                            "rounded-full border px-3 py-1 text-xs font-bold transition-colors",
                            diasAviso === dias
                              ? "border-blue-200 bg-blue-50 text-blue-700"
                              : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50",
                          )}
                        >
                          {dias} dias
                        </button>
                      ))}
                    </div>

                    <Secao
                      titulo="Vencidas"
                      descricao="Páginas fora do ar por mensalidade vencida. As mais atrasadas primeiro."
                      total={vencidasFiltradas.length}
                      tom="vermelho"
                      vazio="Nenhuma mensalidade vencida."
                    >
                      {vencidasFiltradas.map((loja) => (
                        <LojaLinha key={loja.uuid} loja={loja} mostrarPrazo onCobranca={irParaCobranca} />
                      ))}
                    </Secao>

                    <Secao
                      titulo="Por vencer, sem pagamento recorrente"
                      descricao="Vencem na janela escolhida e não têm assinatura ativa. As mais próximas primeiro."
                      total={porVencerFiltradas.length}
                      tom="ambar"
                      vazio="Nenhuma loja por vencer sem pagamento recorrente."
                    >
                      {porVencerFiltradas.map((loja) => (
                        <LojaLinha key={loja.uuid} loja={loja} mostrarPrazo onCobranca={irParaCobranca} />
                      ))}
                    </Secao>
                  </div>
                )}

                {aba === "lojas" && (
                  <Secao
                    titulo="Todas as lojas"
                    total={lojasFiltradas.length}
                    vazio="Nenhuma loja encontrada."
                  >
                    {lojasFiltradas.map((loja) => (
                      <LojaLinha
                        key={loja.uuid}
                        loja={loja}
                        mostrarPrazo={loja.situacao !== "sem_validade"}
                        onCobranca={irParaCobranca}
                      />
                    ))}
                  </Secao>
                )}

                {aba === "pontos" && (
                  <Secao
                    titulo="Todos os pontos turísticos"
                    total={pontosFiltrados.length}
                    vazio="Nenhum ponto turístico encontrado."
                  >
                    {pontosFiltrados.map((ponto) => (
                      <PontoLinha key={ponto.uuid} ponto={ponto} />
                    ))}
                  </Secao>
                )}
              </div>
            </>
          )}
        </div>
      </main>
    </div>
  );
}

/**
 * Só administrador (VENDEDOR.ADM) entra. O guarda roda ANTES do conteúdo para que um
 * vendedor terceirizado nem dispare as consultas admin/* (que responderiam 403).
 */
export default function AdminPage() {
  const { data: acesso, isLoading, isError } = useAdminAcesso();

  if (isLoading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
      </div>
    );
  }

  if (isError || acesso?.adm !== true) {
    return <Navigate to="/vendedor" replace />;
  }

  return <AdminConteudo />;
}

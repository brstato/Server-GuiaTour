import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { isAxiosError } from "axios";
import { adminService } from "../services/adminService";

const STALE_MS = 30_000;

/**
 * Controller da administração geral. As três consultas são independentes (cada aba usa a
 * sua), mas o erro e o carregamento são consolidados para a página mostrar um estado só.
 */
export function useAdminController() {
  const [diasAviso, setDiasAviso] = useState(7);

  const lojasQuery = useQuery({
    queryKey: ["admin", "lojas"],
    queryFn: () => adminService.listLojas(),
    staleTime: STALE_MS,
  });

  const pontosQuery = useQuery({
    queryKey: ["admin", "pontos"],
    queryFn: () => adminService.listPontos(),
    staleTime: STALE_MS,
  });

  const mensalidadesQuery = useQuery({
    queryKey: ["admin", "mensalidades", diasAviso],
    queryFn: () => adminService.getMensalidades(diasAviso),
    staleTime: STALE_MS,
  });

  const error = lojasQuery.error ?? pontosQuery.error ?? mensalidadesQuery.error ?? null;
  const acessoNegado = isAxiosError(error) && error.response?.status === 403;

  const reload = () => {
    void lojasQuery.refetch();
    void pontosQuery.refetch();
    void mensalidadesQuery.refetch();
  };

  return {
    lojas: lojasQuery.data ?? [],
    pontos: pontosQuery.data ?? [],
    vencidas: mensalidadesQuery.data?.vencidas ?? [],
    porVencer: mensalidadesQuery.data?.por_vencer ?? [],
    diasAviso,
    setDiasAviso,
    isLoading:
      lojasQuery.isLoading || pontosQuery.isLoading || mensalidadesQuery.isLoading,
    isFetching:
      lojasQuery.isFetching || pontosQuery.isFetching || mensalidadesQuery.isFetching,
    error,
    acessoNegado,
    reload,
  };
}

import { useQuery } from "@tanstack/react-query";
import { adminService } from "../services/adminService";

/**
 * Se o vendedor logado é administrador. `data?.adm === true` libera o botão e a página da
 * administração; vendedor terceirizado (adm = false) não vê nenhum dos dois.
 */
export function useAdminAcesso() {
  return useQuery({
    queryKey: ["vendor", "perfil"],
    queryFn: () => adminService.getAcesso(),
    staleTime: 5 * 60_000,
  });
}

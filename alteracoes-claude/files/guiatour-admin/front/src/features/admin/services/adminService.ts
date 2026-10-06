import { api } from "@/services/api";
import type { AdminLoja, AdminMensalidades, AdminPonto } from "../types";

class AdminService {
  /**
   * Diz se o vendedor logado é administrador (VENDEDOR.ADM). Responde 200 para qualquer
   * vendedor, então serve para decidir se o botão da administração aparece sem gerar 403.
   * Quem decide o acesso de verdade é o servidor, em cada rota admin/*.
   */
  async getAcesso(): Promise<{ adm: boolean }> {
    const response = await api.get<{ adm: boolean }>("vendedor/perfil");
    return response.data;
  }

  /** Todas as lojas cadastradas (de todos os vendedores). */
  async listLojas(): Promise<AdminLoja[]> {
    const response = await api.get<{ itens: AdminLoja[] }>("admin/lojas");
    return response.data.itens;
  }

  /** Todos os pontos turísticos (de todos os vendedores). */
  async listPontos(): Promise<AdminPonto[]> {
    const response = await api.get<{ itens: AdminPonto[] }>("admin/pontos-turisticos");
    return response.data.itens;
  }

  /** Lojas vencidas e lojas por vencer (sem pagamento recorrente) na janela de `dias`. */
  async getMensalidades(dias: number): Promise<AdminMensalidades> {
    const response = await api.get<AdminMensalidades>("admin/mensalidades", {
      params: { dias },
    });
    return response.data;
  }
}

export const adminService = new AdminService();

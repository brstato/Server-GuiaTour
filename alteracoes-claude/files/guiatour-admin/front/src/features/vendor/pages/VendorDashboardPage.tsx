import { useState, useMemo } from "react";
import { Plus, Search, Loader2, MapPin, CreditCard, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useVendorController } from "../hooks/useVendorController";
import { useTouristSpotController } from "../hooks/useTouristSpotController";
import { useAdminAcesso } from "@/features/admin/hooks/useAdminAcesso";
import { VendorHeader } from "../components/VendorHeader";
import { useNavigate } from "react-router-dom";

export default function VendorDashboardPage() {
  const { 
    vendorMerchants,
    isLoadingVendorMerchants,
  } = useVendorController();
  
  const {
    spots,
    isLoadingSpots,
  } = useTouristSpotController();

  const { data: acesso } = useAdminAcesso();
  const isAdm = acesso?.adm === true;

  const navigate = useNavigate();
  const [searchTerm, setSearchTerm] = useState("");
  const [searchTermSpots, setSearchTermSpots] = useState("");

  const filteredMerchants = useMemo(() => {
    if (!searchTerm.trim()) return vendorMerchants;
    
    const term = searchTerm.toLowerCase();
    return vendorMerchants.filter(
      (item) => 
        item.nome.toLowerCase().includes(term) || 
        item.slug.toLowerCase().includes(term)
    );
  }, [vendorMerchants, searchTerm]);

  const filteredSpots = useMemo(() => {
    if (!searchTermSpots.trim()) return spots;
    
    const term = searchTermSpots.toLowerCase();
    return spots.filter(
      (item) => 
        item.nome.toLowerCase().includes(term) || 
        item.slug.toLowerCase().includes(term)
    );
  }, [spots, searchTermSpots]);

  const handleVisualizar = (uuid: string) => {
    localStorage.setItem("id_loja", uuid);
    navigate('/vendedor/comerciantes/novo');
  };

  const handleNovoComerciante = () => {
    localStorage.removeItem("id_loja");
    navigate('/vendedor/comerciantes/novo');
  };

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col">
      <VendorHeader />

      <main className="flex-1 overflow-y-auto">
        <div className="max-w-7xl mx-auto px-6 py-8">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-10">
            <div>
              <h1 className="text-3xl font-extrabold text-slate-900 tracking-tight">
                Painel do Vendedor
              </h1>
              <p className="text-slate-500 mt-1">
                Gerencie seus comerciantes e pontos turísticos e acompanhe o crescimento da rede.
              </p>
            </div>

            <div className="flex flex-col sm:flex-row gap-3">
              {isAdm && (
                <Button 
                  variant="outline"
                  onClick={() => navigate('/vendedor/admin')}
                  className="gap-2 text-slate-700 border-slate-200 hover:bg-slate-50 font-bold h-11 px-6 shadow-sm"
                >
                  <ShieldCheck className="h-4.5 w-4.5" />
                  Administração
                </Button>
              )}
              <Button 
                variant="outline"
                onClick={() => {
                  localStorage.removeItem("id_ponto_turistico");
                  navigate('/vendedor/pontos/novo');
                }}
                className="gap-2 text-blue-600 border-blue-100 hover:bg-blue-50 font-bold h-11 px-6 shadow-sm"
              >
                <Plus className="h-4.5 w-4.5" />
                <MapPin className="h-4 w-4" />
                Novo Ponto Turístico
              </Button>
              <Button 
                onClick={handleNovoComerciante}
                className="gap-2 bg-blue-600 hover:bg-blue-700 shadow-md shadow-blue-100 h-11 px-6 font-bold"
              >
                <Plus className="h-4.5 w-4.5" />
                Novo Comerciante
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-8">
            {/* Comércios Criados */}
            <div className="bg-white rounded-2xl border border-slate-200/60 shadow-xs p-6">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                <h2 className="text-xl font-bold text-slate-800">
                  Comércios Criados
                </h2>
                <div className="relative w-full sm:w-72">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input 
                    placeholder="Buscar comércio..." 
                    className="pl-10 h-10 border-slate-200 focus-visible:ring-blue-500 bg-slate-50/50"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                  />
                </div>            
              </div>
              
              {isLoadingVendorMerchants ? (
                <div className="flex justify-center py-10">
                  <Loader2 className="h-8 w-8 text-blue-500 animate-spin" />
                </div>
              ) : filteredMerchants.length > 0 ? (
                <div className="space-y-3 max-h-[300px] overflow-y-auto pr-2 scrollbar-thin scrollbar-thumb-slate-200 scrollbar-track-transparent">
                  {filteredMerchants.map((item) => (
                    <div key={item.uuid} className="flex items-center justify-between p-4 bg-slate-50 hover:bg-slate-100/80 transition-colors rounded-xl border border-slate-100 group">
                      <div className="min-w-0 flex-1">
                        <h3 className="font-bold text-slate-900 truncate">{item.nome}</h3>
                        <p className="text-sm text-slate-500 truncate">/{item.slug}</p>
                      </div>
                      <div className="flex shrink-0 items-center gap-2 ml-4">
                        <Button 
                          variant="outline"
                          onClick={() => navigate(`/vendedor/comerciantes/${item.uuid}/assinatura`)}
                          className="bg-white text-slate-700 border-slate-200 hover:bg-slate-50 font-bold shrink-0 shadow-sm gap-1.5"
                        >
                          <CreditCard className="w-4 h-4 text-slate-500" />
                          <span className="hidden sm:inline">Cobrança</span>
                        </Button>
                        <Button 
                          variant="outline"
                          onClick={() => handleVisualizar(item.uuid)}
                          className="bg-white text-blue-600 border-blue-100 hover:bg-blue-50 hover:border-blue-200 font-bold shrink-0 shadow-sm"
                        >
                          Visualizar
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-slate-500 text-center py-10">Nenhum comércio encontrado.</p>
              )}
            </div>

            {/* Pontos Turísticos */}
            <div className="bg-white rounded-2xl border border-slate-200/60 shadow-xs p-6 mb-8">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                <h2 className="text-xl font-bold text-slate-800">
                  Pontos Turísticos
                </h2>
                <div className="relative w-full sm:w-72">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input 
                    placeholder="Buscar ponto turístico..." 
                    className="pl-10 h-10 border-slate-200 focus-visible:ring-blue-500 bg-slate-50/50"
                    value={searchTermSpots}
                    onChange={(e) => setSearchTermSpots(e.target.value)}
                  />
                </div>            
              </div>
              
              {isLoadingSpots ? (
                <div className="flex justify-center py-10">
                  <Loader2 className="h-8 w-8 text-blue-500 animate-spin" />
                </div>
              ) : filteredSpots.length > 0 ? (
                <div className="space-y-3 max-h-[300px] overflow-y-auto pr-2 scrollbar-thin scrollbar-thumb-slate-200 scrollbar-track-transparent">
                  {filteredSpots.map((item) => (
                    <div key={item.uuid} className="flex items-center justify-between p-4 bg-slate-50 hover:bg-slate-100/80 transition-colors rounded-xl border border-slate-100 group">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <h3 className="font-bold text-slate-900 truncate">{item.nome}</h3>
                          <span className={cn(
                            "text-[10px] font-bold uppercase tracking-wider rounded-full px-2 py-1",
                            item.ativo ? "bg-green-50 text-green-600" : "bg-slate-100 text-slate-500"
                          )}>
                            {item.ativo ? "Ativo" : "Inativo"}
                          </span>
                        </div>
                        <p className="text-sm text-slate-500 truncate">/{item.slug} • {item.categoria}</p>
                      </div>
                      <Button 
                        variant="outline"
                        onClick={() => {
                          localStorage.setItem("id_ponto_turistico", item.uuid);
                          navigate(`/vendedor/pontos/${item.uuid}`);
                        }}
                        className="ml-4 bg-white text-blue-600 border-blue-100 hover:bg-blue-50 hover:border-blue-200 font-bold shrink-0 shadow-sm"
                      >
                        Editar
                      </Button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-slate-500 text-center py-10">Nenhum ponto turístico encontrado.</p>
              )}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

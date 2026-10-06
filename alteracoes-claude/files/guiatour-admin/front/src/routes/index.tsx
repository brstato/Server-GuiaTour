import { createBrowserRouter, RouterProvider, Navigate } from "react-router-dom";
import { AppLayout } from "../layouts/AppLayout";
import { PerfilLayout } from "../layouts/PerfilLayout";
import { PortfolioPage } from "../features/portfolio/pages/PortfolioPage";
import { MetricasPage } from "../features/portfolio/pages/MetricasPage";
import { LoginPage } from "../features/auth/pages/LoginPage";
import { VendorRoute } from "../features/vendor/components/VendorRoute";
import VendorDashboardPage from "../features/vendor/pages/VendorDashboardPage";
import MerchantCreatePage from "../features/vendor/pages/MerchantCreatePage";
import TouristSpotFormPage from "../features/vendor/pages/TouristSpotFormPage";
import VendorBillingPage from "../features/vendor/pages/VendorBillingPage";
import AdminPage from "../features/admin/pages/AdminPage";
import { BillingPage } from "../features/billing/pages/BillingPage";

const router = createBrowserRouter([
  {
    path: "/",
    element: <LoginPage />,
  },
  {
    path: "/vendedor",
    element: <VendorRoute />,
    children: [
      {
        index: true,
        element: <VendorDashboardPage />,
      },
      {
        path: "comerciantes/novo",
        element: <MerchantCreatePage />,
      },
      {
        path: "comerciantes/:uuid/assinatura",
        element: <VendorBillingPage />,
      },
      {
        path: "admin",
        element: <AdminPage />,
      },
      {
        path: "pontos/novo",
        element: <TouristSpotFormPage />,
      },
      {
        path: "pontos/:uuid",
        element: <TouristSpotFormPage />,
      },
    ],
  },
  {
    element: <AppLayout />,
    children: [
      {
        path: "/loja/:id",
        element: <PerfilLayout />,
        children: [
          {
            index: true,
            element: <Navigate to="editar" replace />,
          },
          {
            path: "editar",
            element: <PortfolioPage />,
          },
          {
            path: "metricas",
            element: <MetricasPage />,
          },
          {
            path: "assinatura",
            element: <BillingPage />,
          },
        ],
      },
      {
        path: "/portfolio",
        element: <Navigate to="/loja/me/editar" replace />,
      },
      {
        path: "/dashboard",
        element: <Navigate to="/portfolio" replace />,
      },
      {
        path: "*",
        element: <Navigate to="/portfolio" replace />,
      },
    ],
  },
]);

export function AppRoutes() {
  return <RouterProvider router={router} />;
}

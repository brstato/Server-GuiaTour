unit urouter;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, uTlogincontroller, utlojacontroller,
  uportifoliocontroller, utvendedorcontroller, utPontoscontroller,
  utguiatourpublicocontroller, utasaascontroller,
  utadmincontroller,                                         // <-- NOVO (administração geral)
  fpjson;
type

  { tAppRouter }

  tAppRouter = class
  private
      public
    class var anamnese_html: string;
    class procedure load_routes();
  end;

implementation



{ tAppRouter }


class procedure tAppRouter.load_routes();
begin
    TLoginController.RegisterRoutes;
    TlojaController.RegisterRoutes;
    TPortifolioController.RegisterRoutes;
    TVendedorController.RegisterRoutes;
    TPontoTuristicoController.RegisterRoutes;
    TGuiaTourPublicoController.RegisterRoutes;
    TAsaasController.RegisterRoutes;
    TAdminController.RegisterRoutes;                         // <-- NOVO
end;


end.

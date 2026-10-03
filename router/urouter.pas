unit urouter;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse, uTlogincontroller, utlojacontroller,
  uportifoliocontroller, utvendedorcontroller, utPontoscontroller,
  utguiatourpublicocontroller,            // <-- NOVO
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

procedure onStatus(Req: THorseRequest; Res: THorseResponse; next: TNextProc);
begin
     Res.ContentType('text/html').Send('<h1>Server on-line</h1>');
end;

class procedure tAppRouter.load_routes();
begin
    TLoginController.RegisterRoutes;
    TlojaController.RegisterRoutes;
    TPortifolioController.RegisterRoutes;
    TVendedorController.RegisterRoutes;
    TPontoTuristicoController.RegisterRoutes;
    TGuiaTourPublicoController.RegisterRoutes;   // <-- NOVO
end;


end.



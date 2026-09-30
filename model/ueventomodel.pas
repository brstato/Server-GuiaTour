unit ueventomodel;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, ugetdata;

type

  { TEventoModel }

  TEventoModel = class
  public
    // Grava 1 clique. Se a loja não existir ou estiver vencida, não grava nada
    // (sem erro). pontoSlug pode ser ''. Exceções de banco sobem para o chamador.
    class procedure Registrar(const lojaSlug, pontoSlug, tipo: string);
  end;

implementation

{ TEventoModel }

class procedure TEventoModel.Registrar(const lojaSlug, pontoSlug, tipo: string);
begin
  // Parâmetros posicionais, na ordem do texto: :ponto, :tipo, :loja
  TGetData.getData(
    'INSERT INTO evento_clique (id_loja, id_ponto, tipo) ' +
    'SELECT l.id, ' +
    '       (SELECT FIRST 1 p.id FROM ponto_turistico p WHERE p.slug = :ponto), ' +
    '       CAST(:tipo AS VARCHAR(10)) ' +
    'FROM loja l ' +
    'WHERE l.slug = :loja AND l.validade >= CURRENT_DATE;',
    [pontoSlug, tipo, lojaSlug]
  );
end;

end.

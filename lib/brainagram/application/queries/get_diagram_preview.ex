defmodule Brainagram.Application.Queries.GetDiagramPreview do
  @moduledoc """
  A miniatura de um diagrama: o SVG do estado final, como o "Exportar SVG".

  É uma query à parte, e não um campo da listagem, para a listagem continuar
  sem o fonte: cada card pede a sua miniatura quando aparece na tela, e o
  navegador guarda em cache enquanto o diagrama não muda (`updated_at`).
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.GetDiagramPreview,
    fields: [slug: :string],
    required: [:slug]
end

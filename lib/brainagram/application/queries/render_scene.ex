defmodule Brainagram.Application.Queries.RenderScene do
  @moduledoc """
  Compila um fonte avulso em cena, sem tocar no banco.

  É a query que roda a cada tecla digitada no editor (com debounce). Modelá-la
  como query, e não como um comando ou uma chamada direta ao domínio, mantém a
  camada web falando uma linguagem só — e deixa explícito no tipo de retorno
  que compilar não persiste nada.
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.RenderScene,
    fields: [source: :string],
    required: [:source]
end

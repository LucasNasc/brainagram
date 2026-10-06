defmodule Brainagram.Application.Queries.EditSource do
  @moduledoc """
  Aplica um gesto de autoria a um fonte avulso e compila o resultado — sem
  tocar no banco.

  É o par de `RenderScene` para o canvas: o editor guarda o texto da sessão
  (salvo ou não) e, a cada gesto, pede o texto novo *e* a cena dele numa ida
  só. Persistir continua sendo o "Salvar" — e, para diagramas já salvos, os
  comandos de autoria (`PinNode`, `AddNode`…) fazem o mesmo caminho pelo
  agregado.

  `op` é um dos nomes de `Authoring.operations/0`; `params` chega como veio da
  interface (chaves em string).
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.EditSource,
    fields: [source: :string, op: :string, params: :map],
    required: [:source, :op]

  @impl true
  def changeset(changeset) do
    Ecto.Changeset.validate_inclusion(
      changeset,
      :op,
      Brainagram.Domain.Diagramming.Authoring.operations()
    )
  end
end

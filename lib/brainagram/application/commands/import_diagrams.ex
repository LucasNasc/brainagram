defmodule Brainagram.Application.Commands.ImportDiagrams do
  @moduledoc """
  Importa arquivos para a área de gestão, de uma vez:

    * `.brain` (um diagrama exportado daqui), Mermaid ou PlantUML — cada um
      vira um diagrama no projeto `project` (vazio: sem projeto);
    * pacote `.json` (`Bundle`) — recria os projetos dele (reaproveitando um
      de mesmo nome que já exista) e os diagramas em cada um.

  `files`: `[%{"name" => nome, "content" => texto}]`. Um arquivo com problema
  não impede os outros: o resultado conta o que entrou e o que falhou, e por quê.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.ImportDiagrams,
    fields: [files: {:array, :map}, project: :string],
    required: [:files]
end

defmodule Brainagram.Domain.Diagramming.Errors do
  @moduledoc """
  Tradução dos erros do domínio para texto.

  O domínio devolve átomos (`:invalid_slug`, `:not_found`) — não frases. Esta é
  a versão em português para quem roda fora da web (tarefas Mix); a interface
  usa `BrainagramWeb.ErrorMessages`, que traduz os mesmos átomos com `gettext`.
  """

  alias Brainagram.Domain.Diagramming.Dsl.ParseError

  @spec describe(term()) :: String.t()
  def describe(:invalid_slug),
    do: "Slug inválido: use de 3 a 64 letras minúsculas, números, - ou _."

  def describe(:title_too_long), do: "Título longo demais."
  def describe(:source_too_large), do: "O diagrama passou do tamanho máximo permitido."
  def describe(:invalid_kind), do: "Tipo de diagrama desconhecido."
  def describe(:invalid_visibility), do: "Visibilidade desconhecida."
  def describe(:not_found), do: "Diagrama não encontrado."
  def describe(:slug_taken), do: "Já existe um diagrama com esse slug."
  def describe(:unknown_node), do: "Esse nó não existe mais no código."
  def describe(:unknown_edge), do: "Essa seta não existe mais no código."
  def describe(:unknown_group), do: "Esse grupo não existe no código."
  def describe(:blank_label), do: "O nome não pode ficar vazio."
  def describe(:invalid_label), do: "O rótulo não pode ter # nem // (viram comentário na DSL)."
  def describe(:invalid_arrow), do: "Tipo de seta desconhecido."
  def describe(:invalid_position), do: "Posição inválida."
  def describe(:blank_project_name), do: "Dê um nome ao projeto."
  def describe(:project_name_too_long), do: "Nome de projeto longo demais (até 60 caracteres)."
  def describe(:invalid_project_color), do: "Cor de projeto desconhecida."
  def describe(:invalid_project), do: "Projeto inválido."
  def describe(:project_not_found), do: "Esse projeto não existe mais."
  def describe(:not_text), do: "O arquivo não é texto (UTF-8)."
  def describe(:invalid_bundle), do: "O pacote .json não é um export do Brainagram."

  def describe(:not_architecture),
    do:
      "Organizar setas vale para diagramas de arquitetura — na sequência as setas já não se cruzam."

  def describe(:invalid_edit),
    do: "Essa edição deixaria o código inválido, então nada foi aplicado."

  def describe(:unknown_operation), do: "Operação de edição desconhecida."

  def describe(:unsupported_format),
    do: "Formato de importação desconhecido (use Mermaid ou PlantUML)."

  def describe(:nothing_to_import), do: "Não encontrei um diagrama para importar."

  def describe({:syntax, [%ParseError{} = first | rest]}) do
    restantes = if rest == [], do: "", else: " (e mais #{length(rest)})"
    "Erro de sintaxe na linha #{first.line}: #{first.message}#{restantes}"
  end

  def describe({:syntax, _}), do: "Erro de sintaxe na DSL."
  def describe(other), do: "Não foi possível concluir a operação (#{inspect(other)})."
end

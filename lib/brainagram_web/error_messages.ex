defmodule BrainagramWeb.ErrorMessages do
  @moduledoc """
  Erros do domínio em texto, no idioma da interface.

  O domínio devolve átomos (`:not_found`) e erros de sintaxe com `code` e
  `bindings` — nunca frase para a tela. `Domain.Diagramming.Errors` continua
  existindo para quem roda fora da web (tarefas Mix); aqui cada caso passa
  pelo `gettext`, então o idioma é o da pessoa.
  """

  use Gettext, backend: BrainagramWeb.Gettext

  alias Brainagram.Domain.Diagramming.Dsl.ParseError

  @spec describe(term()) :: String.t()
  def describe(:invalid_slug),
    do: gettext("Slug inválido: use de 3 a 64 letras minúsculas, números, - ou _.")

  def describe(:title_too_long), do: gettext("Título longo demais.")

  def describe(:source_too_large),
    do: gettext("O diagrama passou do tamanho máximo permitido.")

  def describe(:invalid_kind), do: gettext("Tipo de diagrama desconhecido.")
  def describe(:invalid_visibility), do: gettext("Visibilidade desconhecida.")
  def describe(:not_found), do: gettext("Diagrama não encontrado.")
  def describe(:slug_taken), do: gettext("Já existe um diagrama com esse slug.")
  def describe(:unknown_node), do: gettext("Esse nó não existe mais no código.")
  def describe(:unknown_edge), do: gettext("Essa seta não existe mais no código.")
  def describe(:unknown_group), do: gettext("Esse grupo não existe no código.")
  def describe(:blank_label), do: gettext("O nome não pode ficar vazio.")

  def describe(:invalid_label),
    do: gettext("O rótulo não pode ter # nem // (viram comentário na DSL).")

  def describe(:invalid_arrow), do: gettext("Tipo de seta desconhecido.")
  def describe(:invalid_position), do: gettext("Posição inválida.")
  def describe(:blank_project_name), do: gettext("Dê um nome ao projeto.")

  def describe(:project_name_too_long),
    do: gettext("Nome de projeto longo demais (até 60 caracteres).")

  def describe(:invalid_project_color), do: gettext("Cor de projeto desconhecida.")
  def describe(:invalid_project), do: gettext("Projeto inválido.")
  def describe(:project_not_found), do: gettext("Esse projeto não existe mais.")
  def describe(:not_text), do: gettext("O arquivo não é texto (UTF-8).")

  def describe(:invalid_bundle),
    do: gettext("O pacote .json não é um export do Brainagram.")

  def describe(:not_architecture),
    do:
      gettext(
        "Organizar setas vale para diagramas de arquitetura — na sequência as setas já não se cruzam."
      )

  def describe(:invalid_edit),
    do: gettext("Essa edição deixaria o código inválido, então nada foi aplicado.")

  def describe(:unknown_operation), do: gettext("Operação de edição desconhecida.")

  def describe(:unsupported_format),
    do: gettext("Formato de importação desconhecido (use Mermaid ou PlantUML).")

  def describe(:nothing_to_import), do: gettext("Não encontrei um diagrama para importar.")

  def describe({:syntax, [%ParseError{} = first | rest]}) do
    message = parse_error(first)

    case length(rest) do
      0 ->
        gettext("Erro de sintaxe na linha %{line}: %{message}",
          line: first.line,
          message: message
        )

      n ->
        ngettext(
          "Erro de sintaxe na linha %{line}: %{message} (e mais 1)",
          "Erro de sintaxe na linha %{line}: %{message} (e mais %{count})",
          n,
          line: first.line,
          message: message
        )
    end
  end

  def describe({:syntax, _}), do: gettext("Erro de sintaxe na DSL.")

  def describe(other),
    do: gettext("Não foi possível concluir a operação (%{reason}).", reason: inspect(other))

  @doc "A mensagem de um erro de sintaxe, traduzida pelo `code`."
  @spec parse_error(ParseError.t()) :: String.t()
  def parse_error(%ParseError{code: code, bindings: b} = error) do
    b = Map.to_list(b)

    case code do
      :pin_outside_layout ->
        gettext("posição fora de um bloco `layout { }`: %{text}", b)

      :unknown_line ->
        gettext("não entendi esta linha: %{text}", b)

      :unknown_kind ->
        gettext("tipo de diagrama desconhecido: %{kind} (use sequence ou architecture)", b)

      :invalid_layout_line ->
        gettext("dentro de `layout` só cabem linhas `id at (x, y)`: %{text}", b)

      :nested_block ->
        gettext("blocos aninhados não são suportados (feche o bloco anterior com `}`)")

      :duplicate_layout ->
        gettext("só pode haver um bloco `layout` por diagrama")

      :unmatched_close ->
        gettext("`}` sem bloco aberto correspondente")

      :unclosed_block ->
        gettext("bloco `%{block}` aberto aqui nunca foi fechado com `}`", b)

      :message_in_group ->
        gettext("mensagens não podem ficar dentro de um `group` — use um `step`")

      :orphan_payload ->
        gettext("`payload` precisa vir logo abaixo de uma mensagem (`a -> b : …`)")

      :unclosed_payload ->
        gettext("payload aberto aqui nunca foi fechado com \"\"\"")

      :invalid_source ->
        gettext("fonte inválido")

      _ ->
        error.message
    end
  end
end

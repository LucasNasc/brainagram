defmodule Brainagram.Application.Message do
  @moduledoc """
  Base comum de comandos e queries.

  Um comando/query é um struct validado na fronteira. A validação usa
  `Ecto.Changeset` sem schema (`{%{}, types}`): é a forma idiomática em Elixir
  de validar um mapa avulso, e traz `Ecto.Changeset` só como biblioteca de
  dados — nenhuma persistência entra junto. Se isso incomodasse, a troca por
  validação à mão ficaria confinada a este módulo.

  Uso:

      defmodule CreateDiagram do
        use Brainagram.Application.Message,
          handler: Handlers.CreateDiagram,
          fields: [source: :string, visibility: :string, slug: :string],
          required: [:source]
      end

  O comando pode refinar a validação sobrescrevendo `changeset/1`.
  """

  @callback handler() :: module()
  @callback new(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  defmacro __using__(opts) do
    handler = Keyword.fetch!(opts, :handler)
    fields = Keyword.fetch!(opts, :fields)
    required = Keyword.get(opts, :required, [])
    keys = Enum.map(fields, &elem(&1, 0))

    quote do
      @behaviour Brainagram.Application.Message

      defstruct unquote(keys)

      @types Map.new(unquote(fields))
      @required unquote(required)

      @type t :: %__MODULE__{}

      @impl true
      def handler, do: unquote(handler)

      @impl true
      def new(attrs \\ %{}) do
        Brainagram.Application.Message.build(__MODULE__, @types, @required, attrs)
      end

      @impl true
      def changeset(changeset), do: changeset

      defoverridable changeset: 1, new: 1
    end
  end

  @doc false
  @spec build(module(), map(), [atom()], map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def build(module, types, required, attrs) do
    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(stringify(attrs), Map.keys(types))
      |> Ecto.Changeset.validate_required(required)
      |> module.changeset()

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, data} -> {:ok, struct!(module, data)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Erros de um changeset no formato `%{campo => [mensagens]}`."
  @spec errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # `cast/3` exige chaves homogêneas; normalizar para string aceita tanto
  # parâmetro de formulário quanto mapa de átomo vindo de teste ou de código.
  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end

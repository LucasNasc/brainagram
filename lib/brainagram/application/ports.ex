defmodule Brainagram.Application.Ports do
  @moduledoc """
  Resolução das portas em tempo de execução.

  As implementações vêm de `config/`, nunca de um `alias` para dentro de
  `infrastructure/`. É isso que mantém a regra de dependência de pé: a camada
  de aplicação conhece os *behaviours*, e a configuração é que amarra o
  concreto. Trocar Postgres por outra coisa, ou plugar um repositório em
  memória num teste, é uma linha de config.

  `Application` aqui é o módulo da stdlib do Elixir — o módulo OTP deste
  projeto foi renomeado para `Brainagram.Runtime` justamente para liberar o
  namespace `Brainagram.Application` para esta camada.
  """

  @spec diagram_repository() :: module()
  def diagram_repository, do: fetch!(:diagram_repository)

  @spec diagram_reader() :: module()
  def diagram_reader, do: fetch!(:diagram_reader)

  @spec project_repository() :: module()
  def project_repository, do: fetch!(:project_repository)

  @spec project_reader() :: module()
  def project_reader, do: fetch!(:project_reader)

  @spec event_bus() :: module()
  def event_bus, do: fetch!(:event_bus)

  @spec example_catalog() :: module()
  def example_catalog, do: fetch!(:example_catalog)

  @doc """
  Substitui uma porta apenas para o processo atual. **Uso em teste.**

  É a costura que permite testar handler com repositório em memória sem tornar
  a suíte serial: `Application.put_env/3` é global e obrigaria `async: false`
  em todo teste que trocasse uma porta. O dicionário de processo é local ao
  teste, então cada um escolhe suas implementações em paralelo.

  A alternativa idiomática seria Mox. Ela é melhor quando se quer verificar
  *interação* (foi chamado, com quais argumentos); aqui os testes verificam
  *resultado*, e um fake escrito à mão diz mais sobre o contrato da porta do
  que uma expectativa configurada.
  """
  @spec override(atom(), module()) :: :ok
  def override(key, module) do
    Process.put({__MODULE__, key}, module)
    :ok
  end

  defp fetch!(key) do
    case Process.get({__MODULE__, key}) do
      nil -> :brainagram |> Application.fetch_env!(:ports) |> Keyword.fetch!(key)
      module -> module
    end
  end
end

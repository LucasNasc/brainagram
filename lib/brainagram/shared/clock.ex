defmodule Brainagram.Shared.Clock do
  @moduledoc """
  Relógio injetável.

  O domínio nunca chama `DateTime.utc_now/0` direto — chama aqui. O motivo é
  testabilidade: um teste que precisa afirmar "`updated_at` avançou" consegue
  congelar ou adiantar o tempo trocando a implementação em config, sem
  `Process.sleep/1` espalhado pela suíte.
  """

  @callback now() :: DateTime.t()

  @spec now() :: DateTime.t()
  def now, do: impl().now()

  defp impl do
    Application.get_env(:brainagram, :clock, __MODULE__.System)
  end

  defmodule System do
    @moduledoc "Relógio real, com precisão de segundo (o que o Postgres guarda)."
    @behaviour Brainagram.Shared.Clock

    @impl true
    def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  end
end

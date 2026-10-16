defmodule Brainagram.Infrastructure.Cache.Store do
  @moduledoc """
  O armazenamento do modo demo: duas tabelas ETS, sem banco de dados.

  Liga com `BRAINAGRAM_DEMO=true` (veja `config/runtime.exs`). É um playground:
  tudo vive na memória do servidor, é visível para qualquer visitante e some
  quando o processo reinicia. Para não crescer sem limite num servidor público:

    * um diagrama sem alteração há mais de `:ttl` (padrão 24 h) é apagado, e
      projetos vazios vão junto;
    * acima de `:max_diagrams` (padrão 500), os mais antigos saem primeiro.

  As tabelas são `:public` com leitura concorrente: os adaptadores leem e
  escrevem direto nelas, e este processo só é dono das tabelas e faz a limpeza
  periódica.
  """

  use GenServer

  @diagrams :brainagram_cache_diagrams
  @projects :brainagram_cache_projects
  @sweep_every :timer.minutes(10)

  def diagrams, do: @diagrams
  def projects, do: @projects

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Um id único e crescente, no lugar da sequência do banco."
  @spec next_id() :: pos_integer()
  def next_id, do: System.unique_integer([:positive, :monotonic])

  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Aplica as regras de validade e de tamanho agora (também usado nos testes)."
  def sweep, do: GenServer.call(__MODULE__, :sweep)

  @impl true
  def init(opts) do
    for table <- [@diagrams, @projects] do
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end

    config = Application.get_env(:brainagram, __MODULE__, [])
    ttl = Keyword.get(opts, :ttl, Keyword.get(config, :ttl, :timer.hours(24)))
    max = Keyword.get(opts, :max_diagrams, Keyword.get(config, :max_diagrams, 500))

    schedule()
    {:ok, %{ttl: ttl, max: max}}
  end

  @impl true
  def handle_call(:sweep, _from, state) do
    do_sweep(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep(state)
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :sweep, @sweep_every)

  defp do_sweep(%{ttl: ttl, max: max}) do
    cutoff = DateTime.add(now(), -ttl, :millisecond)

    rows = :ets.tab2list(@diagrams) |> Enum.map(&elem(&1, 1))
    {expired, alive} = Enum.split_with(rows, &(DateTime.compare(&1.updated_at, cutoff) == :lt))

    overflow =
      alive
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> Enum.drop(max)

    Enum.each(expired ++ overflow, &:ets.delete(@diagrams, &1.slug))

    used =
      for {_slug, d} <- :ets.tab2list(@diagrams),
          d.project_slug,
          into: MapSet.new(),
          do: d.project_slug

    for {slug, p} <- :ets.tab2list(@projects),
        not MapSet.member?(used, slug),
        DateTime.compare(p.updated_at, cutoff) == :lt do
      :ets.delete(@projects, slug)
    end

    :ok
  end
end

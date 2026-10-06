# mix run priv/repo/seeds.exs
#
# Popula o banco com os exemplos do catálogo, passando pelo mesmo comando que a
# interface usa. Seed que escreve direto na tabela é seed que cria estado que o
# domínio jamais produziria.

alias Brainagram.Application.Bus
alias Brainagram.Application.Commands.CreateDiagram
alias Brainagram.Application.Ports
alias Brainagram.Application.Queries.GetDiagramBySlug

for example <- Ports.example_catalog().all() do
  case Bus.ask(GetDiagramBySlug, %{slug: example.slug}) do
    {:ok, existing} ->
      IO.puts("já existe /d/#{existing.slug} — #{existing.title}")

    {:error, :not_found} ->
      case Bus.dispatch(CreateDiagram, %{slug: example.slug, source: example.source}) do
        {:ok, slug} -> IO.puts("criado  /d/#{slug} — #{example.name}")
        {:error, reason} -> IO.puts("falhou  #{example.slug}: #{inspect(reason)}")
      end
  end
end

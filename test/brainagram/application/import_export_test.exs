defmodule Brainagram.Application.ImportExportTest do
  @moduledoc """
  Exportar e importar diagramas feitos aqui: `.brain` (um diagrama) e o
  pacote `.json` (vários, com os projetos). Contra o Postgres, porque o pacote
  passa pelos leitores de verdade.
  """

  use Brainagram.DataCase, async: true

  alias Brainagram.Application.{Bundle, Bus}

  alias Brainagram.Application.Commands.{
    CreateDiagram,
    CreateProject,
    ImportDiagrams,
    StartDiagram
  }

  alias Brainagram.Application.Queries.{ExportBundle, GetDiagramBySlug, ListProjects}
  alias Brainagram.Domain.Diagramming.Import

  defp detail(slug) do
    {:ok, detail} = Bus.ask(GetDiagramBySlug, %{slug: slug})
    detail
  end

  defp project_names do
    {:ok, %{projects: projects}} = Bus.ask(ListProjects)
    Enum.map(projects, & &1.name)
  end

  describe "Bundle" do
    test "vai e volta; slugs de origem não são reaproveitados, só a referência interna" do
      rows = [
        %{
          slug: "a1",
          title: "Checkout",
          source: ~s(diagram sequence "Checkout"\na -> b),
          visibility: "private",
          project: "p1",
          project_name: "Pagamentos",
          project_color: "teal"
        },
        %{
          slug: "b2",
          title: "Solto",
          source: "c -> d",
          visibility: "public",
          project: nil,
          project_name: nil,
          project_color: nil
        }
      ]

      json = Bundle.encode(rows, ~U[2026-09-29 12:00:00Z])
      assert Bundle.bundle?(json)

      assert {:ok,
              %{projects: [%{key: "p1", name: "Pagamentos", color: "teal"}], diagrams: [d1, d2]}} =
               Bundle.decode(json)

      assert d1 == %{
               title: "Checkout",
               source: ~s(diagram sequence "Checkout"\na -> b),
               visibility: "private",
               project: "p1"
             }

      assert d2.project == nil
    end

    test "JSON que não é nosso não é pacote" do
      assert {:error, :invalid_bundle} = Bundle.decode(~s({"a": 1}))
      assert {:error, :invalid_bundle} = Bundle.decode("não é json")
      refute Bundle.bundle?(~s({"format": "outro", "diagrams": []}))
    end

    test "nome do arquivo" do
      assert Bundle.filename("Pagamentos & Cobrança", ~U[2026-09-29 12:00:00Z]) ==
               "brainagram-pagamentos-cobranca-2026-09-29.json"
    end
  end

  describe "detecção do formato" do
    test "um .brain é Brainagram; cabeçalhos de Mermaid e PlantUML continuam mandando" do
      assert Import.detect(~s(diagram sequence "X"\na ->> b : oi)) == :brainagram
      assert Import.detect("sequenceDiagram\n  A->>B: oi") == :mermaid
      assert Import.detect("@startuml\nA -> B : oi\n@enduml") == :plantuml

      assert {:ok, %{format: :brainagram, source: "a -> b"}} =
               Import.convert("a -> b", :brainagram)
    end
  end

  describe "exportar" do
    test "um projeto, os sem projeto ou todos — com o fonte inteiro" do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Pagamentos", color: "teal"})
      {:ok, _} = Bus.dispatch(StartDiagram, %{title: "Checkout", project: project})

      {:ok, _} =
        Bus.dispatch(CreateDiagram, %{
          source: ~s(diagram sequence "Solto"\na -> b\n  payload: {"x": 1})
        })

      assert {:ok, %{json: json, filename: filename, count: 1}} =
               Bus.ask(ExportBundle, %{project: project})

      assert filename =~ ~r/^brainagram-pagamentos-\d{4}-\d{2}-\d{2}\.json$/
      {:ok, bundle} = Bundle.decode(json)
      assert [%{name: "Pagamentos", color: "teal"}] = bundle.projects
      assert [%{title: "Checkout"}] = bundle.diagrams

      assert {:ok, %{json: none}} = Bus.ask(ExportBundle, %{project: "none"})
      {:ok, %{diagrams: [loose]}} = Bundle.decode(none)
      assert loose.source =~ ~s(payload: {"x": 1})

      assert {:ok, %{count: all}} = Bus.ask(ExportBundle, %{project: ""})
      assert all >= 2

      assert {:error, :project_not_found} = Bus.ask(ExportBundle, %{project: "nao-existe"})
    end
  end

  describe "importar" do
    test ".brain entra no projeto escolhido; sem título, o nome do arquivo vira título" do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Destino"})

      files = [
        %{"name" => "checkout.brain", "content" => ~s(diagram sequence "Checkout"\na -> b\n)},
        %{"name" => "fluxo de login.brain", "content" => "user -> app : credenciais\n"}
      ]

      assert {:ok, %{created: [a, b], failed: [], projects: []}} =
               Bus.dispatch(ImportDiagrams, %{files: files, project: project})

      assert a.title == "Checkout"
      assert b.title == "fluxo de login"
      assert detail(a.slug).project == project
      assert detail(b.slug).source =~ ~s(diagram sequence "fluxo de login")
    end

    test "Mermaid e PlantUML também entram; arquivo ruim não impede os outros" do
      files = [
        %{"name" => "seq.mmd", "content" => "sequenceDiagram\n  A->>B: oi"},
        %{"name" => "comp.puml", "content" => "@startuml\n[API] --> [DB]\n@enduml"},
        %{"name" => "quebrado.brain", "content" => "diagram mindmap"},
        %{"name" => "binario.brain", "content" => <<0xFF, 0xFE, 0x00>>},
        %{"name" => "outro.json", "content" => ~s({"format": "outro"})}
      ]

      assert {:ok, %{created: created, failed: failed}} =
               Bus.dispatch(ImportDiagrams, %{files: files})

      assert length(created) == 2
      reasons = Map.new(failed, &{&1.name, &1.reason})
      assert {:syntax, _} = reasons["quebrado.brain"]
      assert reasons["binario.brain"] == :not_text
      assert Map.has_key?(reasons, "outro.json")
    end

    test "pacote: recria os projetos (reaproveita um de mesmo nome) e os diagramas em cada um" do
      {:ok, existing} = Bus.dispatch(CreateProject, %{name: "Pagamentos"})

      bundle =
        Bundle.encode(
          [
            %{
              slug: "x",
              title: "Checkout",
              source: ~s(diagram sequence "Checkout"\na -> b),
              visibility: "private",
              project: "p1",
              project_name: "pagamentos ",
              project_color: "teal"
            },
            %{
              slug: "y",
              title: "Deploy",
              source: ~s(diagram architecture "Deploy"\nci -> k8s),
              visibility: "public",
              project: "p2",
              project_name: "Operação",
              project_color: "neon"
            },
            %{
              slug: "z",
              title: "Solto",
              source: ~s(diagram sequence "Solto"\nc -> d),
              visibility: "public",
              project: nil,
              project_name: nil,
              project_color: nil
            }
          ],
          ~U[2026-09-29 12:00:00Z]
        )

      {:ok, target} = Bus.dispatch(CreateProject, %{name: "Destino"})

      assert {:ok, %{created: [checkout, deploy, loose], projects: ["Operação"], failed: []}} =
               Bus.dispatch(ImportDiagrams, %{
                 files: [%{"name" => "brainagram.json", "content" => bundle}],
                 project: target
               })

      # "pagamentos " casou com o "Pagamentos" que já existia
      assert detail(checkout.slug).project == existing
      assert detail(checkout.slug).visibility == "private"
      # cor desconhecida não impede: entra com a padrão
      assert detail(deploy.slug).project_name == "Operação"
      assert detail(loose.slug).project == target
      assert Enum.count(project_names(), &(&1 == "Pagamentos")) == 1
    end

    test "exportar e importar de volta dá os mesmos diagramas" do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Ida e volta", color: "rose"})

      {:ok, slug} =
        Bus.dispatch(StartDiagram, %{title: "Original", kind: "architecture", project: project})

      {:ok, %{json: json}} = Bus.ask(ExportBundle, %{project: project})

      assert {:ok, %{created: [copy]}} =
               Bus.dispatch(ImportDiagrams, %{files: [%{"name" => "b.json", "content" => json}]})

      assert detail(copy.slug).source == detail(slug).source
      assert detail(copy.slug).project == project
      refute copy.slug == slug
    end
  end
end

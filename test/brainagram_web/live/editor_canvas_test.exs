defmodule BrainagramWeb.EditorCanvasTest do
  @moduledoc """
  Spec 001, §12: um teste por gesto do canvas, verificando o fonte resultante.

  O canvas manda `canvas` com `{op, params}`; o servidor aplica a edição
  cirúrgica, devolve o texto novo ao editor (`bg:source`) e a cena (`bg:scene`).
  """

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  @arch """
  diagram architecture "Plataforma"
  # comentário do autor
  service  api "API"
  database pg  "PostgreSQL"

  group "Dados" {
    queue mq "RabbitMQ"
  }

  step "Leitura" {
    api -> pg : SELECT
  }
  """

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => @arch})
    %{view: view}
  end

  defp gesture(view, op, params \\ %{}) do
    render_hook(view, "canvas", %{"op" => op, "params" => params})
    assert_push_event(view, "bg:source", %{source: source})
    source
  end

  defp textarea(view), do: view |> element("#source") |> render()

  test "renomear nó (duplo clique no rótulo)", %{view: view} do
    source = gesture(view, "rename_node", %{"id" => "pg", "label" => "Postgres 16"})

    assert source == String.replace(@arch, ~s("PostgreSQL"), ~s("Postgres 16"))
    assert textarea(view) =~ "Postgres 16"
    assert_push_event(view, "bg:scene", %{scene: %{title: "Plataforma"}})
  end

  test "renomear seta e trocar o tipo", %{view: view} do
    source = gesture(view, "relabel_edge", %{"id" => "e2", "label" => "SELECT *"})
    assert source =~ "api -> pg : SELECT *"

    source = gesture(view, "change_arrow", %{"id" => "e2", "arrow" => "async"})
    assert source =~ "api ->> pg : SELECT *"
  end

  test "criar nó devolve o id para a interface pedir o nome", %{view: view} do
    source = gesture(view, "add_node", %{"x" => 400, "y" => 96})

    assert source =~ ~s(service novo_no "Novo nó")
    assert source =~ "novo_no at (400, 96)"
    assert_push_event(view, "bg:created", %{node_id: "novo_no"})
  end

  test "conectar dois nós no passo selecionado", %{view: view} do
    source = gesture(view, "connect", %{"from" => "pg", "to" => "mq", "step" => 0})

    assert source =~ "  api -> pg : SELECT\n  pg -> mq\n}"
    assert_push_event(view, "bg:created", %{edge_id: _})
  end

  test "Organizar setas grava a arrumação no bloco layout", %{view: view} do
    tangled = Brainagram.Test.Fixtures.tangled_architecture_source()
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => tangled})

    view |> element("#untangle-layout") |> render_click()
    assert_push_event(view, "bg:source", %{source: organized})

    assert organized =~ "layout {"
    assert textarea(view) =~ "layout {"
    refute has_element?(view, "#clear-layout[disabled]")
    assert render(view) =~ "Setas organizadas"
  end

  test "Organizar setas só aparece em arquitetura", %{view: view} do
    assert has_element?(view, "#untangle-layout")

    sequence = ~s(diagram sequence "S"
a -> b : oi
)
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => sequence})
    refute has_element?(view, "#untangle-layout")
  end

  test "arrastar fixa a posição; Soltar posições apaga o bloco", %{view: view} do
    source = gesture(view, "drop", %{"id" => "api", "x" => 96, "y" => 40})
    assert source =~ "layout {\n  api at (96, 40)\n}"
    refute has_element?(view, "#clear-layout[disabled]")

    view |> element("#clear-layout") |> render_click()
    assert_push_event(view, "bg:source", %{source: cleared})
    assert cleared == @arch
    assert has_element?(view, "#clear-layout[disabled]")
  end

  test "payload pela barra da seta (sequência)", %{view: view} do
    sequence = "diagram sequence \"S\"
user -> api : POST /orders
"
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => sequence})

    source = gesture(view, "set_payload", %{"id" => "e1", "payload" => ~s({"items": 3})})
    assert source =~ ~s(user -> api : POST /orders
  payload: {"items": 3})

    assert_push_event(view, "bg:scene", %{scene: %{edges: [%{payload: %{lines: [_]}}]}})
  end

  test "soltar dentro de um grupo move a declaração", %{view: view} do
    source = gesture(view, "drop", %{"id" => "pg", "x" => 300, "y" => 200, "group" => "Dados"})
    assert source =~ ~s(  queue mq "RabbitMQ"\n  database pg  "PostgreSQL"\n}\n)
  end

  test "apagar seta e nó (Delete)", %{view: view} do
    source = gesture(view, "remove_edge", %{"id" => "e2"})
    refute source =~ "SELECT"

    source = gesture(view, "remove_node", %{"id" => "mq"})
    refute source =~ "RabbitMQ"
    assert source =~ "# comentário do autor"
  end

  test "Alt+↓ move o passo e devolve a linha do cursor", %{view: view} do
    two_steps = @arch <> "\nstep \"Escrita\" {\n  api ->> mq : publica\n}\n"
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => two_steps})

    render_hook(view, "canvas", %{
      "op" => "move_step",
      "params" => %{"line" => 11, "direction" => "down"}
    })

    assert_push_event(view, "bg:source", %{source: source, line: 15})
    assert source =~ ~s(step "Escrita" {\n  api ->> mq : publica\n}\n\nstep "Leitura")
  end

  test "formatar avisa que os comentários saíram", %{view: view} do
    source = gesture(view, "format")
    refute source =~ "#"
    assert render(view) =~ "comentários foram removidos"
  end

  test "com erro de sintaxe no código, o canvas não edita", %{view: view} do
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => "isso não compila"})
    render_hook(view, "canvas", %{"op" => "add_node", "params" => %{}})

    refute_push_event(view, "bg:source", _)
    assert render(view) =~ "Corrija o erro de sintaxe"
  end

  test "gesto inválido explica o motivo e não muda o texto", %{view: view} do
    render_hook(view, "canvas", %{
      "op" => "relabel_edge",
      "params" => %{"id" => "e2", "label" => "#42"}
    })

    refute_push_event(view, "bg:source", _)
    assert render(view) =~ "não pode ter #"
  end

  test "importar Mermaid pelo diálogo", %{view: view} do
    view |> element("#open-import") |> render_click()
    assert has_element?(view, "#import-form")

    view
    |> form("#import-form", %{
      "text" => "sequenceDiagram\n  A->>B: oi\n  B-->>A: tchau",
      "format" => "auto"
    })
    |> render_submit()

    assert_push_event(view, "bg:source", %{source: source})
    assert source =~ "A -> B : oi"
    refute has_element?(view, "#import-form")
  end

  test "importar componentes do PlantUML já organiza as setas (opção ligada por padrão)", %{
    view: view
  } do
    view |> element("#open-import") |> render_click()
    assert has_element?(view, "#import-organize[checked]")

    view
    |> form("#import-form", %{"text" => Brainagram.Test.Fixtures.plantuml_component_source()})
    |> render_submit()

    assert_push_event(view, "bg:source", %{source: source})
    assert source =~ "diagram architecture"
    assert source =~ "layout {"
    assert render(view) =~ "setas organizadas"
  end

  test "sem a opção, o import não mexe nas posições", %{view: view} do
    view |> element("#open-import") |> render_click()

    view
    |> form("#import-form", %{
      "text" => Brainagram.Test.Fixtures.plantuml_component_source(),
      "organize" => "false"
    })
    |> render_submit()

    assert_push_event(view, "bg:source", %{source: source})
    refute source =~ "layout {"
  end

  test "importar texto que não é diagrama mantém o diálogo aberto com o erro", %{view: view} do
    view |> element("#open-import") |> render_click()
    html = view |> form("#import-form", %{"text" => "olá", "format" => "auto"}) |> render_submit()

    assert html =~ "Formato de importação desconhecido"
    assert has_element?(view, "#import-form")
  end

  test "trocar de exemplo manda o texto novo ao editor (entra no desfazer)", %{view: view} do
    view |> element("button[phx-value-slug=minimo]") |> render_click()
    assert_push_event(view, "bg:source", %{source: source})
    assert source =~ ~s(diagram sequence "Login")
  end
end

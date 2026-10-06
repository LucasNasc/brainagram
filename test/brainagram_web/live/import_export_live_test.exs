defmodule BrainagramWeb.ImportExportLiveTest do
  @moduledoc "Baixar e subir diagramas feitos aqui: .brain e pacote .json, pela tela."

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Application.{Bundle, Bus}
  alias Brainagram.Application.Commands.{CreateProject, StartDiagram}
  alias Brainagram.Application.Queries.ListDiagrams

  defp project!(name) do
    {:ok, slug} = Bus.dispatch(CreateProject, %{name: name})
    slug
  end

  defp diagram!(title, attrs \\ %{}) do
    {:ok, slug} = Bus.dispatch(StartDiagram, Map.merge(%{title: title}, attrs))
    slug
  end

  defp titles(project) do
    {:ok, list} = Bus.ask(ListDiagrams, %{project: project})
    list |> Enum.map(& &1.title) |> Enum.sort()
  end

  # Um arquivo por upload: o cliente de upload do LiveViewTest não aguenta
  # vários arquivos pequenos numa entrada só. O lote (vários arquivos de uma
  # vez) está coberto em `Application.ImportExportTest`.
  defp upload!(view, name, content, type) do
    view |> element("#import-diagrams") |> render_click()

    upload =
      file_input(view, "#import-files-form", :files, [%{name: name, content: content, type: type}])

    render_upload(upload, name)
    view
  end

  describe "downloads" do
    test ".brain de um diagrama: o fonte, como anexo com o nome do título", %{conn: conn} do
      slug = diagram!("Checkout com Pix")
      conn = get(conn, ~p"/d/#{slug}/download")

      assert conn.status == 200
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~s(filename="checkout-com-pix.brain")
      assert conn.resp_body =~ ~s(diagram sequence "Checkout com Pix")
      assert get(build_conn(), ~p"/d/naoexiste9/download").status == 404
    end

    test "pacote do projeto: JSON que a importação entende", %{conn: conn} do
      project = project!("Pagamentos")
      diagram!("Checkout", %{project: project})

      conn = get(conn, ~p"/export?project=#{project}")
      assert conn.status == 200
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "brainagram-pagamentos-"

      assert {:ok, %{projects: [%{name: "Pagamentos"}], diagrams: [%{title: "Checkout"}]}} =
               Bundle.decode(conn.resp_body)
    end
  end

  describe "área de gestão" do
    test "Exportar aponta para o escopo aberto; o card tem Baixar .brain", %{conn: conn} do
      project = project!("Pagamentos")
      slug = diagram!("Checkout", %{project: project})
      {:ok, view, _html} = live(conn, ~p"/?project=#{project}")

      assert has_element?(view, "#export-scope[href='/export?project=#{project}'][download]")
      assert has_element?(view, "#diagram-#{slug}-menu a[href='/d/#{slug}/download'][download]")

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#export-scope[href='/export']")
    end

    test "o diálogo abre com o projeto aberto como destino", %{conn: conn} do
      project = project!("Destino")
      {:ok, view, _html} = live(conn, ~p"/?project=#{project}")

      view |> element("#import-diagrams") |> render_click()
      assert has_element?(view, "#import-files-form select option[value='#{project}'][selected]")
      assert has_element?(view, "#import-submit[disabled]")
    end

    test ".brain pelo diálogo vai para o projeto escolhido", %{conn: conn} do
      project = project!("Destino")
      {:ok, view, _html} = live(conn, ~p"/?project=#{project}")

      upload!(
        view,
        "checkout.brain",
        ~s(diagram sequence "Checkout"\na -> b\n),
        "text/x-brainagram"
      )

      assert has_element?(view, "#import-files li", "checkout.brain")
      view |> form("#import-files-form", import: %{project: project}) |> render_submit()

      refute has_element?(view, "#import-dialog")
      assert titles(project) == ["Checkout"]
    end

    test "Mermaid pelo diálogo também entra", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      upload!(view, "login.mmd", "sequenceDiagram\n  U->>A: credenciais", "text/x-mermaid")
      view |> form("#import-files-form", import: %{project: ""}) |> render_submit()

      refute has_element?(view, "#import-dialog")
      assert length(titles("none")) == 1
    end

    test "arquivo com erro: o diálogo fica aberto e diz qual e por quê", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      upload!(view, "ruim.brain", "diagram mindmap\n", "text/x-brainagram")
      view |> form("#import-files-form", import: %{project: ""}) |> render_submit()

      assert has_element?(view, "#import-dialog")
      assert has_element?(view, "#import-report", "ruim.brain")
      assert has_element?(view, "#import-report", "tipo de diagrama desconhecido")
    end

    test "pacote .json exportado volta pela importação", %{conn: conn} do
      project = project!("Ida e volta")
      diagram!("Original", %{project: project})
      json = get(conn, ~p"/export?project=#{project}").resp_body

      {:ok, view, _html} = live(build_conn(), ~p"/")
      upload!(view, "pacote.json", json, "application/json")
      view |> form("#import-files-form", import: %{project: ""}) |> render_submit()

      assert titles(project) == ["Original", "Original"]
    end
  end

  describe "editor" do
    test "Exportar tem .brain e as duas qualidades de GIF; importar aceita .brain", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")

      assert has_element?(view, "#export-brain")
      assert has_element?(view, "#export-gif")
      assert has_element?(view, "#export-gif-light")

      view |> element("#open-import") |> render_click()
      assert has_element?(view, "#import-format option[value=brainagram]")
      assert has_element?(view, "#import-file[phx-hook=ReadFileInto]")

      view
      |> form("#import-form", %{
        "text" => ~s(diagram sequence "Do arquivo"\na ->> b : oi),
        "format" => "auto"
      })
      |> render_submit()

      assert_push_event(view, "bg:source", %{source: source})
      assert source == ~s(diagram sequence "Do arquivo"\na ->> b : oi)
    end
  end
end

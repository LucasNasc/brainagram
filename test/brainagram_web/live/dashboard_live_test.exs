defmodule BrainagramWeb.DashboardLiveTest do
  @moduledoc "A área de gestão: projetos e diagramas, pelos botões e diálogos da tela."

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.{CreateProject, StartDiagram}
  alias Brainagram.Application.Queries.GetDiagramBySlug

  defp project!(name, color \\ "violet") do
    {:ok, slug} = Bus.dispatch(CreateProject, %{name: name, color: color})
    slug
  end

  defp diagram!(title, attrs \\ %{}) do
    {:ok, slug} = Bus.dispatch(StartDiagram, Map.merge(%{title: title}, attrs))
    slug
  end

  defp detail(slug) do
    {:ok, detail} = Bus.ask(GetDiagramBySlug, %{slug: slug})
    detail
  end

  describe "sem nada ainda" do
    test "estado vazio convida a começar pelo tipo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#empty-state")
      assert has_element?(view, "#start-sequence")
      assert has_element?(view, "#start-architecture")
      assert has_element?(view, "#scope-all[aria-current=page]")
    end

    test "começar pelo tipo abre o diálogo já com o tipo escolhido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#start-architecture") |> render_click()
      assert has_element?(view, "#new-diagram-form input[value=architecture][checked]")
    end
  end

  describe "projetos" do
    test "criar pelo diálogo abre o projeto recém-criado", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#new-project") |> render_click()
      assert has_element?(view, "#project-form")

      view
      |> form("#project-form", project: %{name: "Pagamentos", color: "teal"})
      |> render_submit()

      path = assert_patch(view)
      assert path =~ "project="
      assert has_element?(view, "#project-list", "Pagamentos")
      assert has_element?(view, "#scope-title", "Pagamentos")
      assert has_element?(view, "#project-list .ba-projdot[data-color=teal]")
    end

    test "nome em branco mostra o erro no campo e não cria", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#new-project") |> render_click()

      html = view |> form("#project-form", project: %{name: "  "}) |> render_submit()

      assert html =~ "Preencha este campo."
      assert has_element?(view, "#project-form")
    end

    test "editar nome e cor", %{conn: conn} do
      slug = project!("Pagamentos")
      {:ok, view, _html} = live(conn, ~p"/?project=#{slug}")

      view |> element("#edit-project") |> render_click()

      view
      |> form("#project-form", project: %{name: "Cobrança", color: "rose"})
      |> render_submit()

      assert has_element?(view, "#scope-title", "Cobrança")
      assert has_element?(view, "#project-#{slug} .ba-projdot[data-color=rose]")
    end

    test "excluir o projeto deixa os diagramas em “Sem projeto”", %{conn: conn} do
      slug = project!("Pagamentos")
      diagram = diagram!("Checkout", %{project: slug})
      {:ok, view, _html} = live(conn, ~p"/?project=#{slug}")

      view |> element("#delete-project") |> render_click()
      assert has_element?(view, "#confirm-delete-project", "Sem projeto")

      view |> element("#confirm-delete-project-submit") |> render_click()
      assert_patch(view, ~p"/")

      refute has_element?(view, "#project-#{slug}")
      assert detail(diagram).project == nil
      assert has_element?(view, "#scope-none .ba-projnav__count", "1")
    end
  end

  describe "diagramas" do
    setup do
      project = project!("Pagamentos")
      checkout = diagram!("Checkout", %{project: project})
      loose = diagram!("Rascunho", %{kind: "architecture"})
      %{project: project, checkout: checkout, loose: loose}
    end

    test "cards com título, miniatura e projeto; contagens na lateral", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/")

      assert has_element?(view, "#diagram-#{ctx.checkout}", "Checkout")

      assert has_element?(
               view,
               "#diagram-#{ctx.checkout} img[src*='/d/#{ctx.checkout}/preview.svg']"
             )

      assert has_element?(view, "#diagram-#{ctx.checkout} .ba-dcard__project", "Pagamentos")
      assert has_element?(view, "#scope-all .ba-projnav__count", "2")
      assert has_element?(view, "#project-#{ctx.project} .ba-projnav__count", "1")
    end

    test "escopo, tipo e busca filtram a lista", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/?project=#{ctx.project}")
      assert has_element?(view, "#diagram-#{ctx.checkout}")
      refute has_element?(view, "#diagram-#{ctx.loose}")

      {:ok, view, _html} = live(ctx.conn, ~p"/?project=none")
      assert has_element?(view, "#diagram-#{ctx.loose}")
      refute has_element?(view, "#diagram-#{ctx.checkout}")

      {:ok, view, _html} = live(ctx.conn, ~p"/")
      view |> element("#kind-architecture") |> render_click()
      assert has_element?(view, "#diagram-#{ctx.loose}")
      refute has_element?(view, "#diagram-#{ctx.checkout}")

      {:ok, view, _html} = live(ctx.conn, ~p"/")
      view |> form("#dash-search", q: "check") |> render_change()
      assert_patch(view, ~p"/?q=check")
      assert has_element?(view, "#diagram-#{ctx.checkout}")
      refute has_element?(view, "#diagram-#{ctx.loose}")

      view |> form("#dash-search", q: "nada disso") |> render_change()
      assert has_element?(view, "#empty-state", "Nenhum diagrama encontrado")
    end

    test "novo diagrama no projeto aberto: cria e vai para o editor", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/?project=#{ctx.project}")

      view |> element("#new-diagram") |> render_click()

      assert has_element?(
               view,
               "#new-diagram-form select option[value='#{ctx.project}'][selected]"
             )

      # quem cria pela área de gestão é o autor: o diagrama novo abre no editor
      assert {:error, {:live_redirect, %{to: "/d/" <> rest}}} =
               view
               |> form("#new-diagram-form",
                 diagram: %{title: "Estorno", kind: "sequence", project: ctx.project}
               )
               |> render_submit()

      assert [slug, "edit=1"] = String.split(rest, "?")
      assert %{title: "Estorno", project: project} = detail(slug)
      assert project == ctx.project
    end

    test "renomear pelo menu do card", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/")

      view
      |> element("#diagram-#{ctx.checkout}-menu button[phx-click='diagram:rename']")
      |> render_click()

      view |> form("#rename-form", rename: %{title: "Checkout v2"}) |> render_submit()

      assert has_element?(view, "#diagram-#{ctx.checkout}", "Checkout v2")
      assert detail(ctx.checkout).source =~ ~s(diagram sequence "Checkout v2")
    end

    test "mover para outro projeto e para “Sem projeto”", ctx do
      other = project!("Operação")
      {:ok, view, _html} = live(ctx.conn, ~p"/?project=#{ctx.project}")

      view
      |> element("#diagram-#{ctx.checkout}-menu button[phx-click='diagram:move']")
      |> render_click()

      view |> form("#move-form", move: %{project: other}) |> render_submit()

      refute has_element?(view, "#diagram-#{ctx.checkout}")
      assert detail(ctx.checkout).project == other
      assert has_element?(view, "#project-#{other} .ba-projnav__count", "1")
    end

    test "duplicar, publicar e excluir", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/?project=#{ctx.project}")

      view
      |> element("#diagram-#{ctx.checkout}-menu button[phx-click='diagram:fork']")
      |> render_click()

      assert has_element?(view, "#project-#{ctx.project} .ba-projnav__count", "2")

      view
      |> element("#diagram-#{ctx.checkout}-menu button[phx-click='diagram:visibility']")
      |> render_click()

      assert detail(ctx.checkout).visibility == "private"
      assert has_element?(view, "#diagram-#{ctx.checkout} .ba-dcard__private")

      view
      |> element("#diagram-#{ctx.checkout}-menu button[phx-click='diagram:delete']")
      |> render_click()

      view |> element("#confirm-delete-diagram-submit") |> render_click()
      refute has_element?(view, "#diagram-#{ctx.checkout}")
      assert {:error, :not_found} = Bus.ask(GetDiagramBySlug, %{slug: ctx.checkout})
    end

    test "mudança feita fora da tela aparece sozinha", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/")

      diagram!("Criado em outra aba", %{project: ctx.project})
      assert render(view) =~ "Criado em outra aba"
    end

    test "em inglês", %{conn: conn} = ctx do
      {:ok, view, _html} = conn |> put_req_cookie("bg_locale", "en") |> live(~p"/")

      assert has_element?(view, "#scope-all", "All diagrams")
      assert has_element?(view, "#new-diagram", "New diagram")
      assert has_element?(view, "#diagram-#{ctx.checkout}", "Sequence")
    end
  end

  describe "miniatura" do
    test "SVG com cache pelo updated_at, 304 na revalidação, 404 sem diagrama", %{conn: conn} do
      slug = diagram!("Checkout")

      conn1 = get(conn, ~p"/d/#{slug}/preview.svg?v=1")
      assert conn1.status == 200
      assert response_content_type(conn1, :svg) =~ "image/svg+xml"
      assert conn1.resp_body =~ "<svg"
      assert get_resp_header(conn1, "cache-control") == ["private, max-age=31536000, immutable"]

      [etag] = get_resp_header(conn1, "etag")

      conn2 =
        build_conn() |> put_req_header("if-none-match", etag) |> get(~p"/d/#{slug}/preview.svg")

      assert conn2.status == 304

      assert get(build_conn(), ~p"/d/naoexiste123/preview.svg").status == 404
    end
  end

  describe "editor" do
    test "a trilha do topo leva de volta ao projeto do diagrama", %{conn: conn} do
      project = project!("Pagamentos", "teal")
      slug = diagram!("Checkout", %{project: project})

      {:ok, view, _html} = live(conn, ~p"/d/#{slug}")

      assert has_element?(view, "#breadcrumb-project[href='/?project=#{project}']", "Pagamentos")
      assert has_element?(view, "#back-to-dashboard[href='/']")
    end

    test "/new?project=… salva o diagrama novo naquele projeto", %{conn: conn} do
      project = project!("Pagamentos")
      {:ok, view, _html} = live(conn, ~p"/new?project=#{project}")

      view |> element("button[phx-click=save]") |> render_click()
      path = assert_patch(view)
      "/d/" <> slug = path

      assert detail(slug).project == project
    end
  end
end

defmodule BrainagramWeb.DashboardLive do
  @moduledoc """
  A área de gestão: onde a pessoa vê, separa por projeto e organiza os
  diagramas antes de abrir um no editor.

  Tudo que muda estado vai pelo `Bus` — criar/renomear/colorir/excluir
  projeto, começar/renomear/mover/duplicar/publicar/excluir diagrama. A tela
  só guarda o filtro (que mora na URL: `?project=…&q=…&kind=…&sort=…`, então
  dá para favoritar e compartilhar um projeto) e qual diálogo está aberto.

  A lista escuta o tópico global de eventos: salvar um diagrama em outra aba,
  ou outra pessoa criar um projeto, atualiza esta tela sozinha.
  """

  use BrainagramWeb, :live_view

  alias Brainagram.Application.Bus

  alias Brainagram.Application.Commands.{
    ChangeDiagramVisibility,
    CreateProject,
    DeleteDiagram,
    DeleteProject,
    ForkDiagram,
    ImportDiagrams,
    MoveDiagram,
    RenameDiagram,
    StartDiagram,
    UpdateProject
  }

  alias Brainagram.Application.Queries.{ListDiagrams, ListProjects}
  alias BrainagramWeb.{ErrorMessages, TimeAgo}

  @colors ~w(violet blue teal green amber orange rose slate)
  @sorts ~w(updated created title)
  @kinds ~w(sequence architecture)
  @preview_rev 2

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Bus.subscribe_all()

    {:ok,
     socket
     |> assign(page_title: gettext("Diagramas") <> " · Brainagram")
     |> assign(filter: %{project: nil, search: "", kind: nil, sort: "updated"})
     |> assign(dialog: nil, form: nil, import_report: nil)
     |> allow_upload(:files,
       accept: ~w(.brain .json .mmd .mermaid .puml .plantuml .txt),
       max_entries: 50,
       max_file_size: 2_000_000
     )
     |> load_projects()
     |> stream_configure(:diagrams, dom_id: &"diagram-#{&1.slug}")
     |> stream(:diagrams, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = %{
      project: blank_to_nil(params["project"]),
      search: params["q"] || "",
      kind: if(params["kind"] in @kinds, do: params["kind"]),
      sort: if(params["sort"] in @sorts, do: params["sort"], else: "updated")
    }

    {:noreply, socket |> assign(filter: filter) |> load_diagrams()}
  end

  # ── filtros ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, patch_filter(socket, search: q)}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply, patch_filter(socket, sort: sort)}
  end

  # ── diálogos ──────────────────────────────────────────────────────────────

  def handle_event("dialog:close", _params, socket) do
    {:noreply, close_dialog(socket)}
  end

  # ── importar e exportar ───────────────────────────────────────────────────

  def handle_event("import:open", _params, socket) do
    project =
      if socket.assigns.filter.project in [nil, "none"],
        do: "",
        else: socket.assigns.filter.project

    form = to_form(%{"project" => project}, as: :import)
    {:noreply, assign(socket, dialog: :import, form: form, import_report: nil)}
  end

  def handle_event("import:validate", %{"import" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :import))}
  end

  def handle_event("import:validate", _params, socket), do: {:noreply, socket}

  def handle_event("import:cancel-file", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("import:save", params, socket) do
    project = get_in(params, ["import", "project"]) || ""

    files =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        {:ok, %{"name" => entry.client_name, "content" => File.read!(path)}}
      end)

    case {files, Bus.dispatch(ImportDiagrams, %{files: files, project: project})} do
      {[], _} ->
        {:noreply, put_flash(socket, :error, gettext("Escolha ao menos um arquivo."))}

      {_, {:ok, report}} ->
        socket = socket |> load_projects() |> load_diagrams()

        # tudo entrou: fecha e avisa; algo falhou: o diálogo mostra o quê e por quê
        if report.failed == [] do
          {:noreply,
           socket |> close_dialog(cancel: false) |> put_flash(:info, import_message(report))}
        else
          {:noreply, assign(socket, import_report: report)}
        end

      {_, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, ErrorMessages.describe(reason))}
    end
  end

  def handle_event("project:new", _params, socket) do
    form = to_form(%{"name" => "", "color" => next_color(socket)}, as: :project)
    {:noreply, assign(socket, dialog: {:project, nil}, form: form)}
  end

  def handle_event("project:edit", %{"slug" => slug}, socket) do
    case find_project(socket, slug) do
      nil ->
        {:noreply, socket}

      project ->
        form = to_form(%{"name" => project.name, "color" => project.color}, as: :project)
        {:noreply, assign(socket, dialog: {:project, project}, form: form)}
    end
  end

  def handle_event("project:validate", %{"project" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :project))}
  end

  def handle_event("project:save", %{"project" => params}, socket) do
    {command, attrs, message} =
      case socket.assigns.dialog do
        {:project, nil} ->
          {CreateProject, params, gettext("Projeto criado.")}

        {:project, project} ->
          {UpdateProject, Map.put(params, "slug", project.slug), gettext("Projeto atualizado.")}
      end

    case Bus.dispatch(command, attrs) do
      {:ok, slug} ->
        socket =
          socket
          |> close_dialog()
          |> put_flash(:info, message)
          |> load_projects()

        # projeto novo: já abre nele, para o próximo diagrama nascer lá
        {:noreply,
         if(command == CreateProject,
           do: push_patch(socket, to: dashboard_path(socket, project: slug)),
           else: load_diagrams(socket)
         )}

      {:error, reason} ->
        {:noreply, assign(socket, form: form_error(params, :project, :name, reason))}
    end
  end

  def handle_event("project:delete", %{"slug" => slug}, socket) do
    case find_project(socket, slug) do
      nil -> {:noreply, socket}
      project -> {:noreply, assign(socket, dialog: {:delete_project, project})}
    end
  end

  def handle_event("project:confirm-delete", _params, socket) do
    {:delete_project, project} = socket.assigns.dialog

    case Bus.dispatch(DeleteProject, %{slug: project.slug}) do
      {:ok, _} ->
        socket =
          socket
          |> close_dialog()
          |> put_flash(
            :info,
            gettext("Projeto excluído. Os diagramas dele estão em “Sem projeto”.")
          )
          |> load_projects()

        {:noreply,
         if(socket.assigns.filter.project == project.slug,
           do: push_patch(socket, to: dashboard_path(socket, project: nil)),
           else: load_diagrams(socket)
         )}

      {:error, reason} ->
        {:noreply, socket |> close_dialog() |> put_flash(:error, ErrorMessages.describe(reason))}
    end
  end

  def handle_event("diagram:new", params, socket) do
    project =
      case {params["project"], socket.assigns.filter.project} do
        {nil, "none"} -> ""
        {nil, current} -> current || ""
        {given, _} -> given
      end

    form =
      to_form(%{"title" => "", "kind" => params["kind"] || "sequence", "project" => project},
        as: :diagram
      )

    {:noreply, assign(socket, dialog: :new_diagram, form: form)}
  end

  def handle_event("diagram:validate", %{"diagram" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :diagram))}
  end

  def handle_event("diagram:create", %{"diagram" => params}, socket) do
    title = String.trim(params["title"] || "")
    title = if title == "", do: gettext("Sem título"), else: title
    # o modelo inicial sai no idioma da interface (`pt_BR` → `pt`)
    lang = socket.assigns.locale |> String.split("_") |> hd()

    attrs = %{
      title: title,
      kind: params["kind"],
      project: params["project"],
      lang: lang
    }

    case Bus.dispatch(StartDiagram, attrs) do
      {:ok, slug} ->
        {:noreply, push_navigate(socket, to: ~p"/d/#{slug}")}

      {:error, reason} ->
        {:noreply, assign(socket, form: form_error(params, :diagram, :title, reason))}
    end
  end

  def handle_event("diagram:rename", %{"slug" => slug, "title" => title}, socket) do
    form = to_form(%{"title" => title}, as: :rename)
    {:noreply, assign(socket, dialog: {:rename, slug}, form: form)}
  end

  def handle_event("diagram:rename-save", %{"rename" => %{"title" => title} = params}, socket) do
    {:rename, slug} = socket.assigns.dialog

    case Bus.dispatch(RenameDiagram, %{slug: slug, title: title}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> close_dialog()
         |> put_flash(:info, gettext("Diagrama renomeado."))
         |> load_diagrams()}

      {:error, reason} ->
        {:noreply, assign(socket, form: form_error(params, :rename, :title, reason))}
    end
  end

  def handle_event("diagram:move", %{"slug" => slug} = params, socket) do
    form = to_form(%{"project" => params["project"] || ""}, as: :move)
    {:noreply, assign(socket, dialog: {:move, slug}, form: form)}
  end

  def handle_event("diagram:move-save", %{"move" => %{"project" => project}}, socket) do
    {:move, slug} = socket.assigns.dialog

    case Bus.dispatch(MoveDiagram, %{slug: slug, project: project}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> close_dialog()
         |> put_flash(:info, gettext("Diagrama movido."))
         |> load_projects()
         |> load_diagrams()}

      {:error, reason} ->
        {:noreply, socket |> close_dialog() |> put_flash(:error, ErrorMessages.describe(reason))}
    end
  end

  def handle_event("diagram:fork", %{"slug" => slug}, socket) do
    socket
    |> run(ForkDiagram, %{slug: slug}, gettext("Cópia criada (privada)."))
    |> reply()
  end

  def handle_event("diagram:visibility", %{"slug" => slug, "to" => to}, socket) do
    message =
      if to == "public",
        do: gettext("Agora é público."),
        else: gettext("Agora é privado.")

    socket |> run(ChangeDiagramVisibility, %{slug: slug, visibility: to}, message) |> reply()
  end

  def handle_event("diagram:delete", %{"slug" => slug, "title" => title}, socket) do
    {:noreply, assign(socket, dialog: {:delete_diagram, slug, title})}
  end

  def handle_event("diagram:confirm-delete", _params, socket) do
    {:delete_diagram, slug, _title} = socket.assigns.dialog

    socket
    |> close_dialog()
    |> run(DeleteDiagram, %{slug: slug}, gettext("Diagrama excluído."))
    |> reply()
  end

  # ── eventos de domínio ────────────────────────────────────────────────────

  # Qualquer mudança (desta aba, de outra, de outra pessoa) redesenha a lista.
  @impl true
  def handle_info({:domain_event, _event}, socket) do
    {:noreply, socket |> load_projects() |> load_diagrams()}
  end

  # ── plumbing ──────────────────────────────────────────────────────────────

  defp run(socket, command, attrs, message) do
    case Bus.dispatch(command, attrs) do
      {:ok, _} ->
        socket |> put_flash(:info, message) |> load_projects() |> load_diagrams()

      {:error, reason} ->
        put_flash(socket, :error, ErrorMessages.describe(reason))
    end
  end

  defp reply(socket), do: {:noreply, socket}

  defp load_projects(socket) do
    {:ok, %{projects: projects, all: all, none: none}} = Bus.ask(ListProjects)
    assign(socket, projects: projects, counts: %{all: all, none: none})
  end

  defp load_diagrams(socket) do
    filter = socket.assigns.filter

    query = %{
      project: filter.project,
      search: filter.search,
      kind: filter.kind,
      sort: filter.sort
    }

    diagrams =
      case Bus.ask(ListDiagrams, query) do
        {:ok, diagrams} -> diagrams
        {:error, _} -> []
      end

    socket
    |> assign(diagram_count: length(diagrams), scope: scope(socket.assigns.projects, filter))
    |> stream(:diagrams, diagrams, reset: true)
  end

  defp patch_filter(socket, changes) do
    push_patch(socket, to: dashboard_path(socket, changes))
  end

  defp dashboard_path(socket, changes) do
    filter = Map.merge(socket.assigns.filter, Map.new(changes))

    query =
      [
        project: filter.project,
        q: blank_to_nil(filter.search),
        kind: filter.kind,
        sort: if(filter.sort != "updated", do: filter.sort)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ~p"/?#{query}"
  end

  # Fechar o diálogo descarta os arquivos escolhidos e não importados. Depois
  # de importar (`cancel: false`) eles já foram consumidos — não há o que cancelar.
  defp close_dialog(socket, opts \\ []) do
    socket =
      if Keyword.get(opts, :cancel, true),
        do:
          Enum.reduce(socket.assigns.uploads.files.entries, socket, fn entry, acc ->
            cancel_upload(acc, :files, entry.ref)
          end),
        else: socket

    assign(socket, dialog: nil, form: nil, import_report: nil)
  end

  defp import_message(%{created: created, projects: projects}) do
    diagrams = ngettext("1 diagrama importado", "%{count} diagramas importados", length(created))

    case projects do
      [] ->
        diagrams <> "."

      list ->
        diagrams <>
          "; " <> ngettext("1 projeto criado.", "%{count} projetos criados.", length(list))
    end
  end

  defp find_project(socket, slug), do: Enum.find(socket.assigns.projects, &(&1.slug == slug))

  # O que está sendo mostrado: todos, sem projeto, ou um projeto (que pode ter
  # sido excluído noutra aba — aí volta a "todos").
  defp scope(_projects, %{project: nil}), do: :all
  defp scope(_projects, %{project: "none"}), do: :none

  defp scope(projects, %{project: slug}) do
    Enum.find(projects, :all, &(&1.slug == slug))
  end

  # Cada projeto novo ganha a próxima cor da paleta: a lateral fica colorida
  # sem a pessoa precisar escolher.
  defp next_color(socket) do
    Enum.at(@colors, rem(length(socket.assigns.projects), length(@colors)))
  end

  defp form_error(params, as, field, %Ecto.Changeset{}) do
    to_form(params, as: as, errors: [{field, {gettext("Preencha este campo."), []}}])
  end

  defp form_error(params, as, field, reason) do
    to_form(params, as: as, errors: [{field, {ErrorMessages.describe(reason), []}}])
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, colors: @colors)

    ~H"""
    <div class="ba-dash">
      <header class="ba-topbar">
        <.link navigate={~p"/"} class="ba-topbar__brand" aria-label={gettext("Brainagram, início")}>
          <.logo wordmark />
        </.link>
        <span class="ba-topbar__spacer"></span>
        <form
          id="dash-search"
          class="ba-dash__search"
          phx-change="search"
          phx-submit="search"
          role="search"
        >
          <.icon name="hero-magnifying-glass" class="ba-ico--16" />
          <input
            type="search"
            name="q"
            value={@filter.search}
            placeholder={gettext("Buscar diagramas…")}
            aria-label={gettext("Buscar diagramas")}
            phx-debounce="200"
            autocomplete="off"
          />
        </form>
        <div class="ba-topbar__actions">
          <.link navigate={~p"/new"} class="ba-btn ba-btn--ghost ba-topbar__hide-sm" id="open-scratch">
            <.icon name="hero-pencil-square" />{gettext("Editor livre")}
          </.link>
          <Layouts.locale_toggle locale={@locale} />
          <Layouts.theme_toggle />
        </div>
      </header>

      <div class="ba-dash__main">
        <.sidebar projects={@projects} counts={@counts} filter={@filter} />

        <main class="ba-dash__content" id="dash-content">
          <.scope_header scope={@scope} count={@diagram_count} />
          <.toolbar filter={@filter} />

          <.empty_state
            :if={@diagram_count == 0}
            scope={@scope}
            filtered={@filter.search != "" or @filter.kind != nil}
            total={@counts.all}
          />

          <div id="diagrams" class="ba-dgrid" phx-update="stream" hidden={@diagram_count == 0}>
            <.diagram_card
              :for={{dom_id, diagram} <- @streams.diagrams}
              id={dom_id}
              diagram={diagram}
              show_project={@scope == :all}
            />
          </div>
        </main>
      </div>

      <.project_dialog
        :if={match?({:project, _}, @dialog)}
        form={@form}
        project={elem(@dialog, 1)}
        colors={@colors}
      />
      <.new_diagram_dialog :if={@dialog == :new_diagram} form={@form} projects={@projects} />
      <.rename_dialog :if={match?({:rename, _}, @dialog)} form={@form} />
      <.move_dialog :if={match?({:move, _}, @dialog)} form={@form} projects={@projects} />
      <.import_dialog
        :if={@dialog == :import}
        form={@form}
        projects={@projects}
        upload={@uploads.files}
        report={@import_report}
      />
      <.confirm_dialog
        :if={match?({:delete_project, _}, @dialog)}
        id="confirm-delete-project"
        title={gettext("Excluir projeto?")}
        confirm="project:confirm-delete"
        action={gettext("Excluir projeto")}
      >
        {gettext(
          "O projeto “%{name}” será excluído. Os %{count} diagramas dele não são apagados: vão para “Sem projeto”.",
          name: elem(@dialog, 1).name,
          count: elem(@dialog, 1).diagram_count
        )}
      </.confirm_dialog>
      <.confirm_dialog
        :if={match?({:delete_diagram, _, _}, @dialog)}
        id="confirm-delete-diagram"
        title={gettext("Excluir diagrama?")}
        confirm="diagram:confirm-delete"
        action={gettext("Excluir diagrama")}
      >
        {gettext("“%{title}” será excluído para sempre. Isso não pode ser desfeito.",
          title: elem(@dialog, 2)
        )}
      </.confirm_dialog>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  # ── lateral ───────────────────────────────────────────────────────────────

  attr :projects, :list, required: true
  attr :counts, :map, required: true
  attr :filter, :map, required: true

  defp sidebar(assigns) do
    ~H"""
    <aside class="ba-dash__side" aria-label={gettext("Projetos")}>
      <nav class="ba-projnav">
        <.link
          patch={~p"/"}
          id="scope-all"
          class="ba-projnav__item"
          aria-current={@filter.project == nil && "page"}
        >
          <.icon name="hero-squares-2x2" class="ba-ico--16" />
          <span class="ba-projnav__name">{gettext("Todos os diagramas")}</span>
          <span class="ba-projnav__count">{@counts.all}</span>
        </.link>
        <.link
          patch={~p"/?project=none"}
          id="scope-none"
          class="ba-projnav__item"
          aria-current={@filter.project == "none" && "page"}
        >
          <.icon name="hero-inbox" class="ba-ico--16" />
          <span class="ba-projnav__name">{gettext("Sem projeto")}</span>
          <span class="ba-projnav__count">{@counts.none}</span>
        </.link>

        <div class="ba-projnav__head">
          <h2 class="ba-panel__title">{gettext("Projetos")}</h2>
          <button
            type="button"
            id="new-project"
            class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost"
            phx-click="project:new"
            aria-label={gettext("Novo projeto")}
            title={gettext("Novo projeto")}
          >
            <.icon name="hero-plus" class="ba-ico--16" />
          </button>
        </div>

        <ul class="ba-projnav__list" id="project-list">
          <li :for={project <- @projects} id={"project-#{project.slug}"}>
            <.link
              patch={~p"/?project=#{project.slug}"}
              class="ba-projnav__item"
              aria-current={@filter.project == project.slug && "page"}
            >
              <span class="ba-projdot" data-color={project.color} aria-hidden="true"></span>
              <span class="ba-projnav__name">{project.name}</span>
              <span class="ba-projnav__count">{project.diagram_count}</span>
            </.link>
          </li>
        </ul>

        <button
          :if={@projects == []}
          type="button"
          class="ba-projnav__hint"
          phx-click="project:new"
        >
          <.icon name="hero-folder-plus" class="ba-ico--16" />
          {gettext("Crie um projeto para separar seus diagramas")}
        </button>
      </nav>
    </aside>
    """
  end

  # ── conteúdo ──────────────────────────────────────────────────────────────

  attr :scope, :any, required: true
  attr :count, :integer, required: true

  defp scope_header(assigns) do
    ~H"""
    <div class="ba-dash__header">
      <div class="ba-dash__heading">
        <h1 class="ba-dash__title" id="scope-title">
          <%= case @scope do %>
            <% :all -> %>
              {gettext("Todos os diagramas")}
            <% :none -> %>
              {gettext("Sem projeto")}
            <% project -> %>
              <span class="ba-projdot ba-projdot--lg" data-color={project.color} aria-hidden="true"></span>
              {project.name}
          <% end %>
        </h1>
        <p class="ba-dash__subtitle">
          {ngettext("1 diagrama", "%{count} diagramas", @count)}
        </p>
      </div>

      <div :if={is_map(@scope)} class="ba-dash__scope-actions">
        <.button
          size="sm"
          variant="ghost"
          id="edit-project"
          phx-click="project:edit"
          phx-value-slug={@scope.slug}
        >
          <.icon name="hero-pencil-square" />{gettext("Editar projeto")}
        </.button>
        <.button
          size="sm"
          variant="ghost"
          id="delete-project"
          phx-click="project:delete"
          phx-value-slug={@scope.slug}
        >
          <.icon name="hero-trash" />{gettext("Excluir")}
        </.button>
      </div>
    </div>
    """
  end

  attr :filter, :map, required: true

  defp toolbar(assigns) do
    ~H"""
    <div class="ba-dash__toolbar">
      <div class="ba-seg" role="group" aria-label={gettext("Tipo de diagrama")}>
        <.link
          :for={
            {kind, label} <- [
              {nil, gettext("Todos")},
              {"sequence", gettext("Sequência")},
              {"architecture", gettext("Arquitetura")}
            ]
          }
          patch={kind_path(@filter, kind)}
          class="ba-seg__opt"
          id={"kind-#{kind || "all"}"}
          aria-pressed={to_string(@filter.kind == kind)}
        >
          {label}
        </.link>
      </div>

      <form id="dash-sort" phx-change="sort" class="ba-dash__sort">
        <label for="sort-select" class="ba-dash__sort-label">{gettext("Ordenar")}</label>
        <select id="sort-select" name="sort" class="ba-select">
          <option value="updated" selected={@filter.sort == "updated"}>
            {gettext("Editados recentemente")}
          </option>
          <option value="created" selected={@filter.sort == "created"}>
            {gettext("Criados recentemente")}
          </option>
          <option value="title" selected={@filter.sort == "title"}>{gettext("Nome (A–Z)")}</option>
        </select>
      </form>

      <span class="ba-spacer"></span>

      <.button variant="ghost" id="import-diagrams" phx-click="import:open">
        <.icon name="hero-arrow-up-tray" />{gettext("Importar")}
      </.button>
      <a
        href={export_path(@filter)}
        class="ba-btn ba-btn--ghost"
        id="export-scope"
        download
        title={gettext("Baixa os diagramas desta lista num pacote .json, que volta pelo Importar")}
      >
        <.icon name="hero-arrow-down-tray" />{gettext("Exportar")}
      </a>
      <.button variant="primary" id="new-diagram" phx-click="diagram:new">
        <.icon name="hero-plus" />{gettext("Novo diagrama")}
      </.button>
    </div>
    """
  end

  defp export_path(%{project: nil}), do: ~p"/export"
  defp export_path(%{project: project}), do: ~p"/export?#{[project: project]}"

  defp kind_path(filter, kind) do
    query =
      [project: filter.project, q: blank_to_nil(filter.search), kind: kind]
      |> Kernel.++(if filter.sort != "updated", do: [sort: filter.sort], else: [])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ~p"/?#{query}"
  end

  attr :scope, :any, required: true
  attr :filtered, :boolean, required: true
  attr :total, :integer, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="ba-empty" id="empty-state">
      <%= cond do %>
        <% @filtered -> %>
          <.icon name="hero-magnifying-glass" class="ba-empty__icon" />
          <h2 class="ba-empty__title">{gettext("Nenhum diagrama encontrado")}</h2>
          <p class="ba-empty__text">{gettext("Tente outro termo ou limpe os filtros.")}</p>
          <.link patch={clear_path(@scope)} class="ba-btn">{gettext("Limpar filtros")}</.link>
        <% @total == 0 -> %>
          <.icon name="hero-sparkles" class="ba-empty__icon" />
          <h2 class="ba-empty__title">{gettext("Seu primeiro diagrama")}</h2>
          <p class="ba-empty__text">
            {gettext(
              "Escolha um tipo para começar. O diagrama já nasce com um exemplo curto — é só dar play e trocar os nomes."
            )}
          </p>
          <div class="ba-empty__choices">
            <.start_kind kind="sequence" />
            <.start_kind kind="architecture" />
          </div>
        <% true -> %>
          <.icon name="hero-folder-open" class="ba-empty__icon" />
          <h2 class="ba-empty__title">{gettext("Nada aqui ainda")}</h2>
          <p class="ba-empty__text">
            {gettext("Crie um diagrama neste projeto ou mova um que já existe para cá.")}
          </p>
          <.button variant="primary" phx-click="diagram:new">
            <.icon name="hero-plus" />{gettext("Novo diagrama")}
          </.button>
      <% end %>
    </div>
    """
  end

  defp clear_path(%{slug: slug}), do: ~p"/?project=#{slug}"
  defp clear_path(:none), do: ~p"/?project=none"
  defp clear_path(_all), do: ~p"/"

  attr :kind, :string, required: true

  defp start_kind(assigns) do
    ~H"""
    <button
      type="button"
      class="ba-choice__opt ba-empty__choice"
      id={"start-#{@kind}"}
      phx-click="diagram:new"
      phx-value-kind={@kind}
    >
      <strong><.icon name={kind_icon(@kind)} />{kind_label(@kind)}</strong>
      <span>{kind_hint(@kind)}</span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :diagram, :map, required: true
  attr :show_project, :boolean, default: false

  defp diagram_card(assigns) do
    ~H"""
    <article class="ba-dcard" id={@id}>
      <.link
        navigate={~p"/d/#{@diagram.slug}"}
        class="ba-dcard__thumb"
        tabindex="-1"
        aria-hidden="true"
      >
        <img
          src={~p"/d/#{@diagram.slug}/preview.svg?#{[v: version(@diagram)]}"}
          alt=""
          loading="lazy"
          decoding="async"
        />
      </.link>

      <div class="ba-dcard__body">
        <.link navigate={~p"/d/#{@diagram.slug}"} class="ba-dcard__title">{@diagram.title}</.link>
        <div class="ba-dcard__meta">
          <span class="ba-dcard__kind" data-kind={@diagram.kind}>
            <.icon name={kind_icon(@diagram.kind)} class="ba-ico--16" />{kind_label(@diagram.kind)}
          </span>
          <span aria-hidden="true">·</span>
          <time datetime={@diagram.updated_at && DateTime.to_iso8601(@diagram.updated_at)}>
            {TimeAgo.format(@diagram.updated_at)}
          </time>
          <.icon
            :if={@diagram.visibility == "private"}
            name="hero-lock-closed"
            class="ba-ico--16 ba-dcard__private"
          />
        </div>
        <.link
          :if={@show_project && @diagram.project}
          patch={~p"/?project=#{@diagram.project}"}
          class="ba-dcard__project"
        >
          <span class="ba-projdot" data-color={@diagram.project_color} aria-hidden="true"></span>
          {@diagram.project_name}
        </.link>
      </div>

      <details class="ba-dropdown ba-dcard__menu" id={"#{@id}-menu"}>
        <summary
          class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost"
          aria-label={gettext("Ações de %{title}", title: @diagram.title)}
        >
          <.icon name="hero-ellipsis-horizontal" />
        </summary>
        <div class="ba-menu ba-dropdown__menu" role="menu">
          <.link navigate={~p"/d/#{@diagram.slug}"} class="ba-menu__item" role="menuitem">
            <.icon name="hero-arrow-top-right-on-square" /><span>{gettext("Abrir")}</span>
          </.link>
          <button
            type="button"
            class="ba-menu__item"
            role="menuitem"
            phx-click="diagram:rename"
            phx-value-slug={@diagram.slug}
            phx-value-title={@diagram.title}
          >
            <.icon name="hero-pencil" /><span>{gettext("Renomear")}</span>
          </button>
          <button
            type="button"
            class="ba-menu__item"
            role="menuitem"
            phx-click="diagram:move"
            phx-value-slug={@diagram.slug}
            phx-value-project={@diagram.project || ""}
          >
            <.icon name="hero-folder-arrow-down" /><span>{gettext("Mover para projeto…")}</span>
          </button>
          <button
            type="button"
            class="ba-menu__item"
            role="menuitem"
            phx-click="diagram:fork"
            phx-value-slug={@diagram.slug}
          >
            <.icon name="hero-document-duplicate" /><span>{gettext("Duplicar")}</span>
          </button>
          <a
            href={~p"/d/#{@diagram.slug}/download"}
            class="ba-menu__item"
            role="menuitem"
            download
          >
            <.icon name="hero-arrow-down-tray" /><span>{gettext("Baixar .brain")}</span>
          </a>
          <button
            type="button"
            class="ba-menu__item"
            role="menuitem"
            phx-click="diagram:visibility"
            phx-value-slug={@diagram.slug}
            phx-value-to={if @diagram.visibility == "public", do: "private", else: "public"}
          >
            <%= if @diagram.visibility == "public" do %>
              <.icon name="hero-lock-closed" /><span>{gettext("Tornar privado")}</span>
            <% else %>
              <.icon name="hero-globe-alt" /><span>{gettext("Tornar público")}</span>
            <% end %>
          </button>
          <div class="ba-menu__sep" role="separator"></div>
          <button
            type="button"
            class="ba-menu__item ba-menu__item--danger"
            role="menuitem"
            phx-click="diagram:delete"
            phx-value-slug={@diagram.slug}
            phx-value-title={@diagram.title}
          >
            <.icon name="hero-trash" /><span>{gettext("Excluir")}</span>
          </button>
        </div>
      </details>
    </article>
    """
  end

  # ── diálogos ──────────────────────────────────────────────────────────────

  attr :form, :any, required: true
  attr :project, :any, default: nil
  attr :colors, :list, required: true

  defp project_dialog(assigns) do
    ~H"""
    <.modal
      id="project-dialog"
      title={if @project, do: gettext("Editar projeto"), else: gettext("Novo projeto")}
    >
      <.form
        for={@form}
        id="project-form"
        phx-change="project:validate"
        phx-submit="project:save"
      >
        <div class="ba-modal__body">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Nome")}
            placeholder={gettext("Ex.: Pagamentos, Onboarding, RFCs")}
            maxlength="60"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <fieldset class="ba-field ba-swatches">
            <legend class="ba-field__label">{gettext("Cor")}</legend>
            <div class="ba-swatches__row">
              <label :for={color <- @colors} class="ba-swatch" title={color_name(color)}>
                <input
                  type="radio"
                  name={@form[:color].name}
                  value={color}
                  checked={@form[:color].value == color}
                  aria-label={color_name(color)}
                />
                <span class="ba-projdot ba-projdot--swatch" data-color={color}></span>
              </label>
            </div>
          </fieldset>
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="dialog:close">{gettext("Cancelar")}</.button>
          <.button type="submit" variant="primary" id="project-submit">
            {if @project, do: gettext("Salvar"), else: gettext("Criar projeto")}
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :form, :any, required: true
  attr :projects, :list, required: true

  defp new_diagram_dialog(assigns) do
    ~H"""
    <.modal id="new-diagram-dialog" title={gettext("Novo diagrama")}>
      <.form
        for={@form}
        id="new-diagram-form"
        phx-change="diagram:validate"
        phx-submit="diagram:create"
      >
        <div class="ba-modal__body">
          <.input
            field={@form[:title]}
            type="text"
            label={gettext("Nome")}
            placeholder={gettext("Ex.: Checkout com pagamento assíncrono")}
            maxlength="160"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <fieldset class="ba-field">
            <legend class="ba-field__label">{gettext("Tipo")}</legend>
            <div class="ba-choice">
              <label :for={kind <- ~w(sequence architecture)} class="ba-choice__opt">
                <input
                  type="radio"
                  name={@form[:kind].name}
                  value={kind}
                  checked={@form[:kind].value == kind}
                  class="ba-choice__radio"
                />
                <strong><.icon name={kind_icon(kind)} />{kind_label(kind)}</strong>
                <span>{kind_hint(kind)}</span>
              </label>
            </div>
          </fieldset>
          <.input
            field={@form[:project]}
            type="select"
            label={gettext("Projeto")}
            options={project_options(@projects)}
          />
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="dialog:close">{gettext("Cancelar")}</.button>
          <.button type="submit" variant="primary" id="new-diagram-submit">
            <.icon name="hero-arrow-right" />{gettext("Criar e abrir")}
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :form, :any, required: true

  defp rename_dialog(assigns) do
    ~H"""
    <.modal id="rename-dialog" title={gettext("Renomear diagrama")}>
      <.form for={@form} id="rename-form" phx-submit="diagram:rename-save">
        <div class="ba-modal__body">
          <.input
            field={@form[:title]}
            type="text"
            label={gettext("Nome")}
            maxlength="160"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <p class="ba-callout">
            <.icon name="hero-information-circle" />
            {gettext("O nome fica no código do diagrama, na linha “diagram … \"nome\"”.")}
          </p>
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="dialog:close">{gettext("Cancelar")}</.button>
          <.button type="submit" variant="primary" id="rename-submit">{gettext("Renomear")}</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :form, :any, required: true
  attr :projects, :list, required: true
  attr :upload, :any, required: true
  attr :report, :any, default: nil

  # Importar: soltar (ou escolher) arquivos .brain, pacotes .json, Mermaid ou
  # PlantUML. Arquivo solto vai para o projeto escolhido; pacote traz os seus.
  defp import_dialog(assigns) do
    ~H"""
    <.modal id="import-dialog" title={gettext("Importar diagramas")}>
      <.form
        for={@form}
        id="import-files-form"
        phx-change="import:validate"
        phx-submit="import:save"
      >
        <div class="ba-modal__body">
          <label class="ba-dropzone" phx-drop-target={@upload.ref} for={@upload.ref}>
            <.icon name="hero-arrow-up-tray" class="ba-dropzone__icon" />
            <span class="ba-dropzone__title">
              {gettext("Solte os arquivos aqui ou clique para escolher")}
            </span>
            <span class="ba-dropzone__hint">
              {gettext(
                ".brain e pacotes .json exportados do Brainagram, Mermaid (.mmd) ou PlantUML (.puml)"
              )}
            </span>
            <.live_file_input upload={@upload} class="ba-dropzone__input" />
          </label>

          <p :for={err <- upload_errors(@upload)} class="ba-field__error">
            <.icon name="hero-exclamation-triangle" class="ba-ico--16" />{upload_error(err)}
          </p>

          <ul :if={@upload.entries != []} class="ba-filelist" id="import-files">
            <li :for={entry <- @upload.entries} class="ba-filelist__item" id={"file-#{entry.ref}"}>
              <.icon name={file_icon(entry.client_name)} class="ba-ico--16" />
              <span class="ba-filelist__name">{entry.client_name}</span>
              <span class="ba-filelist__size">{file_size(entry.client_size)}</span>
              <span :for={err <- upload_errors(@upload, entry)} class="ba-filelist__error">
                {upload_error(err)}
              </span>
              <button
                type="button"
                class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost"
                phx-click="import:cancel-file"
                phx-value-ref={entry.ref}
                aria-label={gettext("Remover %{name}", name: entry.client_name)}
              >
                <.icon name="hero-x-mark" class="ba-ico--16" />
              </button>
            </li>
          </ul>

          <.input
            field={@form[:project]}
            type="select"
            label={gettext("Projeto de destino")}
            options={project_options(@projects)}
          />
          <p class="ba-field__hint">
            {gettext(
              "Pacotes .json recriam os projetos deles; o destino vale para os diagramas soltos."
            )}
          </p>

          <div :if={@report} class="ba-import-report" id="import-report" role="status">
            <p :if={@report.created != []} class="ba-import-report__ok">
              <.icon name="hero-check-circle" class="ba-ico--16" />{import_message(@report)}
            </p>
            <p class="ba-import-report__title">{gettext("Não importados")}</p>
            <ul>
              <li :for={failure <- @report.failed}>
                <strong>{failure.name}</strong> — {ErrorMessages.describe(failure.reason)}
              </li>
            </ul>
          </div>
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="dialog:close">
            {if @report, do: gettext("Fechar"), else: gettext("Cancelar")}
          </.button>
          <.button
            type="submit"
            variant="primary"
            id="import-submit"
            disabled={@upload.entries == []}
          >
            <.icon name="hero-arrow-up-tray" />
            {ngettext(
              "Importar 1 arquivo",
              "Importar %{count} arquivos",
              max(length(@upload.entries), 1)
            )}
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp upload_error(:too_large), do: gettext("Arquivo grande demais (até 2 MB).")
  defp upload_error(:not_accepted), do: gettext("Formato não aceito.")
  defp upload_error(:too_many_files), do: gettext("Arquivos demais de uma vez (até 50).")
  defp upload_error(_), do: gettext("Não foi possível enviar o arquivo.")

  defp file_icon(name) do
    if String.ends_with?(String.downcase(name), ".json"),
      do: "hero-archive-box",
      else: "hero-document-text"
  end

  defp file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp file_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  attr :form, :any, required: true
  attr :projects, :list, required: true

  defp move_dialog(assigns) do
    ~H"""
    <.modal id="move-dialog" title={gettext("Mover para projeto")}>
      <.form for={@form} id="move-form" phx-submit="diagram:move-save">
        <div class="ba-modal__body">
          <.input
            field={@form[:project]}
            type="select"
            label={gettext("Projeto")}
            options={project_options(@projects)}
          />
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="dialog:close">{gettext("Cancelar")}</.button>
          <.button type="submit" variant="primary" id="move-submit">{gettext("Mover")}</.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :confirm, :string, required: true
  attr :action, :string, required: true
  slot :inner_block, required: true

  defp confirm_dialog(assigns) do
    ~H"""
    <.modal id={@id} title={@title}>
      <div class="ba-modal__body">
        <p class="ba-dash__confirm">{render_slot(@inner_block)}</p>
      </div>
      <div class="ba-modal__foot">
        <span class="ba-spacer"></span>
        <.button type="button" phx-click="dialog:close">{gettext("Cancelar")}</.button>
        <.button variant="danger" id={"#{@id}-submit"} phx-click={@confirm}>{@action}</.button>
      </div>
    </.modal>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  # Mesmo esqueleto do diálogo de import do editor: fundo que fecha, Esc
  # fecha, título ligado ao `aria-labelledby`.
  defp modal(assigns) do
    ~H"""
    <div class="ba-overlay" phx-window-keydown="dialog:close" phx-key="Escape">
      <div
        class="ba-modal"
        id={@id}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-click-away="dialog:close"
      >
        <div class="ba-modal__head">
          <h2 class="ba-modal__title" id={"#{@id}-title"}>{@title}</h2>
          <button
            type="button"
            class="ba-btn ba-btn--icon ba-btn--ghost ba-btn--sm"
            phx-click="dialog:close"
            aria-label={gettext("Fechar")}
          >
            <.icon name="hero-x-mark" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── textos ────────────────────────────────────────────────────────────────

  defp project_options(projects) do
    [{gettext("Sem projeto"), ""} | Enum.map(projects, &{&1.name, &1.slug})]
  end

  # A URL da miniatura muda quando o diagrama muda (`updated_at`) e quando o
  # jeito de desenhar a miniatura muda (`@preview_rev`): o cache pode ser eterno.
  defp version(%{updated_at: %DateTime{} = at}), do: "#{DateTime.to_unix(at)}.#{@preview_rev}"
  defp version(_), do: "0.#{@preview_rev}"

  defp kind_icon("architecture"), do: "hero-rectangle-group"
  defp kind_icon(_), do: "hero-bars-3"

  defp kind_label("architecture"), do: gettext("Arquitetura")
  defp kind_label(_), do: gettext("Sequência")

  defp kind_hint("architecture"),
    do: gettext("Componentes, grupos e setas entre eles — a visão do sistema.")

  defp kind_hint(_), do: gettext("Mensagens entre participantes, passo a passo, no tempo.")

  defp color_name("violet"), do: gettext("Violeta")
  defp color_name("blue"), do: gettext("Azul")
  defp color_name("teal"), do: gettext("Turquesa")
  defp color_name("green"), do: gettext("Verde")
  defp color_name("amber"), do: gettext("Âmbar")
  defp color_name("orange"), do: gettext("Laranja")
  defp color_name("rose"), do: gettext("Rosa")
  defp color_name(_), do: gettext("Grafite")
end

defmodule BrainagramWeb.EditorLive do
  @moduledoc """
  Editor: DSL à esquerda, diagrama animado à direita.

  Esta LiveView não conhece Ecto, repositório, agregado, handler nem PubSub. Ela
  conhece um endereço só — o `Bus` — e três verbos: `dispatch/2` para mudar
  estado, `ask/2` para ler e `subscribe/1` para ouvir. Toda regra de negócio está
  do outro lado dessa fronteira, e é por isso que o arquivo cabe na cabeça mesmo
  com cinco ações e um canal de eventos.

  Ela também não participa da reprodução da animação: assim que a `Scene` vai
  para o cliente por `push_event`, play, scrub, zoom e pan acontecem sem tocar
  no servidor.
  """

  use BrainagramWeb, :live_view

  alias Brainagram.Application.Bus

  alias Brainagram.Application.Commands.{
    ChangeDiagramSource,
    ChangeDiagramVisibility,
    CreateDiagram,
    ForkDiagram
  }

  alias Brainagram.Application.Queries.{
    EditSource,
    GetDiagramBySlug,
    GetExample,
    ImportDiagram,
    ListExamples,
    RenderScene
  }

  alias Brainagram.Domain.Diagramming.Events
  alias BrainagramWeb.ErrorMessages

  @impl true
  def mount(_params, _session, socket) do
    {:ok, examples} = Bus.ask(ListExamples)
    source = examples |> List.first() |> Map.fetch!(:source)

    {:ok,
     socket
     |> assign(diagram: nil, examples: examples, errors: [], remote_change: false)
     |> assign(new_project: nil)
     |> assign(import_open: false, import_error: nil)
     # `saved_source`: o texto como está salvo (ou como o diagrama novo nasceu);
     # o que difere dele é "alteração não salva".
     |> assign(presenting: false, keep_mode: false, saved_source: source)
     |> compile(source)}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    case Bus.ask(GetDiagramBySlug, %{slug: slug}) do
      {:ok, detail} ->
        socket =
          socket
          |> assign(presenting: presenting?(socket, detail.slug, params))
          |> watch(detail.slug)
          |> assign(diagram: detail, remote_change: false, keep_mode: false)
          |> assign(saved_source: detail.source)

        socket =
          if detail.scene do
            assign(socket, source: detail.source, scene: detail.scene, errors: [])
          else
            compile(socket, detail.source)
          end

        {:noreply, push_scene(socket)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, ErrorMessages.describe(:not_found))
         |> push_navigate(to: ~p"/")}
    end
  end

  # `/new?project=abc`: o diagrama novo, ao salvar, já nasce nesse projeto.
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(new_project: blank_to_nil(params["project"]), presenting: false)
     |> push_scene()}
  end

  # Quem abre um link `/d/:slug` assiste: o padrão é a apresentação (diagrama,
  # player e passos). `?edit=1` abre no editor — é o link da área de gestão,
  # onde quem clica é o autor. Salvar, duplicar ou recarregar o mesmo diagrama
  # não troca o modo em que a pessoa já estava.
  defp presenting?(socket, slug, params) do
    cond do
      params["edit"] in ["1", "true"] -> false
      socket.assigns.keep_mode -> socket.assigns.presenting
      match?(%{slug: ^slug}, socket.assigns.diagram) -> socket.assigns.presenting
      true -> true
    end
  end

  # ── comandos e queries ────────────────────────────────────────────────────

  @impl true
  def handle_event("edit", %{"source" => source}, socket) do
    {:noreply, socket |> compile(source) |> push_scene()}
  end

  # Trocar de exemplo substitui o texto — e entra na pilha de desfazer como
  # qualquer outra edição, então Ctrl+Z traz o texto anterior de volta.
  def handle_event("example", %{"slug" => slug}, socket) do
    case Bus.ask(GetExample, %{slug: slug}) do
      {:ok, example} ->
        # num diagrama ainda não salvo, o exemplo é o novo ponto de partida, não
        # uma alteração; num diagrama salvo, substituir o texto é sim alteração
        socket =
          if socket.assigns.diagram,
            do: socket,
            else: assign(socket, saved_source: example.source)

        {:noreply,
         socket
         |> compile(example.source)
         |> push_source()
         |> push_scene()
         |> put_flash(:info, gettext("Exemplo carregado. Ctrl+Z desfaz."))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ── autoria pelo canvas (spec 001) ────────────────────────────────────────

  # Todo gesto do canvas (arrastar, renomear, conectar, apagar…) e os comandos
  # de texto que reescrevem o arquivo (formatar, mover passo) chegam aqui. A
  # query aplica a edição cirúrgica sobre o texto da sessão e devolve texto e
  # cena novos; persistir continua sendo o "Salvar".
  def handle_event("canvas", %{"op" => op} = payload, socket) do
    {:noreply, edit_source(socket, op, Map.get(payload, "params") || %{})}
  end

  def handle_event("canvas_op", %{"op" => op}, socket) do
    {:noreply, edit_source(socket, op, %{})}
  end

  # Apresentar ↔ editar: só a interface muda; o texto (e o que não foi salvo)
  # continua onde estava.
  def handle_event("present", _params, socket), do: {:noreply, assign(socket, presenting: true)}

  def handle_event("edit_mode", _params, socket),
    do: {:noreply, assign(socket, presenting: false)}

  def handle_event("present:toggle", _params, socket),
    do: {:noreply, assign(socket, presenting: !socket.assigns.presenting)}

  def handle_event("import:open", _params, socket) do
    {:noreply, assign(socket, import_open: true, import_error: nil)}
  end

  def handle_event("import:close", _params, socket) do
    {:noreply, assign(socket, import_open: false, import_error: nil)}
  end

  def handle_event("import", %{"text" => text} = params, socket) do
    attrs = %{
      text: text,
      format: params["format"] || "auto",
      organize: params["organize"] == "true"
    }

    case Bus.ask(ImportDiagram, attrs) do
      {:ok, %{source: source, warnings: warnings} = result} ->
        message = import_message(length(warnings), result[:organized])

        {:noreply,
         socket
         |> assign(import_open: false, import_error: nil)
         |> compile(source)
         |> push_source()
         |> push_scene()
         |> put_flash(:info, message)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         assign(socket, import_error: gettext("Cole o texto do diagrama para importar."))}

      {:error, reason} ->
        {:noreply, assign(socket, import_error: ErrorMessages.describe(reason))}
    end
  end

  def handle_event("save", _params, socket) do
    case socket.assigns.diagram do
      nil ->
        run(
          socket,
          CreateDiagram,
          %{source: socket.assigns.source, project: socket.assigns.new_project},
          gettext("Salvo. O link já é compartilhável.")
        )

      diagram ->
        run(
          socket,
          ChangeDiagramSource,
          %{slug: diagram.slug, source: socket.assigns.source},
          gettext("Alterações salvas.")
        )
    end
  end

  def handle_event("toggle-visibility", _params, %{assigns: %{diagram: nil}} = socket) do
    {:noreply, put_flash(socket, :error, gettext("Salve o diagrama antes de publicar."))}
  end

  def handle_event("toggle-visibility", _params, socket) do
    diagram = socket.assigns.diagram
    next = if diagram.visibility == "public", do: "private", else: "public"

    run(
      socket,
      ChangeDiagramVisibility,
      %{slug: diagram.slug, visibility: next},
      if(next == "public", do: gettext("Agora é público."), else: gettext("Agora é privado."))
    )
  end

  def handle_event("fork", _params, %{assigns: %{diagram: nil}} = socket) do
    {:noreply, put_flash(socket, :error, gettext("Salve o diagrama antes de duplicar."))}
  end

  def handle_event("fork", _params, socket) do
    run(socket, ForkDiagram, %{slug: socket.assigns.diagram.slug}, gettext("Cópia criada."))
  end

  def handle_event("reload", _params, socket) do
    {:noreply,
     socket |> assign(keep_mode: true) |> push_patch(to: ~p"/d/#{socket.assigns.diagram.slug}")}
  end

  # ── eventos de domínio ────────────────────────────────────────────────────

  @impl true
  def handle_info({:domain_event, %Events.DiagramSourceChanged{} = event}, socket) do
    # Não sobrescrevemos o textarea: a pessoa pode estar digitando. Avisamos e
    # deixamos a decisão com ela.
    case Bus.ask(GetDiagramBySlug, %{slug: event.slug}) do
      {:ok, detail} when detail.source != socket.assigns.source ->
        {:noreply, assign(socket, remote_change: true)}

      _ ->
        {:noreply, assign(socket, remote_change: false)}
    end
  end

  # Mudou de projeto (noutra aba, ou o projeto foi excluído): só a trilha do
  # topo muda; o texto em edição fica como está.
  def handle_info({:domain_event, %Events.DiagramMoved{slug: slug}}, socket) do
    case {socket.assigns.diagram, Bus.ask(GetDiagramBySlug, %{slug: slug})} do
      {%{slug: ^slug} = diagram, {:ok, detail}} ->
        {:noreply,
         assign(socket,
           diagram: %{
             diagram
             | project: detail.project,
               project_name: detail.project_name,
               project_color: detail.project_color
           }
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:domain_event, %Events.DiagramDeleted{}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("Este diagrama foi removido."))
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:domain_event, %Events.DiagramVisibilityChanged{} = event}, socket) do
    diagram = socket.assigns.diagram

    if diagram && diagram.slug == event.slug do
      {:noreply, assign(socket, diagram: %{diagram | visibility: event.visibility})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:domain_event, _event}, socket), do: {:noreply, socket}

  # ── plumbing ──────────────────────────────────────────────────────────────

  # Um comando só pode terminar de três jeitos, e os três estão aqui: sucesso,
  # falha de validação da mensagem (changeset) e falha de regra (átomo).
  defp run(socket, command, attrs, message) do
    case Bus.dispatch(command, attrs) do
      {:ok, slug} when is_binary(slug) ->
        {:noreply,
         socket
         |> assign(keep_mode: true)
         |> put_flash(:info, message)
         |> push_patch(to: ~p"/d/#{slug}")}

      {:ok, _other} ->
        {:noreply, put_flash(socket, :info, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, describe_validation(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, ErrorMessages.describe(reason))}
    end
  end

  defp import_message(warnings, organized) do
    base =
      case warnings do
        0 ->
          gettext("Diagrama importado")

        n ->
          ngettext(
            "Importado com 1 aviso (veja o comentário no topo do código)",
            "Importado com %{count} avisos (veja o comentário no topo do código)",
            n
          )
      end

    case organized do
      %{before: %{crossings: b}, after: %{crossings: a}} when a < b ->
        ngettext(
          "%{base}; setas organizadas: %{before} → 1 cruzamento. Ctrl+Z desfaz.",
          "%{base}; setas organizadas: %{before} → %{count} cruzamentos. Ctrl+Z desfaz.",
          a,
          base: base,
          before: b
        )

      %{} ->
        gettext("%{base}; setas organizadas. Ctrl+Z desfaz.", base: base)

      nil ->
        gettext("%{base}. Ctrl+Z desfaz.", base: base)
    end
  end

  defp describe_validation(changeset) do
    changeset
    |> Bus.validation_errors()
    |> Enum.map_join("; ", fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
  end

  # Erro de sintaxe não apaga o diagrama: a última cena válida continua na tela
  # enquanto a barra de erros mostra a linha problemática.
  defp compile(socket, source) do
    case Bus.ask(RenderScene, %{source: source}) do
      {:ok, scene} ->
        assign(socket, source: source, scene: scene, errors: [])

      {:error, {:syntax, errors}} ->
        assign(socket, source: source, errors: errors)

      {:error, reason} ->
        socket |> assign(source: source) |> put_flash(:error, ErrorMessages.describe(reason))
    end
  end

  defp edit_source(socket, op, params) do
    case Bus.ask(EditSource, %{source: socket.assigns.source, op: op, params: params}) do
      {:ok, %{source: source, scene: scene, meta: meta}} ->
        socket
        |> assign(source: source, scene: scene, errors: [])
        |> push_source(meta[:line])
        |> push_scene()
        |> push_created(meta)
        |> notice(op, meta)

      {:error, {:syntax, _}} ->
        put_flash(
          socket,
          :error,
          gettext("Corrija o erro de sintaxe no código antes de editar pelo canvas.")
        )

      {:error, %Ecto.Changeset{}} ->
        put_flash(socket, :error, ErrorMessages.describe(:unknown_operation))

      {:error, reason} ->
        put_flash(socket, :error, ErrorMessages.describe(reason))
    end
  end

  # O LiveView não reescreve um campo com foco, então o texto novo vai por
  # evento ao editor — que também o registra na pilha de desfazer.
  defp push_source(socket, line \\ nil) do
    payload =
      if line,
        do: %{source: socket.assigns.source, line: line},
        else: %{source: socket.assigns.source}

    push_event(socket, "bg:source", payload)
  end

  defp push_created(socket, %{node_id: id}), do: push_event(socket, "bg:created", %{node_id: id})
  defp push_created(socket, %{edge_id: id}), do: push_event(socket, "bg:created", %{edge_id: id})
  defp push_created(socket, _meta), do: socket

  defp notice(socket, "format", %{comments_dropped: true}),
    do:
      put_flash(
        socket,
        :info,
        gettext("Código formatado. Os comentários foram removidos — Ctrl+Z desfaz.")
      )

  defp notice(socket, "format", _meta), do: put_flash(socket, :info, gettext("Código formatado."))

  defp notice(socket, "clear_layout", _meta),
    do: put_flash(socket, :info, gettext("Posições soltas: layout automático de novo."))

  defp notice(socket, "untangle", %{improved: false}),
    do: put_flash(socket, :info, gettext("As setas já estão organizadas — nada a mudar."))

  defp notice(socket, "untangle", %{before: before, after: after_}),
    do: put_flash(socket, :info, untangle_message(before, after_))

  defp notice(socket, _op, _meta), do: socket

  defp untangle_message(%{crossings: b}, %{crossings: a}) when a < b,
    do:
      ngettext(
        "Setas organizadas: %{before} → 1 cruzamento. Ctrl+Z desfaz.",
        "Setas organizadas: %{before} → %{count} cruzamentos. Ctrl+Z desfaz.",
        a,
        before: b
      )

  defp untangle_message(_before, _after),
    do: gettext("Setas organizadas: caminhos mais curtos e sem atravessar caixas. Ctrl+Z desfaz.")

  defp push_scene(socket) do
    case socket.assigns[:scene] do
      nil ->
        socket

      scene ->
        socket
        |> assign(page_title: "#{scene.title || gettext("Sem título")} · Brainagram")
        |> push_event("bg:scene", %{scene: scene})
    end
  end

  defp watch(socket, slug) do
    if connected?(socket) do
      if previous = socket.assigns[:diagram], do: Bus.unsubscribe(previous.slug)
      Bus.subscribe(slug)
    end

    socket
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, dirty: assigns.source != assigns.saved_source)

    ~H"""
    <div
      class="ba-editor"
      id="editor"
      data-presenting={to_string(@presenting)}
      data-dirty={to_string(@dirty)}
    >
      <.topbar
        diagram={@diagram}
        examples={@examples}
        scene={@scene}
        locale={@locale}
        presenting={@presenting}
        dirty={@dirty}
      />

      <div class="ba-editor__main">
        <.source_pane
          source={@source}
          errors={@errors}
          remote_change={@remote_change}
          ids={Enum.map(@scene.nodes, & &1.id)}
        />

        <main class="ba-editor__center">
          <div
            id="stage"
            phx-hook="DiagramCanvas"
            class="ba-editor__stage"
            data-presenting={to_string(@presenting)}
          >
            <div
              id="canvas"
              data-bg-canvas
              phx-update="ignore"
              class="bg-stage ba-editor__canvas"
            >
            </div>
            <.canvas_tools scene={@scene} />
            <div id="canvas-overlay" phx-update="ignore" class="ba-overlay-layer"></div>
          </div>

          <.transport />
        </main>

        <.steps_pane scene={@scene} />
      </div>

      <%!-- o anúncio do passo para leitores de tela fica fora do painel de
           passos, que vira gaveta (e some da tela) em telas estreitas --%>
      <p class="ba-sr" data-bg-display="step" aria-live="polite">—</p>

      <div
        id="command-palette"
        phx-hook="CommandPalette"
        phx-update="ignore"
        class="ba-overlay ba-overlay--top"
        hidden
      >
      </div>

      <.import_dialog :if={@import_open} error={@import_error} />

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :diagram, :map, default: nil
  attr :examples, :list, required: true
  attr :scene, :map, required: true
  attr :locale, :string, required: true
  attr :presenting, :boolean, default: false
  attr :dirty, :boolean, default: false

  # Duas barras para dois públicos (PRODUCT.md): quem assiste vê o título, a
  # exportação e um "Editar"; quem escreve vê abrir, apresentar, duplicar e
  # salvar. Em telas estreitas os botões ficam só com o ícone (o nome segue no
  # aria-label) e idioma/tema saem da barra — continuam na área de gestão.
  defp topbar(assigns) do
    ~H"""
    <header class="ba-topbar">
      <.link
        navigate={~p"/"}
        class="ba-topbar__brand"
        id="back-to-dashboard"
        aria-label={gettext("Brainagram, meus diagramas")}
        title={gettext("Meus diagramas")}
        data-confirm={@dirty && leave_warning()}
      >
        <.logo />
      </.link>
      <span class="ba-topbar__slash" aria-hidden="true">/</span>
      <.link
        navigate={crumb_path(@diagram)}
        class="ba-crumb ba-topbar__hide-sm"
        id="breadcrumb-project"
        data-confirm={@dirty && leave_warning()}
        title={
          if(@diagram && @diagram.project,
            do: @diagram.project_name,
            else: gettext("Meus diagramas")
          )
        }
      >
        <%= if @diagram && @diagram.project do %>
          <span class="ba-projdot" data-color={@diagram.project_color} aria-hidden="true"></span>
          {@diagram.project_name}
        <% else %>
          {gettext("Diagramas")}
        <% end %>
      </.link>
      <span class="ba-topbar__slash ba-topbar__hide-sm" aria-hidden="true">/</span>
      <div class="ba-topbar__title">
        <h1 title={gettext("O título vem da 1ª linha do código")}>
          {@scene.title || gettext("Sem título")}
        </h1>
        <span
          :if={@dirty and not @presenting}
          class="ba-save ba-save--dirty"
          id="unsaved-marker"
          role="status"
        >
          <span class="ba-badge__dot" aria-hidden="true"></span>
          <span class="ba-btn__label">{gettext("Alterações não salvas")}</span>
        </span>
      </div>

      <button
        :if={@diagram && not @presenting}
        type="button"
        id="visibility-toggle"
        class={[
          "ba-badge ba-badge--toggle ba-topbar__hide-sm",
          if(@diagram.visibility == "public", do: "ba-badge--success", else: "ba-badge--outline")
        ]}
        phx-click="toggle-visibility"
        title={visibility_hint(@diagram.visibility)}
        data-confirm={
          @diagram.visibility != "public" &&
            gettext("Tornar público? O diagrama passa a aparecer na galeria pública.")
        }
      >
        <%= if @diagram.visibility == "public" do %>
          <.icon name="hero-globe-alt" />{gettext("Público")}
        <% else %>
          <.icon name="hero-lock-closed" />{gettext("Privado")}
        <% end %>
      </button>

      <span class="ba-topbar__spacer"></span>

      <div class="ba-topbar__actions">
        <%= if @presenting do %>
          <.export_menu />
          <.button
            id="edit-diagram"
            phx-click="edit_mode"
            aria-label={gettext("Editar (P)")}
            title={gettext("Abrir o código e as ferramentas de edição (P)")}
          >
            <.icon name="hero-pencil-square" /><span class="ba-btn__label">{gettext("Editar")}</span>
          </.button>
        <% else %>
          <button
            type="button"
            class="ba-btn ba-btn--ghost ba-btn--sm ba-topbar__hide-sm"
            phx-click={JS.dispatch("bg:palette")}
            aria-label={gettext("Paleta de comandos (Ctrl+K)")}
            title={gettext("Paleta de comandos")}
          >
            <.icon name="hero-magnifying-glass" /><span class="ba-kbd">Ctrl K</span>
          </button>

          <details class="ba-dropdown" id="examples-menu">
            <summary class="ba-btn ba-btn--ghost" aria-label={gettext("Abrir")}>
              <.icon name="hero-folder-open" /><span class="ba-btn__label">{gettext("Abrir")}</span><.icon
                name="hero-chevron-down"
                class="ba-ico--16"
              />
            </summary>
            <div class="ba-menu ba-dropdown__menu" role="menu">
              <div class="ba-menu__label">{gettext("Exemplos")}</div>
              <button
                :for={ex <- @examples}
                type="button"
                class="ba-menu__item"
                role="menuitem"
                phx-click="example"
                phx-value-slug={ex.slug}
                data-confirm={
                  (@diagram || @dirty) &&
                    gettext("Substituir o código atual por este exemplo? Ctrl+Z desfaz.")
                }
              >
                <.icon name="hero-document-text" />
                <span>{example_name(ex.name)}</span>
              </button>
              <div class="ba-menu__sep" role="separator"></div>
              <div class="ba-menu__label">{gettext("Importar")}</div>
              <button
                type="button"
                class="ba-menu__item"
                role="menuitem"
                id="open-import"
                phx-click="import:open"
              >
                <.icon name="hero-arrow-down-tray" />
                <span>
                  {gettext("Importar diagrama…")}<small>{gettext(".brain, Mermaid ou PlantUML")}</small>
                </span>
              </button>
            </div>
          </details>

          <.export_menu />

          <.button
            id="present-diagram"
            variant="ghost"
            phx-click="present"
            aria-label={gettext("Apresentar (P)")}
            title={gettext("Só o diagrama, o player e os passos (P)")}
          >
            <.icon name="hero-presentation-chart-bar" /><span class="ba-btn__label">{gettext(
              "Apresentar"
            )}</span>
          </.button>

          <.button
            :if={@diagram}
            variant="ghost"
            phx-click="fork"
            class="ba-topbar__hide-sm"
            aria-label={gettext("Duplicar")}
          >
            <.icon name="hero-document-duplicate" /><span class="ba-btn__label">{gettext("Duplicar")}</span>
          </.button>

          <.button
            id="save-button"
            variant={if(@dirty or is_nil(@diagram), do: "primary")}
            phx-click="save"
            aria-label={gettext("Salvar (Ctrl+S)")}
            title={gettext("Salvar (Ctrl+S)")}
          >
            <.icon name="hero-cloud-arrow-up" /><span class="ba-btn__label">{gettext("Salvar")}</span>
          </.button>
        <% end %>

        <span class="ba-topbar__prefs ba-topbar__hide-sm">
          <Layouts.locale_toggle locale={@locale} />
          <Layouts.theme_toggle />
        </span>
      </div>
    </header>
    """
  end

  # Exportar vale nos dois modos: quem assiste também leva o diagrama embora.
  defp export_menu(assigns) do
    ~H"""
    <details class="ba-dropdown" id="export-menu">
      <summary class="ba-btn" aria-label={gettext("Exportar")}>
        <.icon name="hero-arrow-down-tray" /><span class="ba-btn__label">{gettext("Exportar")}</span><.icon
          name="hero-chevron-down"
          class="ba-ico--16"
        />
      </summary>
      <div class="ba-menu ba-dropdown__menu" role="menu">
        <div class="ba-menu__label">{gettext("Imagem do estado final")}</div>
        <button type="button" class="ba-menu__item" role="menuitem" data-bg-control="export-svg">
          <.icon name="hero-code-bracket-square" />
          <span>SVG<small>{gettext("Vetor com as cores do tema")}</small></span>
        </button>
        <button type="button" class="ba-menu__item" role="menuitem" data-bg-control="export-png">
          <.icon name="hero-photo" />
          <span>PNG 2×<small>{gettext("Imagem para slides e docs")}</small></span>
        </button>
        <div class="ba-menu__sep" role="separator"></div>
        <div class="ba-menu__label">{gettext("Animação")}</div>
        <button
          type="button"
          class="ba-menu__item"
          role="menuitem"
          id="export-gif"
          data-bg-control="export-gif"
        >
          <.icon name="hero-film" />
          <span>
            {gettext("GIF animado (HD)")}<small>{gettext("Nítido em 2×, para slides, PRs e docs")}</small>
          </span>
        </button>
        <button
          type="button"
          class="ba-menu__item"
          role="menuitem"
          id="export-gif-light"
          data-bg-control="export-gif-light"
        >
          <.icon name="hero-film" />
          <span>
            {gettext("GIF leve")}
            <small>{gettext("Arquivo menor, para chats com limite de tamanho")}</small>
          </span>
        </button>
        <div class="ba-menu__sep" role="separator"></div>
        <div class="ba-menu__label">{gettext("Diagrama")}</div>
        <button
          type="button"
          class="ba-menu__item"
          role="menuitem"
          id="export-brain"
          data-bg-control="export-brain"
        >
          <.icon name="hero-document-text" />
          <span>
            {gettext("Arquivo .brain")}
            <small>{gettext("O código, para importar aqui de novo ou versionar")}</small>
          </span>
        </button>
      </div>
    </details>
    """
  end

  defp leave_warning, do: gettext("Há alterações não salvas. Sair mesmo assim?")

  attr :source, :string, required: true
  attr :errors, :list, required: true
  attr :remote_change, :boolean, default: false
  attr :ids, :list, default: []

  defp source_pane(assigns) do
    ~H"""
    <aside class="ba-panel ba-editor__code" aria-label={gettext("Código")}>
      <div class="ba-panel__head">
        <h2 class="ba-panel__title">{gettext("Código")}</h2>
        <span :if={@errors == []} class="ba-validity ba-validity--ok">
          <.icon name="hero-check-circle" />{gettext("Sem erros")}
        </span>
        <button
          :if={@errors != []}
          type="button"
          id="goto-error"
          class="ba-validity ba-validity--err"
          phx-click={JS.dispatch("bg:command", detail: %{action: "next-error"})}
          title={gettext("Ir para o erro (F8)")}
        >
          <.icon name="hero-x-circle" />{error_count(@errors)}
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost"
          data-bg-history="undo"
          phx-click={JS.dispatch("bg:command", detail: %{action: "undo"})}
          aria-label={gettext("Desfazer (Ctrl+Z)")}
          title={gettext("Desfazer (Ctrl+Z)")}
        >
          <.icon name="hero-arrow-uturn-left" class="ba-ico--16" />
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost"
          data-bg-history="redo"
          phx-click={JS.dispatch("bg:command", detail: %{action: "redo"})}
          aria-label={gettext("Refazer (Ctrl+Shift+Z)")}
          title={gettext("Refazer (Ctrl+Shift+Z)")}
        >
          <.icon name="hero-arrow-uturn-right" class="ba-ico--16" />
        </button>
      </div>

      <div :if={@remote_change} class="ba-banner ba-banner--warning" role="alert">
        <.icon name="hero-exclamation-triangle" />
        <span class="ba-spacer">
          {gettext("Alguém salvou uma versão mais nova deste diagrama.")}
        </span>
        <.button size="sm" phx-click="reload">{gettext("Recarregar")}</.button>
      </div>

      <div id="complete-layer" phx-update="ignore" class="ba-overlay-layer"></div>

      <form id="source-form" phx-change="edit" class="ba-source-form">
        <%!-- números de linha: os erros citam "Linha N", então elas precisam
             estar à vista; as linhas não quebram para cada uma ter o seu número --%>
        <div id="source-gutter" class="ba-source__gutter" phx-update="ignore" aria-hidden="true">
        </div>
        <textarea
          id="source"
          name="source"
          phx-debounce="220"
          phx-hook="SourceEditor"
          spellcheck="false"
          autocomplete="off"
          wrap="off"
          aria-label={gettext("Código do diagrama")}
          aria-invalid={to_string(@errors != [])}
          aria-describedby={@errors != [] && "source-errors"}
          data-ids={Jason.encode!(@ids)}
          data-error-lines={Jason.encode!(Enum.map(@errors, & &1.line))}
          class="ba-source"
        >{@source}</textarea>
      </form>

      <div :if={@errors != []} id="source-errors" class="ba-errors" role="alert">
        <div :for={err <- @errors} class="ba-errors__item">
          <span class="ba-errors__line">{gettext("Linha %{line}", line: err.line)}</span>
          <span>{ErrorMessages.parse_error(err)}</span>
        </div>
      </div>

      <.cheatsheet />
    </aside>
    """
  end

  defp cheatsheet(assigns) do
    ~H"""
    <details class="ba-panel__foot ba-cheat">
      <summary class="ba-panel__title">
        <.icon name="hero-chevron-down" class="ba-ico--16" />{gettext("Referência rápida")}
      </summary>
      <div class="ba-ref">
        <code>actor participant</code><span>{gettext("quem inicia, quem participa")}</span>
        <code>service component</code><span>{gettext("serviço, componente")}</span>
        <code>database queue</code><span>{gettext("banco de dados, fila")}</span>
        <code>external system</code><span>{gettext("sistema externo, sistema")}</span>
        <code>node boundary</code><span>{gettext("nó de implantação, fronteira")}</span>
        <code>a -&gt; b</code><span>{gettext("chamada síncrona")}</span>
        <code>a --&gt; b</code><span>{gettext("retorno")}</span>
        <code>a -&gt;&gt; b</code><span>{gettext("assíncrona")}</span>
        <code>a -x b</code><span>{gettext("falha / timeout")}</span>
        <code>step "…" &#123;&#125;</code><span>{gettext("um passo da animação")}</span>
        <code>group "…" &#123;&#125;</code><span>{gettext("agrupamento")}</span>
        <code>note over a, b :</code><span>{gettext("nota")}</span>
        <code>payload: {"{…}"}</code><span>{gettext("o que a mensagem carrega (logo abaixo dela)")}</span>
        <code>payload \"""</code><span>{gettext("payload em várias linhas, até outro \"\"\"")}</span>
      </div>
    </details>
    """
  end

  attr :scene, :map, required: true

  # Barra do canvas: tipo do diagrama, modo (editar / mover a tela) e as ações de
  # autoria — criar nó, conectar, organizar setas e soltar as posições fixadas.
  defp canvas_tools(assigns) do
    ~H"""
    <div class="ba-canvas-tools" role="toolbar" aria-label={gettext("Ferramentas do canvas")}>
      <span class="ba-badge ba-badge--outline ba-editor__kindbadge">
        <.icon name={kind_icon(@scene.kind)} />{kind_label(@scene.kind)}
      </span>

      <div class="ba-seg" role="radiogroup" aria-label={gettext("Modo do canvas")}>
        <%!-- o estado é do JS (modo guardado no navegador): o redesenho da barra
             a cada edição do código não pode desmarcar a opção escolhida --%>
        <button
          type="button"
          class="ba-seg__opt"
          role="radio"
          aria-checked="true"
          tabindex="0"
          data-bg-control="mode-edit"
          phx-mounted={JS.ignore_attributes(["aria-checked", "tabindex"])}
          title={gettext("Editar: arraste nós, puxe setas, duplo clique renomeia (E)")}
        >
          <.icon name="hero-cursor-arrow-rays" />{gettext("Editar")}
        </button>
        <button
          type="button"
          class="ba-seg__opt"
          role="radio"
          aria-checked="false"
          tabindex="-1"
          data-bg-control="mode-view"
          phx-mounted={JS.ignore_attributes(["aria-checked", "tabindex"])}
          title={gettext("Mover a tela: arrastar desloca o canvas (E)")}
        >
          <.icon name="hero-hand-raised" />{gettext("Mover")}
        </button>
      </div>

      <div class="ba-float">
        <button
          type="button"
          class="ba-btn ba-btn--sm"
          data-bg-control="add-node"
          title={gettext("Novo nó no centro (ou duplo clique numa área vazia)")}
        >
          <.icon name="hero-plus" />{gettext("Nó")}
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--sm"
          data-bg-control="connect"
          title={gettext("Clique na origem e depois no destino (ou arraste da alça de um nó)")}
        >
          <.icon name="hero-link" />{gettext("Conectar")}
        </button>
        <span class="ba-float__sep"></span>
        <button
          :if={@scene.kind == :architecture}
          type="button"
          class="ba-btn ba-btn--sm"
          id="untangle-layout"
          phx-click="canvas_op"
          phx-value-op="untangle"
          data-busy="spin"
          title={gettext("Reorganiza os componentes para as setas não se cruzarem (Ctrl+Z desfaz)")}
        >
          <.icon name="hero-sparkles" />{gettext("Organizar setas")}
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--sm"
          id="clear-layout"
          phx-click="canvas_op"
          phx-value-op="clear_layout"
          data-bg-needs-layout
          disabled={!@scene.has_layout}
          title={gettext("Apaga as posições fixadas e volta ao layout automático")}
        >
          <.icon name="hero-arrow-uturn-left" />{gettext("Soltar posições")}
        </button>
      </div>
    </div>

    <p class="ba-canvas-hint" data-bg-hint role="status" hidden></p>

    <div class="ba-editor__zoom ba-float" role="toolbar" aria-label={gettext("Zoom do diagrama")}>
      <button
        type="button"
        class="ba-btn ba-btn--icon ba-btn--sm"
        data-bg-control="zoom-out"
        aria-label={gettext("Afastar")}
        title={gettext("Afastar")}
      >
        <.icon name="hero-minus" />
      </button>
      <span class="ba-float__val" data-bg-display="zoom">100%</span>
      <button
        type="button"
        class="ba-btn ba-btn--icon ba-btn--sm"
        data-bg-control="zoom-in"
        aria-label={gettext("Aproximar")}
        title={gettext("Aproximar")}
      >
        <.icon name="hero-plus" />
      </button>
      <span class="ba-float__sep"></span>
      <button
        type="button"
        class="ba-btn ba-btn--icon ba-btn--sm"
        data-bg-control="fit"
        aria-label={gettext("Enquadrar (F)")}
        title={gettext("Enquadrar (F)")}
      >
        <.icon name="hero-arrows-pointing-out" />
      </button>
    </div>
    """
  end

  attr :error, :string, default: nil

  # Importar Mermaid/PlantUML: o resultado vira o texto do editor (e o Ctrl+Z
  # desfaz); salvar continua sendo um passo à parte.
  defp import_dialog(assigns) do
    ~H"""
    <div class="ba-overlay" phx-window-keydown="import:close" phx-key="Escape">
      <.form
        for={%{}}
        as={:import}
        id="import-form"
        class="ba-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="import-title"
        phx-submit="import"
      >
        <div class="ba-modal__head">
          <h2 class="ba-modal__title" id="import-title">{gettext("Importar diagrama")}</h2>
          <button
            type="button"
            class="ba-btn ba-btn--icon ba-btn--ghost ba-btn--sm"
            phx-click="import:close"
            aria-label={gettext("Fechar")}
          >
            <.icon name="hero-x-mark" />
          </button>
        </div>
        <div class="ba-modal__body">
          <p class="ba-import__hint">
            {gettext(
              "Cole ou escolha um arquivo: um .brain exportado do Brainagram, um sequenceDiagram do Mermaid, ou um diagrama de sequência ou de componentes do PlantUML (este vira arquitetura). O que não converter vira comentário no topo do código."
            )}
          </p>
          <div class="ba-field">
            <label class="ba-field__label" for="import-format">{gettext("Formato")}</label>
            <select id="import-format" name="format" class="ba-input">
              <option value="auto">{gettext("Detectar automaticamente")}</option>
              <option value="mermaid">Mermaid</option>
              <option value="plantuml">PlantUML</option>
              <option value="brainagram">{gettext("Brainagram (.brain)")}</option>
            </select>
          </div>
          <div class="ba-field">
            <span class="ba-field__label">{gettext("Arquivo")}</span>
            <label class="ba-filepick" for="import-file">
              <.icon name="hero-document-arrow-up" class="ba-ico--16" />
              <span data-file-name>{gettext("Escolher arquivo (.brain, .mmd, .puml)…")}</span>
            </label>
            <input
              type="file"
              id="import-file"
              class="ba-filepick__input"
              accept=".brain,.mmd,.mermaid,.puml,.plantuml,.txt"
              phx-hook="ReadFileInto"
              data-target="import-text"
            />
          </div>
          <div class="ba-field">
            <label class="ba-field__label" for="import-text">{gettext("Texto do diagrama")}</label>
            <textarea
              id="import-text"
              name="text"
              class="ba-input ba-input--area ba-import__text"
              spellcheck="false"
              placeholder={
                gettext("sequenceDiagram\n    Cliente->>API: POST /pedido\n    API-->>Cliente: 201")
              }
              phx-mounted={JS.focus()}
              aria-invalid={@error && "true"}
            ></textarea>
            <p :if={@error} class="ba-field__error">
              <.icon name="hero-exclamation-triangle" class="ba-ico--16" />{@error}
            </p>
          </div>
          <.input
            type="checkbox"
            id="import-organize"
            name="organize"
            value={true}
            label={gettext("Organizar as setas (diagramas de arquitetura)")}
          />
        </div>
        <div class="ba-modal__foot">
          <span class="ba-spacer"></span>
          <.button type="button" phx-click="import:close">{gettext("Cancelar")}</.button>
          <.button type="submit" variant="primary" id="import-submit">
            <.icon name="hero-arrow-down-tray" />{gettext("Importar")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp transport(assigns) do
    ~H"""
    <footer class="ba-player" role="group" aria-label={gettext("Reprodução")}>
      <div class="ba-player__transport">
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--ghost"
          data-bg-control="restart"
          aria-label={gettext("Reiniciar (R)")}
          title={gettext("Reiniciar (R)")}
        >
          <.icon name="hero-arrow-path" />
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--ghost"
          data-bg-control="prev"
          aria-label={gettext("Passo anterior (←)")}
          title={gettext("Passo anterior (←)")}
        >
          <.icon name="hero-backward" />
        </button>
        <button
          type="button"
          class="ba-play"
          data-bg-control="toggle"
          aria-label={gettext("Tocar (Espaço)")}
          title={gettext("Tocar / pausar (Espaço)")}
        >
          <span data-bg-play-icon="play"><.icon name="hero-play-mini" /></span>
          <span data-bg-play-icon="pause" hidden><.icon name="hero-pause-mini" /></span>
        </button>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--ghost"
          data-bg-control="next"
          aria-label={gettext("Próximo passo (→)")}
          title={gettext("Próximo passo (→)")}
        >
          <.icon name="hero-forward" />
        </button>
      </div>

      <%!-- o controle nativo (teclado, leitor de tela) fica por cima da faixa
           segmentada por passo, que o JS monta a cada cena --%>
      <div class="ba-scrubber">
        <div class="ba-scrubber__segs" data-bg-scrub-segs aria-hidden="true"></div>
        <input
          type="range"
          min="0"
          max="1000"
          value="0"
          data-bg-control="scrub"
          class="ba-range"
          aria-label={gettext("Posição da animação")}
        />
      </div>

      <span class="ba-time" data-bg-display="time">0.0 s</span>
      <span class="ba-player__sep"></span>

      <select class="ba-select" data-bg-control="speed" aria-label={gettext("Velocidade")}>
        <option value="0.5">{gettext("0,5×")}</option>
        <option value="1" selected>1×</option>
        <option value="1.5">{gettext("1,5×")}</option>
        <option value="2">2×</option>
      </select>

      <button
        type="button"
        class="ba-btn ba-btn--icon ba-btn--sm"
        data-bg-control="loop"
        aria-pressed="false"
        aria-label={gettext("Repetir em loop")}
        title={gettext("Repetir em loop")}
      >
        <.icon name="hero-arrow-path-rounded-square" />
      </button>

      <%!-- só aparece quando o painel de passos vira gaveta (telas estreitas) --%>
      <button
        type="button"
        class="ba-btn ba-btn--sm ba-player__steps"
        data-bg-control="steps-drawer"
        aria-expanded="false"
        aria-controls="steps-pane"
        title={gettext("Mostrar os passos")}
      >
        <.icon name="hero-queue-list" /><span>{gettext("Passos")}</span>
      </button>
    </footer>
    """
  end

  attr :scene, :map, required: true

  # Visualmente, só os tópicos (número, título, quantidade). As mensagens de
  # cada passo ("quem → quem · o quê") ficam só para leitor de tela, que não
  # alcança o conteúdo do SVG — a alternativa textual do diagrama.
  defp steps_pane(assigns) do
    labels = Map.new(assigns.scene.nodes, &{&1.id, &1.label || &1.id})
    edges = Map.new(assigns.scene.edges, &{&1.id, &1})
    assigns = assign(assigns, labels: labels, edges: edges)

    ~H"""
    <aside
      id="steps-pane"
      class="ba-panel ba-editor__steps"
      aria-label={gettext("Passos")}
      phx-mounted={JS.ignore_attributes(["data-open"])}
    >
      <div class="ba-panel__head">
        <h2 class="ba-panel__title">{gettext("Passos")}</h2>
        <span class="ba-time ba-editor__stepcount" data-bg-display="step-count">
          — / {length(@scene.steps)}
        </span>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost ba-editor__stepsclose"
          data-bg-control="steps-drawer"
          aria-label={gettext("Fechar os passos")}
        >
          <.icon name="hero-x-mark" class="ba-ico--16" />
        </button>
      </div>

      <ol class="ba-steps">
        <li :for={step <- @scene.steps}>
          <button type="button" class="ba-step" data-bg-step={step.index}>
            <span class="ba-step__num" aria-hidden="true">{step.index + 1}</span>
            <span>
              <span class="ba-step__title">{step_label(step.label)}</span>
              <span class="ba-step__meta">{message_count(step.edge_ids)}</span>
              <span class="ba-step__bar" aria-hidden="true"><i data-bg-step-bar={step.index}></i></span>
            </span>
          </button>
          <%!-- as mensagens do passo, só para leitor de tela (fora do botão) --%>
          <ol :if={step.edge_ids != []} class="ba-sr">
            <li :for={id <- step.edge_ids} :if={edge = @edges[id]} data-bg-msg={id}>
              {@labels[edge.from]} → {@labels[edge.to]}<span :if={edge.label not in [nil, ""]}> · {edge.label}</span>
            </li>
          </ol>
        </li>
      </ol>

      <div class="ba-panel__foot">
        <p class="ba-editor__stepnow" data-bg-display="step">—</p>
      </div>
    </aside>
    """
  end

  # A cena recém-compilada traz `kind` como átomo; a que vem do banco, como string.
  defp kind_label(kind) when is_atom(kind), do: kind |> Atom.to_string() |> kind_label()
  defp kind_label("sequence"), do: gettext("Sequência")
  defp kind_label("architecture"), do: gettext("Arquitetura")
  defp kind_label(kind), do: kind

  defp crumb_path(%{project: project}) when is_binary(project), do: ~p"/?project=#{project}"
  defp crumb_path(_diagram), do: ~p"/"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp kind_icon(kind) when kind in [:architecture, "architecture"], do: "hero-rectangle-group"
  defp kind_icon(_kind), do: "hero-bars-3"

  defp visibility_hint("public"),
    do: gettext("Aparece na galeria pública. Clique para tornar privado.")

  defp visibility_hint(_), do: gettext("Só abre quem tem o link. Clique para tornar público.")

  defp error_count(errors), do: ngettext("1 erro", "%{count} erros", length(errors))

  defp message_count(ids), do: ngettext("1 mensagem", "%{count} mensagens", length(ids))

  # Rótulos que o próprio domínio dá a um passo sem nome.
  defp step_label("Contexto inicial"), do: gettext("Contexto inicial")
  defp step_label(label), do: label

  # Os exemplos vêm do catálogo com nome em português; o inglês mora em
  # `priv/gettext/en/LC_MESSAGES/examples.po`.
  defp example_name(name), do: Gettext.dgettext(BrainagramWeb.Gettext, "examples", name)
end

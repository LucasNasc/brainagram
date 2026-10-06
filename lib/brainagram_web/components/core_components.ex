defmodule BrainagramWeb.CoreComponents do
  @moduledoc """
  Componentes de interface do Brainagram.

  O estilo vem de CSS puro escrito à mão (`assets/css/*.css`), com os tokens do
  design system "Brainagram". Não há framework de CSS: cada componente aqui usa
  as classes `.ba-*` definidas em `components.css` e `layout.css`.

    * [Heroicons](https://heroicons.com) - ver `icon/1`, renderizados como SVG
      inline a partir de `deps/heroicons` em tempo de compilação.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      o sistema de componentes do Phoenix. Alguns, como `<.link>` e `<.form>`,
      são definidos lá.
  """
  use Phoenix.Component
  use Gettext, backend: BrainagramWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renderiza um aviso de flash como toast.

  ## Exemplos

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Bem-vindo de volta.</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role={if @kind == :error, do: "alert", else: "status"}
      {@rest}
    >
      <div class={[
        "ba-toast",
        @kind == :info && "ba-toast--success",
        @kind == :error && "ba-toast--danger"
      ]}>
        <.icon :if={@kind == :info} name="hero-check-circle" />
        <.icon :if={@kind == :error} name="hero-exclamation-triangle" />
        <p class="ba-toast__msg">
          <strong :if={@title} class="ba-toast__title">{@title}</strong>
          {msg}
        </p>
        <button
          type="button"
          class="ba-btn ba-btn--icon ba-btn--sm ba-btn--ghost ba-toast__close"
          aria-label={gettext("Fechar")}
        >
          <.icon name="hero-x-mark" class="ba-ico--16" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renderiza um botão, com suporte a navegação.

  O primário (`variant="primary"`) aparece uma vez por tela.

  ## Exemplos

      <.button>Cancelar</.button>
      <.button phx-click="go" variant="primary">Salvar</.button>
      <.button navigate={~p"/"} variant="ghost">Início</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil
  attr :variant, :string, values: [nil | ~w(primary ghost danger)], default: nil
  attr :size, :string, values: [nil | ~w(sm lg)], default: nil
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "ba-btn",
        assigns.variant && "ba-btn--#{assigns.variant}",
        assigns.size && "ba-btn--#{assigns.size}",
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="ba-field">
      <label class="ba-check">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="ba-field">
      <label :if={@label} class="ba-field__label" for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        class={[@class || "ba-input", @errors != [] && @error_class]}
        aria-invalid={@errors != [] && "true"}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="ba-field">
      <label :if={@label} class="ba-field__label" for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={[@class || "ba-input ba-input--area", @errors != [] && @error_class]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="ba-field">
      <label :if={@label} class="ba-field__label" for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[@class || "ba-input", @errors != [] && @error_class]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="ba-field__error">
      <.icon name="hero-exclamation-triangle" class="ba-ico--16" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renderiza um cabeçalho com título.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="ba-header">
      <div>
        <h1 class="ba-header__title">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="ba-header__subtitle">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []}>{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="ba-table">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="ba-sr">Ações</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            data-clickable={@row_click && true}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []}>
            <div class="ba-table__actions">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="ba-list">
      <li :for={item <- @item}>
        <div class="ba-list__title">{item.title}</div>
        <div>{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Símbolo do Brainagram: dois nós ligados por uma aresta formando um "b", com
  o impulso na barriga. Com `wordmark`, acompanha o logotipo em minúsculas.
  """
  attr :size, :integer, default: 24
  attr :wordmark, :boolean, default: false
  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <span class={["ba-logo", @class]}>
      <svg
        class="ba-logo__mark"
        width={@size}
        height={@size}
        viewBox="0 0 32 32"
        aria-hidden="true"
      >
        <circle class="ink" cx="9" cy="6" r="3.5" />
        <path class="ink-s" d="M9 9.5V21" stroke-width="3" stroke-linecap="round" />
        <circle class="ink-s" cx="16.5" cy="21" r="7.5" stroke-width="3" />
        <circle class="imp" cx="21.8" cy="15.7" r="3.4" />
      </svg>
      <span :if={@wordmark} class="ba-wordmark">brainagram</span>
    </span>
    """
  end

  # Heroicons: lidos de deps/heroicons em tempo de compilação e embutidos como
  # SVG inline. Sufixos: nenhum = outline 24, -solid = solid 24, -mini = solid
  # 20, -micro = solid 16.
  # Com `sparse: "optimized"` o caminho do dep já aponta para optimized/.
  @heroicons_path (
                    dep = Mix.Project.deps_paths() |> Map.fetch!(:heroicons)
                    if File.dir?(Path.join(dep, "24")), do: dep, else: Path.join(dep, "optimized")
                  )
  @heroicon_sets [
    {"", "24/outline"},
    {"-solid", "24/solid"},
    {"-mini", "20/solid"},
    {"-micro", "16/solid"}
  ]
  @heroicon_skip ~w(xmlns aria-hidden data-slot)

  @heroicons (for {suffix, dir} <- @heroicon_sets,
                  file <- Path.wildcard(Path.join([@heroicons_path, dir, "*.svg"])),
                  into: %{} do
                [_, attrs, inner] = Regex.run(~r{<svg([^>]*)>(.*)</svg>}s, File.read!(file))

                svg_attrs =
                  for [_, key, value] <- Regex.scan(~r/([\w:-]+)="([^"]*)"/, attrs),
                      key not in @heroicon_skip,
                      do: {key, value}

                {"hero-" <> Path.basename(file, ".svg") <> suffix,
                 {svg_attrs, String.trim(inner)}}
              end)

  @doc """
  Renders a [Heroicon](https://heroicons.com) como SVG inline.

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid, mini and micro
  may be applied by using the `-solid`, `-mini` and `-micro` suffix.

  O ícone herda a cor (`currentColor`) e mede 20px por padrão (`.ba-ico`);
  use `ba-ico--16`, `ba-ico--12` ou `ba-ico--24` para outros tamanhos.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ba-ico--16" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _ = name} = assigns) do
    {svg_attrs, inner} =
      Map.get_lazy(@heroicons, name, fn ->
        raise ArgumentError, "Heroicon desconhecido: #{name}"
      end)

    assigns = assign(assigns, svg_attrs: svg_attrs, inner: Phoenix.HTML.raw(inner))

    ~H"""
    <svg class={["ba-ico", @class]} aria-hidden="true" {@svg_attrs}>{@inner}</svg>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 280,
      transition: {"ba-tr-in", "ba-tr-hidden", "ba-tr-shown"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 180,
      transition: {"ba-tr-out", "ba-tr-shown", "ba-tr-hidden"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(BrainagramWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BrainagramWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

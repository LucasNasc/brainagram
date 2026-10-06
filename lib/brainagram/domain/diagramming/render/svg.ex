defmodule Brainagram.Domain.Diagramming.Render.Svg do
  @moduledoc """
  Cena → SVG autocontido, fora do navegador.

  É o estado final do diagrama (todas as mensagens concluídas), o mesmo que o
  botão "Exportar SVG" produz no editor — para rodar em CI com
  `mix brainagram.render`, sem Phoenix nem JavaScript.

  Espelha `assets/js/brainagram/renderer.js` (estrutura e classes `.bg-*`) e
  `assets/css/diagram.css` (regras), com as cores do tema claro do design
  system já resolvidas: o arquivo abre igual em qualquer visualizador.
  """

  alias Brainagram.Domain.Diagramming.Scene

  @colors %{
    canvas: "#fbfbf9",
    surface: "#ffffff",
    surface3: "#e7e7e1",
    text: "#16161b",
    muted: "#5f5f69",
    stroke: "#84848e",
    group_bg: "#f3f3ef",
    note_bg: "#fff3bf",
    note_border: "#c9a52a",
    note_text: "#4a3b00",
    pending: "#898993",
    sync: "#3a3a48",
    return: "#7e7e8a",
    async: "#0c8577",
    fail: "#cc3a31",
    actor: "#0068a3",
    service: "#2f86bf",
    database: "#00805d",
    queue: "#a86f00",
    external: "#b0508a",
    neutral: "#5f5f69"
  }

  @font ~s["Geist", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif]

  @doc """
  Desenha a cena. `background: false` deixa o fundo transparente — é o que a
  miniatura dos cards usa, para assentar sobre o pontilhado do card (e, no
  tema escuro, só o traço ser invertido).
  """
  @spec render(Scene.t(), keyword()) :: String.t()
  def render(%Scene{} = scene, opts \\ []) do
    c = @colors
    background = Keyword.get(opts, :background, true)

    [
      ~s[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{scene.width} #{scene.height}" ],
      ~s[width="#{scene.width}" height="#{scene.height}" role="img" aria-label="#{esc(scene.title || "Diagrama")}">],
      "<style>",
      style(c),
      "</style>",
      defs(c),
      if(background, do: ~s[<rect width="100%" height="100%" fill="#{c.canvas}"/>], else: ""),
      groups(scene),
      bands(scene),
      lifelines(scene),
      activations(scene),
      nodes(scene),
      edges(scene),
      notes(scene),
      "</svg>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp style(c) do
    """
    text{font-family:#{@font}}
    .bg-group-box{fill:#{c.group_bg};stroke:#{c.stroke};stroke-width:1;stroke-dasharray:4 4}
    .bg-group-label,.bg-band-label{fill:#{c.muted};font-size:11px;font-weight:600;letter-spacing:.06em;text-transform:uppercase}
    .bg-band-dot{fill:#{c.surface};stroke:#{c.stroke}}
    .bg-band-num{fill:#{c.muted};font-size:11px;font-weight:600;text-anchor:middle}
    .bg-lifeline{stroke:#{c.pending};stroke-width:1;stroke-dasharray:2 4;stroke-linecap:round}
    .bg-activation{fill:#{c.surface3};stroke:#{c.stroke};stroke-width:1}
    .bg-node-box{fill:#{c.surface};stroke:#{c.stroke};stroke-width:1}
    .is-external .bg-node-box{stroke-dasharray:5 4}
    .is-boundary .bg-node-box{stroke-dasharray:2 3;fill:#{c.group_bg}}
    .bg-node-label{fill:#{c.text};font-size:14px;font-weight:600;letter-spacing:-.01em}
    .bg-glyph{fill:none;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
    .bg-edge-track{fill:none;stroke-width:1.5}
    .bg-edge-line{fill:none;stroke-width:1.5;stroke-linecap:round}
    .is-return .bg-edge-track,.is-fail .bg-edge-track{stroke-dasharray:6 4}
    .is-async .bg-edge-track{stroke-dasharray:.01 4.5;stroke-linecap:round;stroke-width:2}
    .is-return .bg-edge-line,.is-async .bg-edge-line,.is-fail .bg-edge-line{stroke-opacity:0}
    .bg-edge-label{fill:#{c.text};font-size:12px;font-weight:500}
    .bg-edge-label-bg{fill:#{c.canvas}}
    .bg-note-box{fill:#{c.note_bg};stroke:#{c.note_border};stroke-width:1}
    .bg-payload-chip-box{fill:#{c.surface};stroke-opacity:.55;stroke-width:1;stroke-linejoin:round}
    .bg-payload-chip-text{fill:#{c.muted};font-family:ui-monospace,"JetBrains Mono",SFMono-Regular,Menlo,Consolas,monospace;font-size:11px;white-space:pre}
    .bg-note-text{fill:#{c.note_text};font-size:12px}
    """
  end

  defp defs(c) do
    markers =
      for {kind, color} <- [sync: c.sync, return: c.return, async: c.async, fail: c.fail] do
        head =
          case kind do
            k when k in [:return, :async] ->
              ~s[<path d="M 0 0 L 10 5 L 0 10" fill="none" stroke="#{color}" stroke-width="1.6"/>]

            :fail ->
              ~s[<circle cx="5" cy="5" r="4.2" fill="#{c.canvas}" stroke="#{color}" stroke-width="1.2"/>] <>
                ~s[<path d="M 3.3 3.3 L 6.7 6.7 M 6.7 3.3 L 3.3 6.7" stroke="#{color}" stroke-width="1.2"/>]

            :sync ->
              ~s[<path d="M 0 0 L 10 5 L 0 10 z" fill="#{color}"/>]
          end

        ~s[<marker id="bg-arrow-#{kind}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse" markerUnits="strokeWidth">#{head}</marker>]
      end

    ["<defs>", markers, "</defs>"]
  end

  defp groups(scene) do
    for g <- scene.groups do
      ~s[<g class="bg-group"><rect class="bg-group-box" x="#{g.x}" y="#{g.y}" width="#{g.w}" height="#{g.h}" rx="14"/>] <>
        ~s[<text class="bg-group-label" x="#{g.x + 12}" y="#{g.y + 16}">#{esc(g.label)}</text></g>]
    end
  end

  defp bands(%Scene{kind: :sequence} = scene) do
    for step <- scene.steps do
      ~s[<g class="bg-band"><circle class="bg-band-dot" cx="26" cy="#{step.y + 11}" r="11"/>] <>
        ~s[<text class="bg-band-num" x="26" y="#{step.y + 15}">#{step.index + 1}</text>] <>
        ~s[<text class="bg-band-label" x="46" y="#{step.y + 15}">#{esc(step.label)}</text></g>]
    end
  end

  defp bands(_scene), do: []

  defp lifelines(%Scene{kind: :sequence} = scene) do
    for n <- scene.nodes do
      ~s[<line class="bg-lifeline" x1="#{n.cx}" y1="#{n.lifeline_y1}" x2="#{n.cx}" y2="#{n.lifeline_y2}"/>]
    end
  end

  defp lifelines(_scene), do: []

  defp activations(scene) do
    by_id = Map.new(scene.nodes, &{&1.id, &1})

    for bar <- scene.activations, node = by_id[bar.node], node != nil do
      ~s[<rect class="bg-activation" x="#{node.cx - 6 + bar.depth * 6}" y="#{bar.y1}" width="12" height="#{max(bar.y2 - bar.y1, 16)}" rx="3"/>]
    end
  end

  defp nodes(scene) do
    for n <- scene.nodes do
      kind = n.kind
      rx = if kind in [:actor, :queue], do: div(n.h, 2), else: 12

      ~s[<g class="bg-node is-#{kind}"><rect class="bg-node-box" x="#{n.x}" y="#{n.y}" width="#{n.w}" height="#{n.h}" rx="#{rx}"/>] <>
        glyph(kind, n.x + 20, n.y + n.h / 2) <>
        ~s[<text class="bg-node-label" x="#{n.x + 36}" y="#{n.y + n.h / 2 + 5}">#{esc(n.label)}</text></g>]
    end
  end

  # Os mesmos glifos de renderer.js, na cor do tipo.
  defp glyph(kind, x, y) do
    color = Map.get(@colors, kind, @colors.neutral)

    shapes =
      case kind do
        :actor ->
          ~s[<circle cx="0" cy="-5" r="3.6"/><path d="M 0 -1 L 0 6 M -4.5 2 L 4.5 2 M 0 6 L -3.5 11 M 0 6 L 3.5 11"/>]

        :database ->
          ~s[<ellipse cx="0" cy="-4" rx="6" ry="2.4"/><path d="M -6 -4 L -6 6 A 6 2.4 0 0 0 6 6 L 6 -4"/>]

        :queue ->
          ~s[<path d="M -6 -5 L -6 6 M -2 -5 L -2 6 M 2 -5 L 2 6 M 6 -5 L 6 6"/>]

        :external ->
          ~s[<path d="M -6 -5 L 6 -5 L 6 6 L -6 6 Z" stroke-dasharray="3 2"/><path d="M -2 0 L 2 0"/>]

        :service ->
          ~s[<path d="M -6 -5 L 6 -5 L 6 6 L -6 6 Z"/><path d="M -6 -1.5 L 6 -1.5"/>]

        _ ->
          ~s[<rect x="-6" y="-5" width="12" height="11" rx="2"/><path d="M -3 -1 L 3 -1 M -3 2 L 1 2"/>]
      end

    ~s[<g class="bg-glyph" stroke="#{color}" transform="translate(#{x} #{y})">#{shapes}</g>]
  end

  defp edges(scene) do
    for e <- scene.edges do
      color = Map.fetch!(@colors, e.arrow)

      label =
        if e.label do
          w = Scene.text_width(e.label, 12) + 12

          x =
            case e.label_anchor do
              "middle" -> e.label_x - w / 2
              "end" -> e.label_x - w + 6
              _ -> e.label_x - 6
            end

          ~s[<rect class="bg-edge-label-bg" x="#{r(x)}" y="#{e.label_y - 13}" width="#{r(w)}" height="18" rx="4"/>] <>
            ~s[<text class="bg-edge-label" x="#{e.label_x}" y="#{e.label_y}" text-anchor="#{e.label_anchor}">#{esc(e.label)}</text>]
        else
          ""
        end

      ~s[<g class="bg-edge is-#{e.arrow}"><path class="bg-edge-track" d="#{e.path}" stroke="#{color}"/>] <>
        ~s[<path class="bg-edge-line" d="#{e.path}" stroke="#{color}" marker-end="url(#bg-arrow-#{e.arrow})"/>] <>
        label <> payload(Map.get(e, :payload), color) <> "</g>"
    end
  end

  # O payload fora do navegador: o chip minimizado — o mesmo estado padrão da
  # tela (`drawPayload` no renderer.js). O conteúdo inteiro vai no <title>.
  defp payload(nil, _color), do: ""

  defp payload(%{chip: chip} = p, color) do
    # o "▾" na borda direita, como na tela (onde o "· N linhas" ocupa o meio)
    more =
      if chip.count > 1,
        do:
          ~s[<text class="bg-payload-chip-text" x="#{chip.x + chip.w - 16}" y="#{chip.y + 14}">▾</text>],
        else: ""

    shape = Map.merge(chip, %{tip_x: p.tip_x, tip_y: p.tip_y})

    ~s[<g class="bg-payload-chip"><title>#{esc(p.text)}</title>] <>
      ~s[<path class="bg-payload-chip-box" d="#{balloon(shape, 10)}" stroke="#{color}"/>] <>
      ~s[<text class="bg-payload-chip-text" x="#{chip.x + 10}" y="#{chip.y + 14}">#{esc(chip.label)}</text>#{more}</g>]
  end

  defp balloon(%{x: x, y: y, w: w, h: h, tip_x: tx, tip_y: ty}, rr) do
    base = tx |> max(x + 14) |> min(x + w - 14)

    "M #{x + rr} #{y} L #{base - 6} #{y} L #{tx} #{ty} L #{base + 6} #{y} L #{x + w - rr} #{y} " <>
      "Q #{x + w} #{y} #{x + w} #{y + rr} L #{x + w} #{y + h - rr} Q #{x + w} #{y + h} #{x + w - rr} #{y + h} " <>
      "L #{x + rr} #{y + h} Q #{x} #{y + h} #{x} #{y + h - rr} L #{x} #{y + rr} Q #{x} #{y} #{x + rr} #{y} Z"
  end

  defp notes(scene) do
    for n <- scene.notes do
      ~s[<g class="bg-note"><rect class="bg-note-box" x="#{n.x}" y="#{n.y}" width="#{n.w}" height="#{n.h}" rx="8"/>] <>
        ~s[<text class="bg-note-text" x="#{n.x + 14}" y="#{n.y + n.h / 2 + 5}">#{esc(n.text)}</text></g>]
    end
  end

  defp r(n), do: round(n)

  defp esc(nil), do: ""

  defp esc(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

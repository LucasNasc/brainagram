defmodule Brainagram.Application.Handlers.EditDiagram do
  @moduledoc """
  Handler único dos comandos de autoria do canvas (spec 001, §6–7).

  Todos seguem o mesmo trilho: carrega o agregado, traduz o comando numa edição
  de texto (`Authoring`) e pede a transição genérica `Diagram.apply_edit/2`.
  O agregado decide — inclusive que texto idêntico não gera evento, então
  arrastar um nó e soltar no mesmo lugar não grava nem publica nada.

  Um handler para doze comandos não é atalho: a regra é uma só ("gesto vira
  edição cirúrgica do fonte"), e o que varia — *qual* edição — mora no domínio.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.{
    AddNode,
    ChangeEdgeArrow,
    ClearLayoutHints,
    ConnectNodes,
    MoveNodeToGroup,
    PinNode,
    RelabelEdge,
    RemoveEdge,
    RemoveNode,
    RenameDiagram,
    RenameNodeLabel,
    UntangleLayout
  }

  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.{Authoring, Diagram}

  @impl true
  def handle(%{slug: slug} = command) do
    with {:ok, diagram} <- Support.load(slug),
         {:ok, updated, events} <- Diagram.apply_edit(diagram, edit(command)) do
      Support.persist_if_changed(diagram, updated, events)
    end
  end

  defp edit(%PinNode{} = c), do: &Authoring.pin_node(&1, c.node_id, {c.x, c.y})

  defp edit(%AddNode{} = c) do
    at = if c.x && c.y, do: {c.x, c.y}
    &Authoring.add_node(&1, %{label: c.label, kind: c.kind, group: c.group, at: at})
  end

  defp edit(%ConnectNodes{} = c) do
    &Authoring.connect_nodes(&1, %{
      from: c.from,
      to: c.to,
      arrow: c.arrow,
      label: c.label,
      step: c.step
    })
  end

  defp edit(%RenameNodeLabel{} = c), do: &Authoring.rename_node_label(&1, c.node_id, c.label)
  defp edit(%RelabelEdge{} = c), do: &Authoring.relabel_edge(&1, c.edge_id, c.label)
  defp edit(%ChangeEdgeArrow{} = c), do: &Authoring.change_edge_arrow(&1, c.edge_id, c.arrow)
  defp edit(%RemoveNode{} = c), do: &Authoring.remove_node(&1, c.node_id)
  defp edit(%RemoveEdge{} = c), do: &Authoring.remove_edge(&1, c.edge_id)
  defp edit(%MoveNodeToGroup{} = c), do: &Authoring.move_node_to_group(&1, c.node_id, c.group)
  defp edit(%ClearLayoutHints{}), do: &Authoring.clear_layout_hints/1
  defp edit(%UntangleLayout{}), do: &Authoring.untangle/1
  defp edit(%RenameDiagram{} = c), do: &Authoring.rename_title(&1, c.title)
end

defmodule Botgrade.Game.CampaignState do
  alias Botgrade.Game.{MapNode, Card}

  @type t :: %__MODULE__{
          id: String.t(),
          nodes: %{String.t() => MapNode.t()},
          current_node_id: String.t(),
          player_cards: [Card.t()],
          player_resources: map(),
          visited_nodes: [String.t()],
          combat_id: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  @enforce_keys [:id, :nodes, :current_node_id, :player_cards]
  defstruct [
    :id,
    :nodes,
    :current_node_id,
    :player_cards,
    player_resources: %{},
    visited_nodes: [],
    combat_id: nil,
    created_at: nil,
    updated_at: nil
  ]
end

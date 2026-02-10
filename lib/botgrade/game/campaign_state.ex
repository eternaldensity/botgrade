defmodule Botgrade.Game.CampaignState do
  alias Botgrade.Game.{Space, Tile, Zone, Card}

  @type t :: %__MODULE__{
          id: String.t(),
          seed: integer() | nil,
          zones: %{String.t() => Zone.t()},
          tiles: %{String.t() => Tile.t()},
          spaces: %{String.t() => Space.t()},
          current_space_id: String.t(),
          player_cards: [Card.t()],
          player_resources: map(),
          visited_spaces: [String.t()],
          combat_id: String.t() | nil,
          movement_points: non_neg_integer(),
          max_movement_points: non_neg_integer(),
          turn_number: pos_integer(),
          created_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  @enforce_keys [:id, :zones, :tiles, :spaces, :current_space_id, :player_cards]
  defstruct [
    :id,
    :zones,
    :tiles,
    :spaces,
    :current_space_id,
    :player_cards,
    seed: nil,
    player_resources: %{},
    visited_spaces: [],
    combat_id: nil,
    movement_points: 1,
    max_movement_points: 1,
    turn_number: 1,
    created_at: nil,
    updated_at: nil
  ]

  @doc "Calculate movement points from player's locomotion cards. Base speed 1 + locomotion bonuses."
  def calculate_movement_points(player_cards) do
    base_speed = 1

    locomotion_bonus =
      player_cards
      |> Enum.filter(&(&1.type == :locomotion and &1.damage != :destroyed))
      |> Enum.map(&Map.get(&1.properties, :speed_base, 0))
      |> Enum.sum()

    base_speed + locomotion_bonus
  end
end

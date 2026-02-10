defmodule Botgrade.Game.Space do
  @moduledoc """
  A single space on the campaign board. The atomic unit players move between.
  Spaces live within tiles, which live within zones.
  """

  @type space_type ::
          :empty | :enemy | :shop | :rest | :event | :scavenge | :start | :exit | :edge_connector
  @type enemy_behavior :: :stationary | :patrol

  @type t :: %__MODULE__{
          id: String.t(),
          type: space_type(),
          position: {number(), number()},
          zone_id: String.t(),
          connections: [String.t()],
          label: String.t(),
          enemy_type: String.t() | nil,
          enemy_behavior: enemy_behavior() | nil,
          enemy_patrol_path: [String.t()],
          encounter_range: non_neg_integer(),
          danger_rating: pos_integer(),
          cleared: boolean()
        }

  @enforce_keys [:id, :type, :position, :zone_id]
  defstruct [
    :id,
    :type,
    :position,
    :zone_id,
    connections: [],
    label: "",
    enemy_type: nil,
    enemy_behavior: nil,
    enemy_patrol_path: [],
    encounter_range: 1,
    danger_rating: 1,
    cleared: false
  ]
end

defmodule Botgrade.Game.MapNode do
  alias Botgrade.Game.Zone

  @type node_type :: :start | :combat | :shop | :rest | :event | :exit
  @type t :: %__MODULE__{
          id: String.t(),
          type: node_type(),
          position: {number(), number()},
          zone: Zone.t(),
          cleared: boolean(),
          edges: [String.t()],
          label: String.t(),
          enemy_type: String.t() | nil,
          danger_rating: pos_integer()
        }

  @enforce_keys [:id, :type, :position, :zone]
  defstruct [
    :id,
    :type,
    :position,
    :zone,
    cleared: false,
    edges: [],
    label: "",
    enemy_type: nil,
    danger_rating: 1
  ]
end

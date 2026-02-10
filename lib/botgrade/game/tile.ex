defmodule Botgrade.Game.Tile do
  @moduledoc """
  A tile fills a single zone and contains a set of connected spaces.
  Tiles connect to neighboring tiles via edge connector spaces.
  """

  alias Botgrade.Game.Space

  @type t :: %__MODULE__{
          id: String.t(),
          zone_id: String.t(),
          spaces: %{String.t() => Space.t()},
          edge_connectors: %{
            north: String.t() | nil,
            south: String.t() | nil,
            east: String.t() | nil,
            west: String.t() | nil
          },
          bounds: {number(), number(), number(), number()}
        }

  @enforce_keys [:id, :zone_id, :spaces, :bounds]
  defstruct [
    :id,
    :zone_id,
    :spaces,
    :bounds,
    edge_connectors: %{north: nil, south: nil, east: nil, west: nil}
  ]
end

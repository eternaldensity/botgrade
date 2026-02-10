defmodule Botgrade.Game.Zone do
  @type zone_type :: :industrial | :residential | :commercial
  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: zone_type(),
          danger_rating: pos_integer(),
          name: String.t(),
          grid_pos: {non_neg_integer(), non_neg_integer()} | nil,
          neighbors: [String.t()]
        }

  @enforce_keys [:type, :danger_rating, :name]
  defstruct [:id, :type, :danger_rating, :name, grid_pos: nil, neighbors: []]

  @zone_names %{
    industrial: ["Foundry District", "Scrapyard Row", "Factory Block", "Smelter Quarter"],
    residential: ["Haven Sector", "Shell District", "Quiet Block", "Shelter Row"],
    commercial: ["Market Strip", "Trade Hub", "Exchange Row", "Vendor Alley"]
  }

  @doc "Create a zone with a random name for the given type."
  def new(type, danger_rating) do
    name = Enum.random(@zone_names[type])
    %__MODULE__{type: type, danger_rating: danger_rating, name: name}
  end

  @doc "Create a zone with id, grid position, and a random name."
  def new(id, type, danger_rating, grid_pos) do
    name = Enum.random(@zone_names[type])
    %__MODULE__{id: id, type: type, danger_rating: danger_rating, name: name, grid_pos: grid_pos}
  end
end

defmodule Botgrade.Game.Zone do
  @type zone_type :: :industrial | :residential | :commercial
  @type t :: %__MODULE__{
          type: zone_type(),
          danger_rating: pos_integer(),
          name: String.t()
        }

  @enforce_keys [:type, :danger_rating, :name]
  defstruct [:type, :danger_rating, :name]

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
end

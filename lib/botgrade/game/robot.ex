defmodule Botgrade.Game.Robot do
  alias Botgrade.Game.Card

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          deck: [Card.t()],
          hand: [Card.t()],
          discard: [Card.t()],
          in_play: [Card.t()],
          available_dice: [map()],
          total_hp: non_neg_integer(),
          current_hp: non_neg_integer(),
          shield: non_neg_integer()
        }

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    deck: [],
    hand: [],
    discard: [],
    in_play: [],
    available_dice: [],
    total_hp: 0,
    current_hp: 0,
    shield: 0
  ]

  @spec new(String.t(), String.t(), [Card.t()]) :: t()
  def new(id, name, cards) do
    total_hp =
      cards
      |> Enum.filter(&(&1.type == :chassis))
      |> Enum.reduce(0, fn card, acc -> acc + Map.get(card.properties, :hp_max, 0) end)

    %__MODULE__{
      id: id,
      name: name,
      deck: Enum.shuffle(cards),
      total_hp: total_hp,
      current_hp: total_hp
    }
  end
end

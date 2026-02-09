defmodule Botgrade.Game.Robot do
  alias Botgrade.Game.Card

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          deck: [Card.t()],
          hand: [Card.t()],
          discard: [Card.t()],
          in_play: [Card.t()],
          installed: [Card.t()],
          available_dice: [map()],
          shield: non_neg_integer(),
          plating: non_neg_integer()
        }

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    deck: [],
    hand: [],
    discard: [],
    in_play: [],
    installed: [],
    available_dice: [],
    shield: 0,
    plating: 0
  ]

  @installed_types [:chassis, :cpu, :locomotion]

  @default_card_hp %{
    chassis: 4,
    cpu: 2,
    weapon: 3,
    armor: 3,
    battery: 2,
    capacitor: 2,
    locomotion: 2
  }

  @spec new(String.t(), String.t(), [Card.t()]) :: t()
  def new(id, name, cards) do
    cards = Enum.map(cards, &initialize_card_hp/1)

    {installed, deck_cards} =
      Enum.split_with(cards, &(&1.type in @installed_types))

    %__MODULE__{
      id: id,
      name: name,
      deck: Enum.shuffle(deck_cards),
      installed: installed
    }
  end

  @spec total_hp(t()) :: non_neg_integer()
  def total_hp(robot) do
    robot.installed
    |> Enum.filter(&(&1.type == :chassis))
    |> Enum.reduce(0, fn card, acc ->
      acc + Map.get(card.properties, :card_hp, @default_card_hp[:chassis])
    end)
  end

  @spec current_hp(t()) :: non_neg_integer()
  def current_hp(robot) do
    robot.installed
    |> Enum.filter(&(&1.type == :chassis and &1.current_hp > 0))
    |> Enum.reduce(0, fn card, acc -> acc + card.current_hp end)
  end

  defp initialize_card_hp(%Card{current_hp: hp} = card) when not is_nil(hp), do: card

  defp initialize_card_hp(%Card{} = card) do
    card_hp = Map.get(card.properties, :card_hp, Map.get(@default_card_hp, card.type, 2))
    %{card | current_hp: card_hp}
  end
end

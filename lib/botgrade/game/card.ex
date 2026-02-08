defmodule Botgrade.Game.Card do
  @type card_type :: :battery | :capacitor | :weapon | :armor | :locomotion | :chassis

  @type dice_condition ::
          {:min, pos_integer()}
          | {:max, pos_integer()}
          | {:exact, pos_integer()}
          | :even
          | :odd

  @type dice_slot :: %{
          id: String.t(),
          condition: dice_condition() | nil,
          assigned_die: map() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: card_type(),
          damage: :intact | :damaged | :destroyed,
          properties: map(),
          dice_slots: [dice_slot()]
        }

  @enforce_keys [:id, :name, :type]
  defstruct [:id, :name, :type, damage: :intact, properties: %{}, dice_slots: []]

  @spec meets_condition?(dice_condition() | nil, pos_integer()) :: boolean()
  def meets_condition?(nil, _value), do: true
  def meets_condition?({:min, min}, value), do: value >= min
  def meets_condition?({:max, max}, value), do: value <= max
  def meets_condition?({:exact, n}, value), do: value == n
  def meets_condition?(:even, value), do: rem(value, 2) == 0
  def meets_condition?(:odd, value), do: rem(value, 2) == 1
end
